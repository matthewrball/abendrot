#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: verify-public-snapshot.sh <build-repo> <40-hex-source-sha> <public-repo> <40-hex-target-sha>" >&2
  exit 2
}

[ "$#" -eq 4 ] || usage
BUILD_REPO="$1"
SOURCE_SHA="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')"
PUBLIC_REPO="$3"
TARGET_SHA="$(printf '%s' "$4" | tr '[:upper:]' '[:lower:]')"
[[ "$SOURCE_SHA" =~ ^[0-9a-f]{40}$ ]] || usage
[[ "$TARGET_SHA" =~ ^[0-9a-f]{40}$ ]] || usage

TMP_ROOT="$(mktemp -d)"
cleanup() { rm -rf "$TMP_ROOT"; }
trap cleanup EXIT

SRC="$TMP_ROOT/source"
PUB="$TMP_ROOT/public"

reject_tracked_symlinks() {
  local repo="$1" label="$2" links
  links="$(git -C "$repo" ls-files -s | awk '$1 == "120000" { print $4 }')"
  [ -z "$links" ] || {
    echo "snapshot: refusing $label commit with tracked symlink(s):" >&2
    printf '  %s\n' $links >&2
    exit 1
  }
}

git clone --quiet "$BUILD_REPO" "$SRC" || {
  echo "snapshot: could not clone build repo: $BUILD_REPO" >&2
  exit 1
}
git -C "$SRC" cat-file -e "$SOURCE_SHA^{commit}" 2>/dev/null || {
  echo "snapshot: source commit does not exist in build repo: $SOURCE_SHA" >&2
  exit 1
}
git -C "$SRC" checkout -q --detach "$SOURCE_SHA"
[ -f "$SRC/scripts/sync-public.sh" ] || {
  echo "snapshot: source commit has no scripts/sync-public.sh" >&2
  exit 1
}
reject_tracked_symlinks "$SRC" "source"

git clone --quiet "$PUBLIC_REPO" "$PUB" || {
  echo "snapshot: could not clone public repo: $PUBLIC_REPO" >&2
  exit 1
}
git -C "$PUB" cat-file -e "$TARGET_SHA^{commit}" 2>/dev/null || {
  echo "snapshot: target commit does not exist in public repo: $TARGET_SHA" >&2
  exit 1
}
git -C "$PUB" checkout -q --detach "$TARGET_SHA"
reject_tracked_symlinks "$PUB" "public"

BUILD="$SRC" PUBLIC="$PUB" bash "$SRC/scripts/sync-public.sh" >/dev/null

git -C "$PUB" add -A -f --

if ! git -C "$PUB" diff --cached --quiet --exit-code "$TARGET_SHA" --; then
  echo "snapshot: public target does not match source sync output." >&2
  git -C "$PUB" diff --cached --stat "$TARGET_SHA" -- >&2 || true
  exit 1
fi

if [ -n "$(git -C "$PUB" status --porcelain --untracked-files=all)" ]; then
  echo "snapshot: public target has uncommitted working-tree changes after verification." >&2
  git -C "$PUB" status --short --untracked-files=all >&2
  exit 1
fi

echo "snapshot: public $TARGET_SHA matches source $SOURCE_SHA"
