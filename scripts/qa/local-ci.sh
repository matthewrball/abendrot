#!/usr/bin/env bash
# Runs the required gates of .github/workflows/ci.yml on this Mac, for when hosted
# runners are unavailable. Keep the steps in the same order as that workflow.
#
#   scripts/qa/local-ci.sh            every gate except the launch test
#   scripts/qa/local-ci.sh --smoke    also launch the built app for 20 seconds
#
# --smoke starts a second Abendrot next to any installed copy. Both drive the same
# displays and share preferences, so quit the installed app first.
#
# Not covered here: the macOS 15 and Intel runners, and CI's pinned Xcode. The
# toolchain in use is printed so a result can be compared with the workflow.
set -euo pipefail

SMOKE=0
for arg in "$@"; do
  case "$arg" in
    --smoke) SMOKE=1 ;;
    *) echo "usage: $0 [--smoke]" >&2; exit 2 ;;
  esac
done

ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
cd "$ROOT"
SHA="$(git rev-parse HEAD)"
SCHEME="Abendrot"
APP="build/DerivedData/Build/Products/Release/$SCHEME.app"
# Must match XCODEGEN_VERSION in .github/workflows/ci.yml.
PINNED_XCODEGEN="Version: 2.46.0"
LOGS="$(mktemp -d -t abendrot-local-ci.XXXXXX)"
PASSED=()
CAVEATS=()

step() {
  local name="$1"; shift
  local log="$LOGS/${name// /-}.log"
  printf '▸ %s … ' "$name"
  if "$@" >"$log" 2>&1; then
    echo "ok"
    PASSED+=("$name")
  else
    echo "FAILED (log: $log)"
    tail -n 40 "$log" >&2
    exit 1
  fi
}

# `step` runs this as an `if` condition, where `set -e` is off: collect failures by hand.
shell_syntax() {
  local script rc=0
  while IFS= read -r -d '' script; do
    bash -n "$script" || rc=1
  done < <(find scripts -type f -name '*.sh' -print0)
  return "$rc"
}

build_scheme() {
  xcodebuild \
    -project "$SCHEME.xcodeproj" \
    -scheme "$1" \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$2" \
    -onlyUsePackageVersionsFromResolvedFile \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGN_IDENTITY="" \
    ABENDROT_SOURCE_COMMIT="$SHA" \
    build
}

source_commit_bound() {
  [ "$(/usr/bin/plutil -extract AbendrotSourceCommit raw "$APP/Contents/Info.plist")" = "$SHA" ]
}

if [ -n "$(git status --porcelain)" ]; then
  CAVEATS+=("uncommitted changes: the result describes this tree, not $SHA")
fi
XCODEGEN_VERSION="$(xcodegen --version)"
if [ "$XCODEGEN_VERSION" != "$PINNED_XCODEGEN" ]; then
  CAVEATS+=("xcodegen is '$XCODEGEN_VERSION'; CI pins '$PINNED_XCODEGEN'")
fi
[ "$SMOKE" = 1 ] || CAVEATS+=("launch test not run; rerun with --smoke")
echo "local CI at $SHA ($(xcodebuild -version | tr '\n' ' '), xcodegen $XCODEGEN_VERSION)"

step "shell syntax" shell_syntax
step "release guards" scripts/release/test-release-guards.sh
step "mac app store guards" scripts/release/test-mac-app-store.sh
step "WarmthKit tests" swift test --package-path WarmthKit --parallel
step "CLI tests" swift test --package-path cli --parallel
step "xcodegen" xcodegen generate --spec project.yml
step "build app" build_scheme "$SCHEME" build/DerivedData
step "build app store variant" build_scheme AbendrotAppStore build/DerivedData-AppStore
step "source commit bound" source_commit_bound
step "plain dmg" ./scripts/dmg/plain-dmg.sh --app "$APP" --out "build/$SCHEME-ci.dmg" --volname "Abendrot"
step "macOS compatibility" scripts/qa/check-macos-compatibility.sh "$APP"
if [ "$SMOKE" = 1 ]; then
  step "smoke launch" scripts/qa/smoke-launch.sh "$APP"
fi

rm -rf "$LOGS"
if [ "${#CAVEATS[@]}" -eq 0 ]; then
  echo "PASS: ${#PASSED[@]} steps at $SHA"
else
  echo "PASS with caveats: ${#PASSED[@]} steps at $SHA"
  for caveat in "${CAVEATS[@]}"; do echo "  - $caveat"; done
fi
