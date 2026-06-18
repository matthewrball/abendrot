#!/usr/bin/env bash
#
# sync-public.sh — export the shippable app/engine source from the PRIVATE build repo
# to the CLEAN public mirror, then scrub planning tells. Idempotent. Does NOT git-push
# (that is founder-gated) and does NOT commit — it only updates the public working tree.
#
# Usage:
#   scripts/sync-public.sh            # real run
#   scripts/sync-public.sh --dry-run  # show what rsync would change, touch nothing
#
# Env overrides: BUILD=/path PUBLIC=/path
#
set -euo pipefail

BUILD="${BUILD:-/Users/ball/Documents/abendrot}"
PUBLIC="${PUBLIC:-/Users/ball/Documents/abendrot-public}"
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

# Sync a subtree build->public with --delete (so removed files propagate), scoped to that subtree.
sync_tree() {
  local rel="$1"
  echo "  rsync $rel/"
  rsync -a $DRY --delete "${EXCLUDES[@]}" "$BUILD/$rel/" "$PUBLIC/$rel/"
}
copy_file() {
  local rel="$1"
  echo "  cp $rel"
  [ -n "$DRY" ] || cp "$BUILD/$rel" "$PUBLIC/$rel"
}

echo "== Syncing shippable source build -> public =="
sync_tree "App/Sources"
sync_tree "App/Resources"
sync_tree "WarmthKit/Sources"
sync_tree "WarmthKit/Tests"
copy_file "WarmthKit/Package.swift"
copy_file "project.yml"
copy_file ".github/workflows/ci.yml"
sync_tree "scripts/dmg"
sync_tree "scripts/release"

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
if grep -rnE '§|docs/(research|marketing|engine|qa)|plan §|abendrot-plan|RESUME-PROMPT|HANDOFF\b|founder' \
     "$PUBLIC/App/Sources" "$PUBLIC/WarmthKit/Sources" "$PUBLIC/WarmthKit/Tests" 2>/dev/null; then
  echo "ERROR: planning tells remain after scrub (see matches above). Fix scrub-planning-tells.py and re-run." >&2
  exit 1
fi
echo "✓ Public source synced and clean. Review the diff, build-verify, commit, then push (founder-gated)."
