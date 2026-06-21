#!/usr/bin/env bash
#
# publish.sh — STAGED publish of the private build repo to the PUBLIC mirror, gitflow-style.
# `main` never advances except by fast-forwarding a verified-green `dev`. Two subcommands:
#
#   publish.sh [stage]   (default) Sync the COMMITTED build HEAD onto public `dev` and stage it.
#                        Never commits/pushes — prints the founder-gated commit+push commands.
#   publish.sh promote   Fast-forward `main` to `origin/dev` AFTER verifying dev's CI is green +
#                        a final leak scan. Confirms before the (founder-gated) push to main.
#
# Why this exists: a publish straight to main once leaked a dev home path + shipped scrub-mangled
# code, forcing a main rollback. Guards: (a) we sync from a CLEAN CLONE of the COMMITTED build HEAD,
# never the working tree, so uncommitted WIP/secrets can't ride along; (b) everything lands on `dev`,
# where CI + the leak gate run BEFORE main advances; (c) GitHub branch protection on `main` requires
# those CI checks green, so even a direct push can't bypass the flow (this script just makes the
# correct path the easy one).
#
# Env: BUILD=/path PUBLIC=/path   (override to test against copies — never the real tree)
#
set -euo pipefail

BUILD="${BUILD:-/Users/ball/Documents/abendrot/abendrot-build}"
PUBLIC="${PUBLIC:-/Users/ball/Documents/abendrot/abendrot-public}"
REQUIRED_CHECKS=(test-warmthcore build-app-unsigned)   # the real CI gates (see ci.yml)
# Legit PUBLIC-ONLY files: tracked in public but NOT produced by sync. Keep this TIGHT — every entry
# is a conscious "yes, this belongs in public". The allowlist guard fails the publish on anything that
# is neither in the sync set nor here, so a stray internal file can't ride along via `git add -A`.
PUBLIC_ONLY=(.gitignore LICENSE CONTRIBUTING.md PRIVACY.md SECURITY.md WarmthKit/Package.resolved assets)

[ -d "$BUILD/.git" ]  || { echo "BUILD is not a git repo: $BUILD" >&2; exit 1; }
[ -d "$PUBLIC/.git" ] || { echo "PUBLIC is not a git repo: $PUBLIC" >&2; exit 1; }

git_pub() { git -C "$PUBLIC" "$@"; }

CLEAN_ROOT=""
cleanup() { local rc=$?; [ -n "${CLEAN_ROOT:-}" ] && rm -rf "$CLEAN_ROOT"; exit "$rc"; }  # preserve real exit code
trap cleanup EXIT

require_clean_tree() {
  if [ -n "$(git_pub status --porcelain)" ]; then
    echo "PUBLIC working tree is dirty. Commit/stash/clean it first, then re-run:" >&2
    git_pub status -s >&2
    exit 1
  fi
}

# Independent leak scan over the synced public paths — belt-and-suspenders over sync's own gate.
leak_scan() {
  local paths=()
  local p
  for p in App WarmthKit cli scripts README.md AGENTS.md; do
    [ -e "$PUBLIC/$p" ] && paths+=("$PUBLIC/$p")
  done
  # Mirrors the sync gate's home-path / private-repo-name / §-ref / founder checks.
  local pat='/Users/|/home/[a-z]|abendrot-(build|public)|§|\bfounder\b'
  if grep -rInE "$pat" "${paths[@]}" 2>/dev/null; then
    echo "ERROR: leak scan found tells above. Do NOT publish — fix scrub-planning-tells.py and re-run." >&2
    return 1
  fi
  echo "✓ leak scan clean (0 hits)"
}

# Allowlist guard: every file that would be committed must be EITHER produced by sync (the authoritative
# SYNC_TREES/SYNC_FILES, read straight from the cloned sync-public.sh so there's no extra list to keep in
# lockstep) OR on PUBLIC_ONLY. Flips leak-prevention from "remove the bad things we named" to "permit only
# what we expect" — catches any stray (brand/, .omc/, a new top-level file, …) outside the sync set.
# $1 = path to the (cloned) sync-public.sh.
assert_only_expected() {
  local manifest="$1" f e ok
  local expected=()
  while IFS= read -r e; do expected+=("$e"); done < <(
    sed -n '/^SYNC_TREES=(/,/^)/p; /^SYNC_FILES=(/,/^)/p' "$manifest" | grep -oE '"[^"]+"' | tr -d '"')
  [ "${#expected[@]}" -ge 5 ] \
    || { echo "guard: could not parse the sync set from $manifest — refusing to publish." >&2; return 1; }
  local strays=()
  while IFS= read -r f; do
    ok=""
    for e in "${expected[@]}" "${PUBLIC_ONLY[@]}"; do
      if [[ "$f" == "$e" || "$f" == "$e"/* ]]; then ok=1; break; fi
    done
    [ -z "$ok" ] && strays+=("$f")
  done < <(git_pub ls-files)   # the staged set (run after `git add -A`): reflects sync's deletions + additions
  if [ "${#strays[@]}" -gt 0 ]; then
    echo "ERROR: unexpected file(s) in the public tree — not in the sync set or the PUBLIC_ONLY allowlist:" >&2
    printf '  %s\n' "${strays[@]}" >&2
    echo "Fix: if it belongs in public, add it to PUBLIC_ONLY in publish.sh; otherwise remove it (or add it" >&2
    echo "to INTERNAL_ONLY in sync-public.sh so sync strips it)." >&2
    return 1
  fi
  echo "✓ allowlist clean (no files outside the sync set + PUBLIC_ONLY)"
}

# ---------------------------------------------------------------------------
# stage: clone committed build HEAD -> sync+scrub+gate -> land on dev -> scan -> guide.
# ---------------------------------------------------------------------------
do_stage() {
  git_pub rev-parse --verify --quiet dev >/dev/null || {
    echo "PUBLIC has no 'dev' branch. Create it first (founder-gated):" >&2
    echo "  git -C $PUBLIC checkout -b dev main && git -C $PUBLIC push -u origin dev" >&2
    exit 1
  }
  require_clean_tree

  local clean head_sha
  CLEAN_ROOT="$(mktemp -d)"; clean="$CLEAN_ROOT/ab-clean"
  echo "== Cloning committed build HEAD (no working-tree WIP rides along) =="
  git clone --quiet "$BUILD" "$clean"
  head_sha="$(git -C "$clean" rev-parse --short HEAD)"
  echo "   build HEAD = $head_sha"

  git_pub checkout dev
  echo "== Sync + scrub + hard tell/leak gate (sourced from the clean clone) =="
  BUILD="$clean" PUBLIC="$PUBLIC" bash "$clean/scripts/sync-public.sh"

  git_pub add -A
  echo "== Allowlist guard (only sync-set + PUBLIC_ONLY files may be published) =="
  assert_only_expected "$clean/scripts/sync-public.sh" || exit 1
  echo "== Independent leak scan =="
  leak_scan || exit 1

  echo
  echo "== Staged on dev. Diff summary: =="
  git_pub diff --cached --stat
  cat <<EOF

Next (FOUNDER-GATED — review the diff above first):
  # 1) commit + push dev:
  git -C "$PUBLIC" commit -m "sync from build $head_sha"
  git -C "$PUBLIC" push origin dev
  # 2) wait for CI GREEN on dev (branch protection on main also requires it), then:
  scripts/publish.sh promote
EOF
}

# ---------------------------------------------------------------------------
# promote: ff main -> origin/dev, only after dev's CI is green + a final leak scan.
# ---------------------------------------------------------------------------
slug() { git_pub config --get remote.origin.url | sed -E 's#.*[:/]([^/]+/[^/]+)$#\1#; s#\.git$##'; }

require_green() {  # $1 = sha
  local sha="$1" runs c
  runs="$(gh api "repos/$(slug)/commits/$sha/check-runs" --jq '.check_runs[] | "\(.name)=\(.conclusion)"' 2>/dev/null || true)"
  [ -n "$runs" ] || { echo "  ✗ no CI check-runs found for $sha (has CI finished?)" >&2; return 1; }
  for c in "${REQUIRED_CHECKS[@]}"; do
    if printf '%s\n' "$runs" | grep -qx "$c=success"; then
      echo "  ✓ $c green"
    else
      echo "  ✗ $c is $(printf '%s\n' "$runs" | grep "^$c=" | cut -d= -f2 || echo missing) — refusing to promote" >&2
      return 1
    fi
  done
}

do_promote() {
  command -v gh >/dev/null || { echo "gh CLI required for promote (CI-green check)." >&2; exit 1; }
  require_clean_tree
  echo "== Fetching origin =="
  git_pub fetch -q origin
  local dev main
  dev="$(git_pub rev-parse origin/dev)"; main="$(git_pub rev-parse origin/main)"
  if [ "$dev" = "$main" ]; then echo "origin/dev == origin/main — nothing to promote."; exit 0; fi
  git_pub merge-base --is-ancestor "$main" "$dev" \
    || { echo "origin/main is not an ancestor of origin/dev — not a fast-forward. Resolve manually." >&2; exit 1; }

  echo "== Verifying CI is green on origin/dev ($(git_pub rev-parse --short origin/dev)) =="
  require_green "$dev" || exit 1

  echo "== Final leak scan on the dev tree =="
  git_pub checkout -q dev && git_pub merge --ff-only -q origin/dev
  leak_scan || exit 1

  echo
  read -r -p "Fast-forward main -> $(git_pub rev-parse --short origin/dev) and push? [y/N] " ans
  if [ "${ans:-}" != "y" ] && [ "${ans:-}" != "Y" ]; then echo "Aborted (no push)."; exit 0; fi
  git_pub checkout -q main
  git_pub merge --ff-only origin/dev
  git_pub push origin main
  echo "✓ main promoted to $(git_pub rev-parse --short main) and pushed."
}

case "${1:-stage}" in
  stage)   do_stage ;;
  promote) do_promote ;;
  *) echo "usage: publish.sh [stage|promote]" >&2; exit 2 ;;
esac
