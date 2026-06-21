#!/usr/bin/env bash
#
# publish.sh — STAGED publish of the private build repo to the PUBLIC mirror's `dev`
# branch. Never publishes straight to main: `dev` gets the sync + CI + leak gate first;
# main only ever fast-forwards from a verified-green `dev`.
#
# Why this exists: a publish straight to main once leaked a dev home path + briefly
# shipped scrub-mangled code, forcing a main rollback. Two guards prevent a repeat —
#   (a) we sync from a CLEAN CLONE of the COMMITTED build HEAD, never the working tree,
#       so uncommitted WIP/secrets can never ride along; and
#   (b) the result lands on `dev`, where CI + the leak gate run BEFORE main advances.
#
# What this script does (all SAFE — it does NOT commit and does NOT push; both stay
# founder-gated):
#   1. Clone the committed build HEAD into a throwaway dir (no working-tree WIP).
#   2. Run sync-public.sh FROM THE CLONE (rsync -> scrub -> hard tell/leak gate).
#   3. Check out `dev` in the public mirror and stage the synced result.
#   4. Re-run an independent leak scan as belt-and-suspenders over the gate.
#   5. Print the exact founder-gated commands to commit + push `dev`, and — after CI is
#      green on `dev` — to fast-forward main.
#
# Usage:  scripts/publish.sh
# Env:    BUILD=/path PUBLIC=/path   (override to test against copies — never the real tree)
#
set -euo pipefail

BUILD="${BUILD:-/Users/ball/Documents/abendrot/abendrot-build}"
PUBLIC="${PUBLIC:-/Users/ball/Documents/abendrot/abendrot-public}"

[ -d "$BUILD/.git" ]  || { echo "BUILD is not a git repo: $BUILD" >&2; exit 1; }
[ -d "$PUBLIC/.git" ] || { echo "PUBLIC is not a git repo: $PUBLIC" >&2; exit 1; }

# `dev` must already exist (created once from main). Don't auto-create — that push is gated.
git -C "$PUBLIC" rev-parse --verify --quiet dev >/dev/null || {
  echo "PUBLIC has no 'dev' branch. Create it first (founder-gated):" >&2
  echo "  git -C $PUBLIC checkout -b dev main && git -C $PUBLIC push -u origin dev" >&2
  exit 1
}

# Refuse to run on a dirty public tree — never sweep stray uncommitted files into a publish.
if [ -n "$(git -C "$PUBLIC" status --porcelain)" ]; then
  echo "PUBLIC working tree is dirty. Commit/stash/clean it first, then re-run:" >&2
  git -C "$PUBLIC" status -s >&2
  exit 1
fi

# 1. Clean clone of the COMMITTED build HEAD (NOT the working tree).
CLEAN="$(mktemp -d)/ab-clean"
trap 'rm -rf "$(dirname "$CLEAN")"' EXIT
echo "== Cloning committed build HEAD (no working-tree WIP rides along) =="
git clone --quiet "$BUILD" "$CLEAN"
HEAD_SHA="$(git -C "$CLEAN" rev-parse --short HEAD)"
echo "   build HEAD = $HEAD_SHA"

# 2. Land on dev, then sync + scrub + hard gate FROM THE CLONE into the public mirror.
git -C "$PUBLIC" checkout dev
echo "== Sync + scrub + hard tell/leak gate (sourced from the clean clone) =="
BUILD="$CLEAN" PUBLIC="$PUBLIC" bash "$CLEAN/scripts/sync-public.sh"

# 3. Stage the synced result.
git -C "$PUBLIC" add -A

# 4. Independent leak scan — belt-and-suspenders over sync-public.sh's own gate.
echo "== Independent leak scan =="
SCAN_PATHS=()
for p in App WarmthKit cli scripts README.md AGENTS.md; do
  [ -e "$PUBLIC/$p" ] && SCAN_PATHS+=("$PUBLIC/$p")
done
# Mirrors the sync gate's home-path / private-repo-name / §-ref / founder checks.
LEAK_PATTERN='/Users/|/home/[a-z]|abendrot-(build|public)|§|\bfounder\b'
if grep -rInE "$LEAK_PATTERN" "${SCAN_PATHS[@]}" 2>/dev/null; then
  echo "ERROR: leak scan found tells above. Do NOT publish — fix scrub-planning-tells.py and re-run." >&2
  exit 1
fi
echo "✓ leak scan clean (0 hits)"

echo
echo "== Staged on dev. Diff summary: =="
git -C "$PUBLIC" diff --cached --stat
cat <<EOF

Next (FOUNDER-GATED — review the diff above first):
  # 1) commit + push dev:
  git -C "$PUBLIC" commit -m "sync from build $HEAD_SHA"
  git -C "$PUBLIC" push origin dev
  # 2) wait for CI GREEN on dev, then re-run this script's leak scan (or by hand).
  # 3) ONLY then fast-forward main:
  git -C "$PUBLIC" checkout main && git -C "$PUBLIC" merge --ff-only dev && git -C "$PUBLIC" push origin main
EOF
