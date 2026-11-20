#!/usr/bin/env bash
# Extra QA beyond the required gates: static analysis, compiler warnings,
# sanitizer test passes, coverage, and strict lint. Writes a report and, by
# default, never fails: a check blocks only when its name is in QA_BLOCKING.
#
#   scripts/qa/deep-qa.sh                    run every check, report only
#   QA_BLOCKING="asan tsan" scripts/qa/deep-qa.sh   fail if asan or tsan fails
#   QA_CHECKS="coverage swift-format" scripts/qa/deep-qa.sh   run a subset
#
# Checks: analyze, warnings, asan, tsan, coverage, swift-format, shellcheck,
# actionlint. analyze needs xcodegen on PATH; shellcheck and actionlint are
# skipped (not failed) when the tool is missing.
#
# Output: build/qa/report.md, build/qa/report.json, build/qa/<check>.log.
# In GitHub Actions the report is also added to the job summary.
set -uo pipefail

ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
cd "$ROOT" || exit 2
OUT="build/qa"
rm -rf "$OUT"
mkdir -p "$OUT"
ALL_CHECKS="analyze warnings asan tsan coverage swift-format shellcheck actionlint"
CHECKS="${QA_CHECKS:-$ALL_CHECKS}"
BLOCKING=" ${QA_BLOCKING:-} "
RESULTS="$OUT/results.tsv"
: > "$RESULTS"

# name, status (pass|fail|skip), detail
record() { printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$RESULTS"; echo "[$2] $1: $3"; }
wants() { case " $CHECKS " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }
count_lines() { if [ -s "$1" ]; then wc -l < "$1" | tr -d ' '; else echo 0; fi; }

# --- analyze + warnings (one xcodebuild analyze pass feeds both) ------------
if wants analyze || wants warnings; then
  log="$OUT/analyze.log"
  if ! command -v xcodegen >/dev/null 2>&1; then
    wants analyze && record analyze skip "xcodegen not on PATH"
    wants warnings && record warnings skip "xcodegen not on PATH"
  else
    xcodegen generate --spec project.yml >"$OUT/xcodegen.log" 2>&1
    xcodebuild analyze \
      -project Abendrot.xcodeproj -scheme Abendrot -configuration Debug \
      -destination 'generic/platform=macOS' -derivedDataPath build/QA-Analyze \
      -onlyUsePackageVersionsFromResolvedFile \
      CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" >"$log" 2>&1
    rc=$?
    # Unique "path:line:col: warning: ..." lines, split by language.
    grep -E '^[^ ]+:[0-9]+:[0-9]+: warning: ' "$log" | sort -u > "$OUT/warnings-all.txt" || true
    grep -E '\.(c|m|mm|h):[0-9]+:' "$OUT/warnings-all.txt" > "$OUT/warnings-c.txt" || true
    grep -E '\.swift:[0-9]+:' "$OUT/warnings-all.txt" > "$OUT/warnings-swift.txt" || true
    nc=$(count_lines "$OUT/warnings-c.txt"); ns=$(count_lines "$OUT/warnings-swift.txt")
    if [ "$rc" -ne 0 ]; then
      wants analyze && record analyze fail "xcodebuild analyze exited $rc"
      wants warnings && record warnings fail "build did not finish"
    else
      if wants analyze; then
        if [ "$nc" -eq 0 ]; then record analyze pass "0 analyzer/C findings"
        else record analyze fail "$nc analyzer/C findings"; fi
      fi
      if wants warnings; then
        if [ "$ns" -eq 0 ]; then record warnings pass "0 Swift warnings"
        else record warnings fail "$ns Swift warnings"; fi
      fi
    fi
  fi
fi

# --- sanitizer test passes --------------------------------------------------
sanitize() { # check-name, sanitizer
  local name="$1" san="$2" log="$OUT/$1.log" rc=0 pkg
  : > "$log"
  for pkg in WarmthKit cli; do
    echo "== $pkg ==" >> "$log"
    (cd "$pkg" && swift test --sanitize="$san" --scratch-path "../build/QA-$san-$pkg") >> "$log" 2>&1 || rc=1
  done
  if grep -qE "ERROR: (AddressSanitizer|ThreadSanitizer)|WARNING: ThreadSanitizer" "$log"; then
    record "$name" fail "$(grep -cE 'ERROR: (AddressSanitizer|ThreadSanitizer)|WARNING: ThreadSanitizer' "$log") sanitizer report(s)"
  elif [ "$rc" -ne 0 ]; then
    record "$name" fail "tests failed under $san sanitizer"
  else
    record "$name" pass "WarmthKit and cli tests clean"
  fi
}
wants asan && sanitize asan address
wants tsan && sanitize tsan thread

# --- coverage (report only; no threshold) -----------------------------------
if wants coverage; then
  log="$OUT/coverage.log"
  if (cd WarmthKit && swift test --enable-code-coverage --scratch-path ../build/QA-cov) >"$log" 2>&1; then
    json="$(cd WarmthKit && swift test --show-codecov-path --scratch-path ../build/QA-cov 2>/dev/null)"
    pct="$(python3 - "$json" <<'PY' 2>>"$log"
import json, sys
data = json.load(open(sys.argv[1]))["data"][0]["files"]
covered = total = 0
for f in data:
    name = f["filename"]
    if "/Tests/" in name or "/.build/" in name or "/build/" in name or "/checkouts/" in name:
        continue
    lines = f["summary"]["lines"]
    covered += lines["covered"]; total += lines["count"]
print("{:.1f}% of {} source lines".format(100.0 * covered / total if total else 0, total))
PY
)"
    if [ -n "$pct" ]; then
      record coverage pass "WarmthKit $pct"
    else
      record coverage fail "could not read the coverage report"
    fi
  else
    record coverage fail "tests failed with coverage enabled"
  fi
fi

# --- strict lint ------------------------------------------------------------
if wants swift-format; then
  log="$OUT/swift-format.log"
  : > "$log"
  tool_rc=0
  for dir in WarmthKit/Sources WarmthKit/Tests cli/Sources cli/Tests App; do
    [ -d "$dir" ] || continue
    swift format lint --strict --recursive "$dir" >> "$log" 2>&1 || tool_rc=$?
  done
  n=$(grep -cE ': (warning|error):' "$log" || true)
  if [ "${n:-0}" -gt 0 ]; then
    record swift-format fail "$n findings"
  elif [ "$tool_rc" -ne 0 ]; then
    record swift-format fail "swift format exited $tool_rc with no findings (tool error)"
  else
    record swift-format pass "0 findings"
  fi
fi

if wants shellcheck; then
  if command -v shellcheck >/dev/null 2>&1; then
    log="$OUT/shellcheck.log"
    find scripts -type f -name '*.sh' -print0 | xargs -0 shellcheck -f gcc > "$log" 2>&1
    rc=$?
    n=$(count_lines "$log")
    if [ "$n" -gt 0 ]; then record shellcheck fail "$n findings"
    elif [ "$rc" -ne 0 ]; then record shellcheck fail "shellcheck exited $rc (tool error)"
    else record shellcheck pass "0 findings"; fi
  else
    record shellcheck skip "shellcheck not on PATH"
  fi
fi

if wants actionlint; then
  if command -v actionlint >/dev/null 2>&1; then
    log="$OUT/actionlint.log"
    cfg="$OUT/actionlint.yaml"
    printf 'self-hosted-runner:\n  labels: [abendrot-air, abendrot-display-matrix]\n' > "$cfg"
    actionlint -config-file "$cfg" -oneline > "$log" 2>&1
    rc=$?
    n=$(count_lines "$log")
    if [ "$n" -gt 0 ]; then record actionlint fail "$n findings"
    elif [ "$rc" -ne 0 ]; then record actionlint fail "actionlint exited $rc (tool error)"
    else record actionlint pass "0 findings"; fi
  else
    record actionlint skip "actionlint not on PATH"
  fi
fi

# --- report -----------------------------------------------------------------
blocked=0
{
  echo "### Deep QA ($(git rev-parse --short HEAD))"
  echo
  echo "| Check | Result | Detail | Blocking |"
  echo "|---|---|---|---|"
  while IFS=$'\t' read -r name status detail; do
    block="no"
    case "$BLOCKING" in *" $name "*) block="yes"; [ "$status" = fail ] && blocked=1 ;; esac
    echo "| $name | $status | $detail | $block |"
  done < "$RESULTS"
  echo
  echo "Report-only checks never fail the job. Logs: build/qa/<check>.log."
} > "$OUT/report.md"
python3 - "$RESULTS" "$OUT/report.json" "$(git rev-parse HEAD)" <<'PY'
import json, sys
rows = [l.rstrip("\n").split("\t") for l in open(sys.argv[1]) if l.strip()]
json.dump({"commit": sys.argv[3],
           "checks": [{"name": n, "status": s, "detail": d} for n, s, d in rows]},
          open(sys.argv[2], "w"), indent=1)
PY
cat "$OUT/report.md"
# The machine-readable line the review and the weekly tally read from the log.
echo "DEEP-QA-JSON $(tr -d '\n' < "$OUT/report.json")"
[ -n "${GITHUB_STEP_SUMMARY:-}" ] && cat "$OUT/report.md" >> "$GITHUB_STEP_SUMMARY"
# Show the first findings of each failed check in the log.
while IFS=$'\t' read -r name status _; do
  [ "$status" = fail ] || continue
  for f in "$OUT/$name.log" "$OUT/warnings-c.txt" "$OUT/warnings-swift.txt"; do
    case "$name:$f" in
      analyze:*warnings-c.txt|warnings:*warnings-swift.txt|*:"$OUT/$name.log") ;;
      *) continue ;;
    esac
    [ -s "$f" ] || continue
    echo "::group::$name: first findings ($f)"
    head -n 40 "$f"
    echo "::endgroup::"
  done
done < "$RESULTS"
exit "$blocked"
