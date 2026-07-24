#!/usr/bin/env bash
#
# publish.sh — STAGED publish of the source/build checkout to the curated public tree.
# `main` never advances except by fast-forwarding a verified-green `public-dev`. Two subcommands:
#
#   publish.sh [stage]   (default) Sync the COMMITTED build HEAD onto `public-dev` and stage it.
#                        Never commits/pushes — prints the founder-gated commit+push commands.
#   publish.sh promote   Fast-forward `main` to `origin/public-dev` AFTER verifying CI is green
#                        and running a final leak scan. Confirms before pushing main.
#
# Why this exists: a publish straight to main once leaked a dev home path + shipped scrub-mangled
# code, forcing a main rollback. Guards: (a) we sync from a CLEAN CLONE of the COMMITTED build HEAD,
# never the working tree, so uncommitted WIP/secrets can't ride along; (b) everything lands on
# `public-dev` (distinct from the source-history `dev` branch),
# where CI + the leak gate run BEFORE main advances; (c) GitHub branch protection on `main` requires
# those CI checks green, so even a direct push can't bypass the flow (this script just makes the
# correct path the easy one).
#
# Env: BUILD=/path PUBLIC=/path   (override to test against copies — never the real tree)
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="${BUILD:-$REPO_ROOT}"
PUBLIC="${PUBLIC:-$(dirname "$REPO_ROOT")/abendrot-public}"
REQUIRED_CHECKS=(public-dev/release-gate)
PUBLIC_BRANCH="public-dev"
CI_WORKFLOW_PATH=".github/workflows/ci.yml"
# Legit PUBLIC-ONLY files: tracked in public but NOT produced by sync. Keep this TIGHT — every entry
# is a conscious "yes, this belongs in public". The allowlist guard fails the publish on anything that
# is neither in the sync set nor here, so a stray internal file can't ride along via `git add -A`.
PUBLIC_ONLY=(.gitignore LICENSE CONTRIBUTING.md SECURITY.md assets/abendrot-icon.png)

git -C "$BUILD" rev-parse --git-dir >/dev/null 2>&1 || { echo "BUILD is not a git repo: $BUILD" >&2; exit 1; }
git -C "$PUBLIC" rev-parse --git-dir >/dev/null 2>&1 || { echo "PUBLIC is not a git repo: $PUBLIC" >&2; exit 1; }

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
  local pat='/Users/|/home/[a-z]|abendrot-(build|public)|§|\bfounder\b|(^|[^$])\{\{[^}]+\}\}'
  local hits rc=0
  hits="$(git_pub grep -nEI "$pat" -- .)" || rc=$?
  case "$rc" in
    0)
      printf '%s\n' "$hits" >&2
      echo "ERROR: leak scan found tells above. Do NOT publish." >&2
      return 1
      ;;
    1) echo "✓ leak scan clean (0 hits across every tracked public file)" ;;
    *) echo "ERROR: leak scan failed to inspect the public tree." >&2; return "$rc" ;;
  esac
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
# stage: clone committed build HEAD -> sync+scrub+gate -> public-dev -> scan -> guide.
# ---------------------------------------------------------------------------
do_stage() {
  require_clean_tree
  echo "== Fetching public origin =="
  git_pub fetch -q origin
  git_pub rev-parse --verify --quiet origin/main >/dev/null || {
    echo "PUBLIC origin has no 'main' branch — refusing to stage." >&2
    exit 1
  }
  local local_publish remote_publish local_only remote_only main
  main="$(git_pub rev-parse origin/main)"
  if git_pub rev-parse --verify --quiet "origin/$PUBLIC_BRANCH" >/dev/null; then
    if ! git_pub rev-parse --verify --quiet "$PUBLIC_BRANCH" >/dev/null; then
      git_pub branch --track "$PUBLIC_BRANCH" "origin/$PUBLIC_BRANCH" >/dev/null
    fi
    git_pub checkout -q "$PUBLIC_BRANCH"
    git_pub merge --ff-only -q "origin/$PUBLIC_BRANCH" || {
      echo "PUBLIC $PUBLIC_BRANCH cannot fast-forward to origin/$PUBLIC_BRANCH — refusing to stage." >&2
      exit 1
    }
    local_publish="$(git_pub rev-parse "$PUBLIC_BRANCH")"
    remote_publish="$(git_pub rev-parse "origin/$PUBLIC_BRANCH")"
    if [ "$local_publish" != "$remote_publish" ]; then
      local_only="$(git_pub rev-list --count "origin/$PUBLIC_BRANCH..$PUBLIC_BRANCH")"
      remote_only="$(git_pub rev-list --count "$PUBLIC_BRANCH..origin/$PUBLIC_BRANCH")"
      echo "PUBLIC $PUBLIC_BRANCH does not exactly match origin/$PUBLIC_BRANCH — refusing to stage." >&2
      echo "  local-only commits: $local_only; remote-only commits: $remote_only" >&2
      exit 1
    fi
  else
    git_pub rev-parse --verify --quiet "$PUBLIC_BRANCH" >/dev/null && {
      echo "PUBLIC has a local $PUBLIC_BRANCH but origin/$PUBLIC_BRANCH is absent — refusing stale history." >&2
      exit 1
    }
    git_pub checkout --no-track -q -b "$PUBLIC_BRANCH" origin/main
  fi
  git_pub merge-base --is-ancestor "$main" HEAD || {
    echo "PUBLIC $PUBLIC_BRANCH is not descended from origin/main — refusing unrelated history." >&2
    exit 1
  }

  local clean head_sha head_short
  CLEAN_ROOT="$(mktemp -d)"; clean="$CLEAN_ROOT/ab-clean"
  echo "== Cloning committed build HEAD (no working-tree WIP rides along) =="
  git clone --quiet "$BUILD" "$clean"
  head_sha="$(git -C "$clean" rev-parse HEAD)"
  head_short="$(git -C "$clean" rev-parse --short HEAD)"
  echo "   build HEAD = $head_sha"

  echo "== Sync + scrub + hard tell/leak gate (sourced from the clean clone) =="
  BUILD="$clean" PUBLIC="$PUBLIC" bash "$clean/scripts/sync-public.sh"

  git_pub add -A
  echo "== Allowlist guard (only sync-set + PUBLIC_ONLY files may be published) =="
  assert_only_expected "$clean/scripts/sync-public.sh" || exit 1
  echo "== Independent leak scan =="
  leak_scan || exit 1

  echo
  echo "== Staged on $PUBLIC_BRANCH. Diff summary: =="
  git_pub diff --cached --stat
  cat <<EOF

Next (review the diff above first):
  # 1) commit + push public-dev:
  git -C "$PUBLIC" commit -m "sync from build $head_short" -m "Source-Build-Commit: $head_sha"
  git -C "$PUBLIC" push -u origin $PUBLIC_BRANCH
  # 2) wait for CI GREEN on public-dev, then:
  scripts/publish.sh promote
EOF
}

# ---------------------------------------------------------------------------
# promote: ff main -> origin/public-dev, only after CI is green + a final leak scan.
# ---------------------------------------------------------------------------
slug() { git_pub config --get remote.origin.url | sed -E 's#.*[:/]([^/]+/[^/]+)$#\1#; s#\.git$##'; }

require_green() {  # $1 = sha
  local sha="$1" repo run run_id jobs c
  repo="$(slug)"
  runs="$(
    gh api --paginate "repos/$repo/actions/runs?branch=$PUBLIC_BRANCH&event=push&status=completed&head_sha=$sha&per_page=100" \
      --jq '.workflow_runs[] | [.id, .path, .head_branch, .event, .status, .conclusion, .head_sha, .head_repository.full_name, .repository.full_name] | @tsv' \
      2>/dev/null || true
  )"
  run="$(
    printf '%s\n' "$runs" | awk -F '\t' -v path="$CI_WORKFLOW_PATH" -v branch="$PUBLIC_BRANCH" -v sha="$sha" -v repo="$repo" '
      $2 == path && $3 == branch && $4 == "push" && $5 == "completed" && $6 == "success" && $7 == sha && $8 == repo && $9 == repo { print; exit }
    '
  )"
  if [ -z "$run" ]; then
    echo "  ✗ no successful completed push run for $CI_WORKFLOW_PATH on $PUBLIC_BRANCH at $sha in $repo" >&2
    if [ -n "$runs" ]; then
      printf '%s\n' "$runs" | awk -F '\t' '{ printf "    observed: run_id=%s path=%s branch=%s event=%s status=%s conclusion=%s head_sha=%s head_repo=%s repo=%s\n", $1, $2, $3, $4, $5, $6, $7, $8, $9 }' >&2
    fi
    return 1
  fi
  run_id="${run%%	*}"
  for c in "${REQUIRED_CHECKS[@]}"; do
    jobs="$(
      gh api --paginate "repos/$repo/actions/runs/$run_id/jobs?per_page=100" \
        --jq '.jobs[] | [.name, .run_id, .head_sha, .status, .conclusion] | @tsv' \
        2>/dev/null || true
    )"
    if printf '%s\n' "$jobs" | awk -F '\t' -v name="$c" -v run_id="$run_id" -v sha="$sha" \
      '$1 == name && $2 == run_id && $3 == sha && $4 == "completed" && $5 == "success" { found = 1 } END { exit !found }'; then
      echo "  ✓ $c green"
    else
      echo "  ✗ $c is missing, not green, or not attached to run $run_id at $sha — refusing to promote" >&2
      printf '%s\n' "$jobs" | awk -F '\t' -v name="$c" '$1 == name {
        printf "    observed: name=%s run_id=%s sha=%s status=%s conclusion=%s\n", $1, $2, $3, $4, $5
      }' >&2
      return 1
    fi
  done
}

require_source_snapshot() { # $1 = public sha
  local publish="$1" message trailers source_sha
  message="$(git_pub log -1 --format=%B "$publish")"
  trailers="$(printf '%s\n' "$message" | grep -E '^Source-Build-Commit: [0-9a-f]{40}$' || true)"
  [ "$(printf '%s\n' "$trailers" | sed '/^$/d' | wc -l | tr -d ' ')" = "1" ] || {
    echo "ERROR: origin/$PUBLIC_BRANCH commit must contain exactly one Source-Build-Commit: <40hex> trailer." >&2
    exit 1
  }
  source_sha="${trailers#Source-Build-Commit: }"
  git -C "$BUILD" cat-file -e "$source_sha^{commit}" 2>/dev/null || {
    echo "ERROR: Source-Build-Commit does not exist in BUILD: $source_sha" >&2
    exit 1
  }
  git -C "$BUILD" fetch -q origin dev || {
    echo "ERROR: could not fetch BUILD origin/dev for Source-Build-Commit lineage." >&2
    exit 1
  }
  git -C "$BUILD" rev-parse --verify --quiet origin/dev >/dev/null || {
    echo "ERROR: BUILD origin/dev is missing; refusing to promote unmerged source." >&2
    exit 1
  }
  git -C "$BUILD" merge-base --is-ancestor "$source_sha" origin/dev || {
    echo "ERROR: Source-Build-Commit is not an ancestor of BUILD origin/dev: $source_sha" >&2
    exit 1
  }
  "$REPO_ROOT/scripts/release/verify-public-snapshot.sh" "$BUILD" "$source_sha" "$PUBLIC" "$publish"
}

do_promote() {
  command -v gh >/dev/null || { echo "gh CLI required for promote (CI-green check)." >&2; exit 1; }
  require_clean_tree
  echo "== Fetching origin =="
  git_pub fetch -q origin
  git_pub rev-parse --verify --quiet "origin/$PUBLIC_BRANCH" >/dev/null \
    || { echo "origin/$PUBLIC_BRANCH does not exist — nothing to promote." >&2; exit 1; }
  local publish main
  publish="$(git_pub rev-parse "origin/$PUBLIC_BRANCH")"; main="$(git_pub rev-parse origin/main)"
  if [ "$publish" = "$main" ]; then
    echo "origin/$PUBLIC_BRANCH == origin/main — nothing to promote."
    exit 0
  fi
  git_pub merge-base --is-ancestor "$main" "$publish" \
    || { echo "origin/main is not an ancestor of origin/$PUBLIC_BRANCH — not a fast-forward." >&2; exit 1; }

  echo "== Verifying public source snapshot =="
  require_source_snapshot "$publish"

  echo "== Verifying CI is green on origin/$PUBLIC_BRANCH ($(git_pub rev-parse --short "$publish")) =="
  require_green "$publish" || exit 1

  echo "== Final leak scan on the exact origin/$PUBLIC_BRANCH tree =="
  git_pub checkout -q --detach "$publish"
  leak_scan || exit 1

  echo
  read -r -p "Fast-forward main -> $(git_pub rev-parse --short "$publish") and push? [y/N] " ans
  if [ "${ans:-}" != "y" ] && [ "${ans:-}" != "Y" ]; then echo "Aborted (no push)."; exit 0; fi
  if ! git_pub rev-parse --verify --quiet main >/dev/null; then
    git_pub branch --track main origin/main >/dev/null
  fi
  git_pub checkout -q main
  git_pub merge --ff-only origin/main
  [ "$(git_pub rev-parse HEAD)" = "$main" ] \
    || { echo "local main does not exactly match origin/main — refusing to push." >&2; exit 1; }
  git_pub merge --ff-only "$publish"
  git_pub push origin main
  echo "✓ main promoted to $(git_pub rev-parse --short main) and pushed."
}

case "${1:-stage}" in
  stage)   do_stage ;;
  promote) do_promote ;;
  *) echo "usage: publish.sh [stage|promote]" >&2; exit 2 ;;
esac
