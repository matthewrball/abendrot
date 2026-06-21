#!/usr/bin/env bash
#
# sync-public.sh — export the shippable app/engine/CLI source + agent-control docs
# from the PRIVATE build repo to the CLEAN public mirror, then scrub planning tells.
# Idempotent. Does NOT git-push (that is founder-gated) and does NOT commit — it only
# updates the public working tree.
#
# Usage:
#   scripts/sync-public.sh            # real run
#   scripts/sync-public.sh --dry-run  # show what rsync would change, touch nothing
#
# Env overrides: BUILD=/path PUBLIC=/path
#
set -euo pipefail

# The real sub-repos live INSIDE the umbrella workspace. Default to them directly
# (NOT the parent workspace, which holds private planning material). Override with
# BUILD=/path PUBLIC=/path for testing against copies.
BUILD="${BUILD:-/Users/ball/Documents/abendrot/abendrot-build}"
PUBLIC="${PUBLIC:-/Users/ball/Documents/abendrot/abendrot-public}"
DRY=""
[ "${1:-}" = "--dry-run" ] && DRY="-n"

[ -d "$BUILD/.git" ] || { echo "BUILD is not a git repo: $BUILD" >&2; exit 1; }
[ -d "$PUBLIC/.git" ] || { echo "PUBLIC is not a git repo: $PUBLIC" >&2; exit 1; }

# Common excludes: build artifacts + tooling state that must never reach public.
EXCLUDES=(
  --exclude='.build/' --exclude='build/' --exclude='DerivedData/'
  --exclude='.swiftpm/' --exclude='xcuserdata/' --exclude='*.xcuserstate'
  --exclude='.DS_Store' --exclude='.omc/' --exclude='*.xcodeproj/'
)

# ---------------------------------------------------------------------------
# The synced fileset. EVERY entry here is also a scrub TARGET (scrub-planning-tells.py)
# and is covered by the grep gate below — the three lists MUST stay in lockstep so no
# path reaches public un-scrubbed or un-gated.
# ---------------------------------------------------------------------------
SYNC_TREES=(
  "App/Sources"
  "App/Resources"
  "WarmthKit/Sources"
  "WarmthKit/Tests"
  "scripts/dmg"
  "scripts/release"
  "cli/Sources"
  "cli/Tests"
  "cli/completions"
)
SYNC_FILES=(
  "WarmthKit/Package.swift"
  "project.yml"
  ".github/workflows/ci.yml"
  "cli/Package.swift"
  "cli/Package.resolved"
  "AGENTS.md"
  "docs/abendrot.1"
)

# Sync a subtree build->public with --delete (so removed files propagate), scoped to that subtree.
sync_tree() {
  local rel="$1"
  echo "  rsync $rel/"
  rsync -a $DRY --delete "${EXCLUDES[@]}" "$BUILD/$rel/" "$PUBLIC/$rel/"
}
copy_file() {
  local rel="$1"
  echo "  cp $rel"
  [ -n "$DRY" ] || { mkdir -p "$PUBLIC/$(dirname "$rel")"; cp "$BUILD/$rel" "$PUBLIC/$rel"; }
}

echo "== Syncing shippable source build -> public =="
for t in "${SYNC_TREES[@]}"; do sync_tree "$t"; done
for f in "${SYNC_FILES[@]}"; do copy_file "$f"; done

# Internal-only files that must not appear in public (present in build, absent in public).
echo "== Removing internal-only files from public =="
for f in "App/README.md"; do
  if [ -e "$PUBLIC/$f" ]; then echo "  rm $f"; [ -n "$DRY" ] || rm -f "$PUBLIC/$f"; fi
done

if [ -n "$DRY" ]; then
  echo "== DRY RUN — nothing changed. Re-run without --dry-run to apply, then run the scrub. =="
  exit 0
fi

echo "== Scrubbing planning tells from public source =="
python3 "$BUILD/scripts/scrub-planning-tells.py" "$PUBLIC"

echo "== Verifying public source is clean (0 planning tells) =="
# Gate EVERY synced path. The pattern covers §-refs, internal doc paths, the build/release
# vocabulary (Mode A/B, Wave-N, Lane X, dev/dogfood), the internal RELEASE.md/abendrot-plan
# paths, the handoff/resume artifacts, and "founder". Any surviving hit fails the run.
GATE_PATHS=()
for t in "${SYNC_TREES[@]}"; do [ -d "$PUBLIC/$t" ] && GATE_PATHS+=("$PUBLIC/$t"); done
for f in "${SYNC_FILES[@]}"; do [ -f "$PUBLIC/$f" ] && GATE_PATHS+=("$PUBLIC/$f"); done

TELL_PATTERN='§|docs/(research|marketing|engine|qa|release)/|plan §|abendrot-plan|RESUME-PROMPT|HANDOFF\b|\bfounder\b|\bMode [AB]\b|\bmode [AB]\b|\bWave-[0-9]|\bLane [A-Z]\b|dogfood|RELEASE\.md'
if grep -rnE "$TELL_PATTERN" "${GATE_PATHS[@]}" 2>/dev/null; then
  echo "ERROR: planning tells remain after scrub (see matches above). Fix scrub-planning-tells.py and re-run." >&2
  exit 1
fi
echo "✓ Public source synced and clean. Review the diff, build-verify, commit, then push (founder-gated)."
