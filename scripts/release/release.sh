#!/usr/bin/env bash
#
# release.sh — Abendrot release orchestrator (REIMPLEMENTED, not copied).
#
# This is a clean-room reimplementation of the *concept* behind the
# fayazara/macos-app-skills Go `release` CLI. We do NOT copy that code: its repo
# has no LICENSE file (README says "MIT" but the license API returns null), so
# verbatim reuse is legally unsafe (reference doc, license caveat). We reimplement
# the workflow in bash with our own structure.
#
# What it does (the Go CLI's job, our way):
# 1. Read version + build number from the EXPORTED app's Info.plist (plutil).
# 2. Require a build number above every build already in the appcast.
# 3. Build the DMG (pretty on a UI runner, else plain) — credential-less safe.
# 4. When signing is enabled: notarize + staple + verify via notarize.sh.
# 5. Sparkle-sign the DMG with `sign_update` (EdDSA) — the SINGLE release
# authority's key (local machine, key in login keychain).
# 6. Update appcast.xml PRESERVING existing <item> entries (prepend the new one).
# 7. Upload stable releases as GitHub drafts. Publish the draft only after the
# appcast has passed public-dev CI and been promoted to public main.
#
# DESIGN RULE: public release is GATED on >=1 notarized+stapled DMG, Developer
# ID signing, and Sparkle EdDSA signing. When signing is deferred (no Apple
# account), --unsigned is private/local dry-run packaging only and cannot publish
# or upload artifacts.
#
# This file is a working SKELETON: the Sparkle + appcast + gh steps are real
# command lines, guarded so the script runs end-to-end TODAY without credentials
# and tells you exactly what each later step will do. Configurable placeholders
# (scheme/app name) are env vars at the top.
#
# SIGNING RULE: an appcast <item> that carries a
# `sparkle:edSignature` attribute is a PROMISE that the enclosure is EdDSA-signed
# by the single release authority. Therefore:
# * SIGNED path (default for a real release): a missing/empty EdDSA signature is
# a HARD FAILURE — the script exits non-zero and writes NOTHING to the
# appcast. We never publish an item that claims to be signed but isn't.
# * UNSIGNED path (--unsigned, local testing only): the script produces a local
# smoke artifact and does not modify the production appcast.
#
# Usage:
# scripts/release/release.sh --app <exported/Abendrot.app> [--prerelease] \
# [--notes <notes.md>] [--dmg-mode auto|pretty|plain] [--unsigned]
#
# Env (signing-enabled only): ASC_API_KEY_P8(_BASE64), ASC_API_KEY_ID, ASC_API_ISSUER_ID,
# SPARKLE_SIGN_UPDATE (path to Sparkle's sign_update tool; auto-discovered).
# Env (publishing only): RELEASE_TARGET_SHA (40-char SHA already pushed to the curated
# public repo; stable releases must target public main, prereleases may target
# public-dev or main).
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# ---- PLACEHOLDERS ----
APP_DISPLAY_NAME="Abendrot"
GH_REPO="matthewrball/abendrot"
EXPECTED_BUNDLE_ID="app.abendrot.Abendrot"
APPCAST_PATH="${APPCAST_PATH:-$REPO_ROOT/appcast.xml}"  # hosted via GitHub (raw)
RELEASE_SCRATCH="${RELEASE_SCRATCH:-$REPO_ROOT/release-scratch}"
DOWNLOAD_URL_BASE="https://github.com/${GH_REPO}/releases/download"
PUBLIC_DEV_BRANCH="${PUBLIC_DEV_BRANCH:-public-dev}"
RELEASE_PUBLIC_REPO="${RELEASE_PUBLIC_REPO:-https://github.com/matthewrball/abendrot.git}"
# --------------------------------------------

APP=""
NOTES=""
PRERELEASE="false"
DMG_MODE="auto"
UNSIGNED="false"   # --unsigned: local-testing path; never mutates the production appcast.

while [ $# -gt 0 ]; do
  case "$1" in
    --app)        APP="${2:-}"; shift 2 ;;
    --notes)      NOTES="${2:-}"; shift 2 ;;
    --prerelease) PRERELEASE="true"; shift ;;
    --dmg-mode)   DMG_MODE="${2:-}"; shift 2 ;;
    --unsigned)   UNSIGNED="true"; shift ;;
    -h|--help)    grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed -n '1,50p'; exit 0 ;;
    *) echo "release: unknown arg '$1'" >&2; exit 2;;
  esac
done

[ -n "$APP" ] || { echo "release: --app <exported app> is required." >&2; exit 2; }
[ -d "$APP" ] || { echo "release: app not found at '$APP'." >&2; exit 3; }
if [ "${RELEASE_PUBLISH:-0}" = "1" ] && [ "$UNSIGNED" = "true" ]; then
  echo "release: ABORT — --unsigned is private/local dry-run packaging only." >&2
  echo "         Unsigned artifacts cannot be published or uploaded. Re-run without --unsigned after Developer ID signing, notarization, stapling, and Sparkle signing." >&2
  exit 9
fi
if [ "${RELEASE_PUBLISH:-0}" = "1" ] &&
   [ -n "$(git -C "$REPO_ROOT" status --porcelain --untracked-files=all)" ]; then
  echo "release: ABORT — publishing requires a clean committed source tree." >&2
  echo "         Commit or remove every tracked/untracked change, then rebuild." >&2
  exit 9
fi

# --- 1. Read version + build from Info.plist -------------------------------
PLIST="$APP/Contents/Info.plist"
[ -f "$PLIST" ] || { echo "release: Info.plist missing in app bundle." >&2; exit 3; }
VERSION="$(/usr/bin/plutil -extract CFBundleShortVersionString raw "$PLIST" 2>/dev/null || echo '')"
BUILD="$(/usr/bin/plutil -extract CFBundleVersion raw "$PLIST" 2>/dev/null || echo '')"
BUNDLE_ID="$(/usr/bin/plutil -extract CFBundleIdentifier raw "$PLIST" 2>/dev/null || echo '')"
APP_EXECUTABLE="$(/usr/bin/plutil -extract CFBundleExecutable raw "$PLIST" 2>/dev/null || echo '')"
[ -n "$VERSION" ] || { echo "release: could not read CFBundleShortVersionString." >&2; exit 3; }
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,3}(-[0-9A-Za-z][0-9A-Za-z.-]*)?$ ]] \
  || { echo "release: unsafe or malformed marketing version '$VERSION'." >&2; exit 3; }
[ -n "$BUILD" ] || { echo "release: could not read CFBundleVersion." >&2; exit 3; }
case "$BUILD" in
  *[!0-9]*) echo "release: CFBundleVersion must be a positive integer, got '$BUILD'." >&2; exit 3;;
esac
[ "$BUILD" -gt 0 ] 2>/dev/null \
  || { echo "release: CFBundleVersion must be greater than zero, got '$BUILD'." >&2; exit 3; }
[ "$BUNDLE_ID" = "$EXPECTED_BUNDLE_ID" ] || {
  echo "release: ABORT — CFBundleIdentifier must remain $EXPECTED_BUNDLE_ID." >&2
  echo "         Changing it would strand existing user preferences and statistics." >&2
  exit 3
}
[ -n "$APP_EXECUTABLE" ] || { echo "release: could not read CFBundleExecutable." >&2; exit 3; }
APP_BINARY="$APP/Contents/MacOS/$APP_EXECUTABLE"
[ -x "$APP_BINARY" ] || { echo "release: app executable missing at '$APP_BINARY'." >&2; exit 3; }
echo "release: $APP_DISPLAY_NAME version=$VERSION build=$BUILD prerelease=$PRERELEASE"

DEVELOPER_ID_APP="${DEVELOPER_ID_APP:-}"

require_developer_id_app_identity() {
  [ "$UNSIGNED" != "true" ] || return 0
  [ -n "$DEVELOPER_ID_APP" ] || {
    echo "release: ABORT — signed releases require DEVELOPER_ID_APP to be set to the exact Developer ID Application leaf authority." >&2
    echo "         Example: Developer ID Application: Name (TEAMID)" >&2
    exit 5
  }
  [[ "$DEVELOPER_ID_APP" =~ ^Developer\ ID\ Application:\ .+\ \([A-Z0-9]{10}\)$ ]] || {
    echo "release: ABORT — DEVELOPER_ID_APP must be the exact full leaf authority string." >&2
    echo "         Example: Developer ID Application: Name (TEAMID)" >&2
    exit 5
  }
}

verify_input_app_signature_authority() {
  [ "$UNSIGNED" != "true" ] || return 0
  command -v codesign >/dev/null 2>&1 || {
    echo "release: ABORT — signed releases require codesign." >&2
    exit 5
  }

  codesign --verify --deep --strict --verbose=2 "$APP" || {
    echo "release: ABORT — exported app signature is invalid before release packaging." >&2
    exit 5
  }

  local leaf_authority
  leaf_authority="$(
    codesign -dv --verbose=4 "$APP" 2>&1 \
      | awk -F= '/^Authority=/{ print $2; exit }'
  )"
  [ -n "$leaf_authority" ] || {
    echo "release: ABORT — could not read exported app signing authority." >&2
    exit 5
  }
  [ "$leaf_authority" = "$DEVELOPER_ID_APP" ] || {
    echo "release: ABORT — exported app signing authority does not match DEVELOPER_ID_APP." >&2
    echo "         Expected: $DEVELOPER_ID_APP" >&2
    echo "         Found:    $leaf_authority" >&2
    exit 5
  }
  echo "release: verified exported app signature authority: $leaf_authority"
}

require_developer_id_app_identity
verify_input_app_signature_authority

TAG="v$VERSION"
AUDITED_SOURCE_COMMIT="$(git -C "$REPO_ROOT" rev-parse HEAD)"
if [ "${RELEASE_PUBLISH:-0}" = "1" ]; then
  APP_SOURCE_COMMIT="$(/usr/bin/plutil -extract AbendrotSourceCommit raw "$PLIST" 2>/dev/null || echo '')"
  [ "$APP_SOURCE_COMMIT" = "$AUDITED_SOURCE_COMMIT" ] || {
    echo "release: ABORT — exported app was not built from this audited source commit." >&2
    echo "         Expected Info.plist AbendrotSourceCommit=$AUDITED_SOURCE_COMMIT" >&2
    exit 9
  }
fi

RELEASE_TARGET_RESOLVED=""
require_release_target() {
  [ "${RELEASE_PUBLISH:-0}" = "1" ] || return 0
  command -v gh >/dev/null 2>&1 || {
    echo "release: ABORT — RELEASE_PUBLISH=1 requires the gh CLI." >&2
    exit 9
  }

  local target="${RELEASE_TARGET_SHA:-}"
  [[ "$target" =~ ^[0-9a-fA-F]{40}$ ]] || {
    echo "release: ABORT — RELEASE_TARGET_SHA must be the exact 40-char curated public commit SHA." >&2
    echo "         Run scripts/publish.sh stage/promote first, then pass the public main/dev SHA." >&2
    exit 9
  }
  target="$(printf '%s' "$target" | tr '[:upper:]' '[:lower:]')"

  local resolved main_sha dev_sha tag_sha target_message target_trailers
  resolved="$(gh api "repos/${GH_REPO}/commits/${target}" --jq '.sha' 2>/dev/null || true)"
  [ "$resolved" = "$target" ] || {
    echo "release: ABORT — RELEASE_TARGET_SHA is not a commit in ${GH_REPO}." >&2
    exit 9
  }

  main_sha="$(gh api "repos/${GH_REPO}/git/ref/heads/main" --jq '.object.sha' 2>/dev/null || true)"
  dev_sha="$(gh api "repos/${GH_REPO}/git/ref/heads/${PUBLIC_DEV_BRANCH}" --jq '.object.sha' 2>/dev/null || true)"
  if [ "$PRERELEASE" = "true" ] || [ "$UNSIGNED" = "true" ]; then
    [ "$target" = "$main_sha" ] || [ "$target" = "$dev_sha" ] || {
      echo "release: ABORT — RELEASE_TARGET_SHA must be public main or ${PUBLIC_DEV_BRANCH}." >&2
      exit 9
    }
  else
    [ "$target" = "$main_sha" ] || {
      echo "release: ABORT — stable releases must target the curated public main SHA." >&2
      echo "         Promote public source first; refusing to tag ${PUBLIC_DEV_BRANCH} or a stale commit." >&2
      exit 9
    }
  fi
  target_message="$(gh api "repos/${GH_REPO}/commits/${target}" --jq '.commit.message' 2>/dev/null || true)"
  target_trailers="$(printf '%s\n' "$target_message" | grep -E '^Source-Build-Commit: [0-9a-f]{40}$' || true)"
  if [ "$(printf '%s\n' "$target_trailers" | sed '/^$/d' | wc -l | tr -d ' ')" != "1" ]; then
    echo "release: ABORT — public release target must contain exactly one Source-Build-Commit: <40hex> trailer." >&2
    exit 9
  fi
  [ "$target_trailers" = "Source-Build-Commit: $AUDITED_SOURCE_COMMIT" ] || {
    echo "release: ABORT — public release target is not tied to this audited build commit." >&2
    echo "         Expected commit trailer: Source-Build-Commit: $AUDITED_SOURCE_COMMIT" >&2
    exit 9
  }
  git -C "$REPO_ROOT" fetch -q origin dev || {
    echo "release: ABORT — could not fetch source origin/dev for audited source lineage." >&2
    exit 9
  }
  git -C "$REPO_ROOT" rev-parse --verify --quiet origin/dev >/dev/null || {
    echo "release: ABORT — source origin/dev is missing; refusing to publish unmerged source." >&2
    exit 9
  }
  git -C "$REPO_ROOT" merge-base --is-ancestor "$AUDITED_SOURCE_COMMIT" origin/dev || {
    echo "release: ABORT — audited source commit is not an ancestor of source origin/dev: $AUDITED_SOURCE_COMMIT" >&2
    exit 9
  }
  "$REPO_ROOT/scripts/release/verify-public-snapshot.sh" \
    "$REPO_ROOT" "$AUDITED_SOURCE_COMMIT" "$RELEASE_PUBLIC_REPO" "$target" || {
      echo "release: ABORT — public release target content does not match audited source commit." >&2
      exit 9
    }

  tag_sha="$(gh api "repos/${GH_REPO}/git/ref/tags/${TAG}" --jq '.object.sha' 2>/dev/null || true)"
  [ -z "$tag_sha" ] || {
    echo "release: ABORT — remote tag ${TAG} already exists; refusing to publish against a stale tag." >&2
    exit 9
  }

  RELEASE_TARGET_RESOLVED="$target"
  echo "release: verified curated public release target $RELEASE_TARGET_RESOLVED"
}

require_release_target

# Signed Sparkle releases must carry the real public key that matches the EdDSA
# private key in the release machine's login keychain. Shipping the placeholder
# would strand users on a build that can never validate future updates.
SPARKLE_PUBLIC_KEY="$(/usr/bin/plutil -extract SUPublicEDKey raw "$PLIST" 2>/dev/null || echo '')"
SPARKLE_FEED_URL="$(/usr/bin/plutil -extract SUFeedURL raw "$PLIST" 2>/dev/null || echo '')"
if [ "$UNSIGNED" != "true" ]; then
  SPARKLE_PUBLIC_KEY_BYTES="$(
    printf '%s' "$SPARKLE_PUBLIC_KEY" | /usr/bin/base64 -D 2>/dev/null | wc -c | tr -d ' '
  )"
  [ "$SPARKLE_PUBLIC_KEY_BYTES" = "32" ] || {
    echo "release: ABORT — SUPublicEDKey must decode to exactly 32 bytes." >&2
    exit 6
  }
  EXPECTED_FEED_URL="https://raw.githubusercontent.com/${GH_REPO}/main/appcast.xml"
  [ "$SPARKLE_FEED_URL" = "$EXPECTED_FEED_URL" ] || {
    echo "release: ABORT — SUFeedURL must be exactly $EXPECTED_FEED_URL" >&2
    exit 6
  }
fi

# --- 2. Strictly increasing build guard vs existing appcast -----------------
# The appcast uses the ELEMENT form (<sparkle:version>BUILD</sparkle:version>),
# written in step 6 below — NOT the attribute form.
# Reject any build that cannot advance every existing client on this channel.
if [ -f "$APPCAST_PATH" ]; then
  HIGHEST_BUILD="$(
    sed -n 's|.*<sparkle:version>\([0-9][0-9]*\)</sparkle:version>.*|\1|p' \
      "$APPCAST_PATH" | sort -n | tail -n 1
  )"
  if [ -n "$HIGHEST_BUILD" ] && [ "$BUILD" -le "$HIGHEST_BUILD" ]; then
    echo "release: ABORT — build number $BUILD does not exceed appcast build $HIGHEST_BUILD." >&2
    echo "         Bump CFBundleVersion before releasing (Sparkle compares builds)." >&2
    exit 7
  fi
fi

# --- 2.5 Embed + sign the `abendrot` CLI helper (inside-out) ----------------
# The CLI ships INSIDE the app bundle (one download, always version-matched). Order
# is load-bearing: build the helper, copy it in, then sign the HELPER
# FIRST — with its own unique identifier (app.abendrot.Abendrot.cli), the hardened
# runtime, and a secure timestamp — so that when the containing .app is signed later
# (at export / Developer-ID time) the nested Mach-O is already correctly signed. We
# do NOT use `codesign --deep`: nested code is signed explicitly, inside-out, and the
# helper never inherits app-only entitlements.
#
# DEVIATION FROM the planned path (Contents/MacOS/abendrot), with reason:
# the app's own executable is `Abendrot` (CFBundleExecutable), and the macOS default
# APFS volume is CASE-INSENSITIVE, so `Contents/MacOS/abendrot` COLLIDES with
# `Contents/MacOS/Abendrot` — copying the helper there OVERWRITES the app binary. We
# therefore embed at `Contents/Helpers/abendrot` (the conventional location for
# bundled command-line helpers; nested signed code is valid anywhere in the bundle).
# The cask `binary` stanza points at this path. (If the app is ever renamed so no
# case-collision exists, MacOS/ can be restored.)
#
# `--unsigned` is the only path that may skip code signing. A normal release must
# sign both the helper and the containing app, then pass notarization below.
CLI_PKG="$REPO_ROOT/cli"
CLI_SIGN_ID="app.abendrot.Abendrot.cli"     # unique helper identifier (NOT the app's id)

embed_cli_helper() {
  local app="$1"
  [ -d "$CLI_PKG" ] || { echo "release: ABORT — required cli/ package missing at '$CLI_PKG'." >&2; exit 5; }

  # Contents/Helpers/ (NOT Contents/MacOS/) — avoids the case-insensitive collision
  # with the app's own `Abendrot` executable (see the DEVIATION note above).
  local helpers_dir="$app/Contents/Helpers"
  local dest="$helpers_dir/abendrot"
  local app_archs arch triple bin_dir cli_bin
  local cli_build_root="$RELEASE_SCRATCH/cli-helper-build"
  local cli_bins=()
  app_archs="$(lipo -archs "$APP_BINARY" 2>/dev/null)" || {
    echo "release: ABORT — could not inspect app architectures at '$APP_BINARY'." >&2
    exit 5
  }
  [ -n "$app_archs" ] || { echo "release: ABORT — app has no Mach-O architectures." >&2; exit 5; }

  echo "release: building abendrot CLI helper for app architectures: $app_archs"
  for arch in $app_archs; do
    case "$arch" in
      arm64|x86_64) ;;
      *) echo "release: ABORT — unsupported app architecture '$arch'." >&2; exit 5;;
    esac
    triple="${arch}-apple-macosx26.0"
    bin_dir="$(swift build -c release --package-path "$CLI_PKG" \
      --only-use-versions-from-resolved-file \
      --scratch-path "$cli_build_root" --triple "$triple" --show-bin-path)" || {
        echo "release: ABORT — could not resolve CLI build path for '$arch'." >&2
        exit 5
      }
    swift build -c release --package-path "$CLI_PKG" \
      --only-use-versions-from-resolved-file \
      --scratch-path "$cli_build_root" --triple "$triple" || {
        echo "release: ABORT — CLI helper build failed for '$arch'." >&2
        exit 5
      }
    cli_bin="$bin_dir/abendrot"
    [ -x "$cli_bin" ] || {
      echo "release: ABORT — built CLI not found at '$cli_bin'." >&2
      exit 5
    }
    cli_bins+=( "$cli_bin" )
  done

  mkdir -p "$helpers_dir"
  echo "release: embedding helper -> $dest"
  if [ "${#cli_bins[@]}" -eq 1 ]; then
    cp "${cli_bins[0]}" "$dest"
  else
    lipo -create "${cli_bins[@]}" -output "$dest" || {
      echo "release: ABORT — could not assemble universal CLI helper." >&2
      exit 5
    }
  fi
  chmod 755 "$dest"
  lipo "$dest" -verify_arch $app_archs || {
    echo "release: ABORT — helper architectures do not cover app architectures '$app_archs'." >&2
    exit 5
  }

  # Sign the helper FIRST, inside-out — ONLY when a Developer ID identity is
  # configured and this is a SIGNED build. Otherwise leave it unsigned
  # (unsigned local builds) with a clear note; the app's own export step is
  # likewise unsigned today.
  if [ "$UNSIGNED" = "true" ]; then
    echo "release: NOTE — helper EMBEDDED but UNSIGNED (--unsigned; signing deferred)." >&2
    echo "         When signing is enabled, the helper is signed inside-out with id '$CLI_SIGN_ID'," >&2
    echo "         --options runtime, --timestamp, BEFORE the containing .app is signed." >&2
    return 0
  fi

  echo "release: signing helper FIRST (id=$CLI_SIGN_ID, hardened runtime, timestamp)..."
  codesign --force \
    --sign "$DEVELOPER_ID_APP" \
    --identifier "$CLI_SIGN_ID" \
    --options runtime \
    --timestamp \
    "$dest" || { echo "release: ABORT — helper codesign failed." >&2; exit 5; }

  # Verify the helper signature strictly. The
  # app-level --deep --strict verify + helper spctl run AFTER the app is signed
  # (at export/notarize time); these guarded checks document the contract here.
  codesign --verify --strict --verbose=2 "$dest" \
    || { echo "release: ABORT — helper signature failed --verify --strict." >&2; exit 5; }

  # The input is already an exported, signed app. Adding the helper changes the
  # sealed bundle, so re-sign the outer app after signing the nested helper.
  codesign --force \
    --sign "$DEVELOPER_ID_APP" \
    --options runtime \
    --timestamp \
    --preserve-metadata=entitlements,requirements,flags \
    "$app" || { echo "release: ABORT — app re-sign failed after helper embed." >&2; exit 5; }
  codesign --verify --deep --strict --verbose=2 "$app" \
    || { echo "release: ABORT — app signature invalid after helper embed." >&2; exit 5; }
  echo "release: helper + containing app signed and verified inside-out."
}

embed_cli_helper "$APP"

# --- 3. Build the DMG -------------------------------------------------------
DMG_OUT="$RELEASE_SCRATCH/${APP_DISPLAY_NAME}-${VERSION}.dmg"
mkdir -p "$(dirname "$DMG_OUT")"

choose_dmg_mode() {
  case "$DMG_MODE" in
    pretty) echo pretty ;;
    plain)  echo plain ;;
    auto)
      # Use pretty only if create-dmg exists AND there's a GUI session.
      if command -v create-dmg >/dev/null 2>&1 && pgrep -x WindowServer >/dev/null 2>&1; then
        echo pretty
      else
        echo plain
      fi ;;
    *) echo plain;;
  esac
}
EFFECTIVE_MODE="$(choose_dmg_mode)"
echo "release: building DMG (mode=$EFFECTIVE_MODE) -> $DMG_OUT"
if [ "$EFFECTIVE_MODE" = "pretty" ]; then
  "$REPO_ROOT/scripts/dmg/pretty-dmg.sh" --app "$APP" --out "$DMG_OUT" --volname "$APP_DISPLAY_NAME" \
    || { echo "release: pretty-dmg failed; falling back to plain-dmg." >&2;
         "$REPO_ROOT/scripts/dmg/plain-dmg.sh" --app "$APP" --out "$DMG_OUT" --volname "$APP_DISPLAY_NAME"; }
else
  "$REPO_ROOT/scripts/dmg/plain-dmg.sh" --app "$APP" --out "$DMG_OUT" --volname "$APP_DISPLAY_NAME"
fi

# --- 4. Notarize + staple (when signing enabled) / clean skip otherwise -----
# notarize.sh exits 0 with a clear message when no Apple credentials exist.
NOTARIZED="false"
if [ "$UNSIGNED" = "true" ]; then
  echo "release: --unsigned -> skipping notarization."
else
  if "$REPO_ROOT/scripts/release/notarize.sh" "$DMG_OUT"; then
    # Distinguish "actually notarized" from "skipped" by checking for a stapled ticket.
    if xcrun stapler validate "$DMG_OUT" >/dev/null 2>&1; then
      NOTARIZED="true"
    fi
  fi
fi
unset ASC_API_KEY_P8_BASE64 ASC_API_KEY_P8 ASC_API_KEY_ID ASC_API_ISSUER_ID

# Release gate: every signed release must be notarized and stapled. Local builds
# without Apple credentials must opt into the explicit --unsigned path.
if [ "$UNSIGNED" != "true" ] && [ "$NOTARIZED" != "true" ]; then
  echo "release: ABORT — signing is configured but the DMG is not notarized+stapled." >&2
  echo "         Releases are gated on >=1 notarized+stapled DMG." >&2
  exit 4
fi
if [ "$NOTARIZED" != "true" ]; then
  echo "release: NOTE — unsigned private/local smoke artifact." >&2
  echo "         Do not publish or upload; use right-click>Open / xattr only for local testing." >&2
  PRERELEASE="true"
fi

# --- 5. Sparkle sign_update (EdDSA) ----------------------------------------
# The SINGLE release authority's EdDSA private key lives in the LOGIN KEYCHAIN
# only (never in repo / CI). sign_update reads it from the keychain automatically.
#
# SIGNED is true unless the operator explicitly passed --unsigned. A SIGNED build
# MUST end up with a non-empty EdDSA signature or the script aborts before writing
# the appcast (no item that claims to be signed but isn't).
SIGNED="true"
[ "$UNSIGNED" = "true" ] && SIGNED="false"
PUBLISH_APPCAST="false"
if [ "$SIGNED" = "true" ] && [ "$PRERELEASE" != "true" ]; then
  PUBLISH_APPCAST="true"
fi

ED_SIGNATURE=""
DMG_SIZE="$(stat -f%z "$DMG_OUT" 2>/dev/null || wc -c < "$DMG_OUT")"

if [ "$SIGNED" = "false" ]; then
  echo "release: --unsigned -> building an UNSIGNED local-test release." >&2
  echo "         The production appcast will not be modified; publish/upload mode is rejected." >&2
  PRERELEASE="true"
else
  SIGN_UPDATE="${SPARKLE_SIGN_UPDATE:-}"
  if [ -z "$SIGN_UPDATE" ]; then
    # PATH is the only implicit trust boundary. Do not execute the first
    # user-writable file named sign_update found anywhere under Developer data.
    SIGN_UPDATE="$(command -v sign_update 2>/dev/null || true)"
  fi
  GENERATE_KEYS="${SPARKLE_GENERATE_KEYS:-}"
  if [ -z "$GENERATE_KEYS" ] && [ -n "$SIGN_UPDATE" ]; then
    CANDIDATE_GENERATE_KEYS="$(dirname "$SIGN_UPDATE")/generate_keys"
    [ -x "$CANDIDATE_GENERATE_KEYS" ] && GENERATE_KEYS="$CANDIDATE_GENERATE_KEYS"
  fi
  [ -n "$GENERATE_KEYS" ] || GENERATE_KEYS="$(command -v generate_keys 2>/dev/null || true)"
  if [ -z "$GENERATE_KEYS" ] || [ ! -x "$GENERATE_KEYS" ]; then
    echo "release: ABORT — signed release requires Sparkle generate_keys to verify SUPublicEDKey." >&2
    echo "         Set SPARKLE_GENERATE_KEYS or place generate_keys beside sign_update." >&2
    exit 5
  fi
  KEYCHAIN_PUBLIC_KEY="$("$GENERATE_KEYS" -p 2>/dev/null | tr -d '\r\n' || true)"
  [ -n "$KEYCHAIN_PUBLIC_KEY" ] || {
    echo "release: ABORT — Sparkle generate_keys -p did not return a keychain public key." >&2
    exit 5
  }
  [ "$KEYCHAIN_PUBLIC_KEY" = "$SPARKLE_PUBLIC_KEY" ] || {
    echo "release: ABORT — Sparkle keychain public key does not match embedded SUPublicEDKey." >&2
    echo "         Refusing to publish an update signed by a different keychain private key." >&2
    exit 5
  }
  echo "release: Sparkle keychain public key matches embedded SUPublicEDKey."

  if [ -n "$SIGN_UPDATE" ] && [ -x "$SIGN_UPDATE" ]; then
    echo "release: Sparkle sign_update -> $SIGN_UPDATE"
    # Emits e.g.: sparkle:edSignature="...." length="...."
    SIGN_OUT="$("$SIGN_UPDATE" "$DMG_OUT" 2>/dev/null || true)"
    echo "  $SIGN_OUT"
    ED_SIGNATURE="$(printf '%s' "$SIGN_OUT" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
  fi
  # HARD GATE: a signed release with no usable signature must never reach the
  # appcast. Abort now — before any appcast write — with a non-zero exit.
  if [ -z "$ED_SIGNATURE" ]; then
    echo "release: ABORT — signed release requires a Sparkle EdDSA signature, but" >&2
    echo "         sign_update produced none (tool missing, key absent, or signing" >&2
    echo "         failed). Refusing to write an appcast item that claims to be" >&2
    echo "         signed but isn't." >&2
    echo "         Fix: ensure Sparkle's sign_update is on PATH (or set" >&2
    echo "         SPARKLE_SIGN_UPDATE) and the EdDSA key is in the login keychain;" >&2
    echo "         or re-run with --unsigned for a local test build." >&2
    exit 5
  fi
fi

# --- 6. Prepare appcast candidate (PRESERVING existing items) ---------------
# We PREPEND a new <item> into a candidate file, never rewriting old entries.
# The production appcast is replaced only after the draft release upload succeeds.
DOWNLOAD_URL="${DOWNLOAD_URL_BASE}/${TAG}/$(basename "$DMG_OUT")"
PUBDATE="$(date -u +'%a, %d %b %Y %H:%M:%S +0000')"
# Build an appcast item only for a stable signed release. Unsigned and pre-release
# artifacts remain outside the stable update channel.
if [ "$PUBLISH_APPCAST" = "true" ]; then
  ITEM_TITLE="${APP_DISPLAY_NAME} ${VERSION}"
  ENCLOSURE="<enclosure url=\"${DOWNLOAD_URL}\"
                 length=\"${DMG_SIZE}\"
                 type=\"application/octet-stream\"
                 sparkle:edSignature=\"${ED_SIGNATURE}\" />"
  ITEM=$(cat <<EOF
    <item>
      <title>${ITEM_TITLE}</title>
      <pubDate>${PUBDATE}</pubDate>
      <sparkle:version>${BUILD}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.0.0</sparkle:minimumSystemVersion>
      ${ENCLOSURE}
    </item>
EOF
  )
fi

APPCAST_CANDIDATE=""
if [ "$PUBLISH_APPCAST" = "true" ]; then
  APPCAST_CANDIDATE="$RELEASE_SCRATCH/appcast-${VERSION}-${BUILD}.xml"
  [ -f "$APPCAST_PATH" ] || {
    echo "release: ABORT — canonical appcast missing at $APPCAST_PATH" >&2
    exit 8
  }
  cp "$APPCAST_PATH" "$APPCAST_CANDIDATE"
  # Insert the new item immediately after the comment anchor in the template
  # ("release.sh inserts new <item> elements directly below this line."), so items
  # land exactly where that comment promises and the anchor stays ABOVE them.
  # Preserves every existing <item>. We write the multi-line item to a temp file
  # and slurp it inside awk — passing a multi-line string via `awk -v` breaks on
  # BSD awk ("newline in string"), so we avoid that entirely.
  # Fallback: if the anchor is absent (hand-edited appcast), insert after </language>.
  ITEM_FILE="$(mktemp)"
  printf '%s\n' "$ITEM" > "$ITEM_FILE"
  TMP_APPCAST="$(mktemp)"
  ANCHOR="release.sh inserts new <item> elements directly below this line."
  if grep -qF "$ANCHOR" "$APPCAST_CANDIDATE"; then
    MATCH="$ANCHOR"
  elif grep -qF "</language>" "$APPCAST_CANDIDATE"; then
    MATCH="</language>"
  else
    rm -f "$ITEM_FILE" "$TMP_APPCAST"
    echo "release: ABORT — appcast has neither the insertion anchor nor </language>." >&2
    exit 8
  fi
  awk -v itemfile="$ITEM_FILE" -v match_str="$MATCH" '
    index($0, match_str) && !done {
      print
      while ((getline line < itemfile) > 0) print line
      close(itemfile)
      done = 1
      next
    }
    { print }
  ' "$APPCAST_CANDIDATE" > "$TMP_APPCAST"
  mv "$TMP_APPCAST" "$APPCAST_CANDIDATE"
  rm -f "$ITEM_FILE"
  python3 "$REPO_ROOT/scripts/release/validate-appcast.py" "$APPCAST_CANDIDATE" || {
    echo "release: ABORT — generated appcast candidate failed release-item validation." >&2
    exit 8
  }
  echo "release: prepared signed appcast candidate at $APPCAST_CANDIDATE"
elif [ "$SIGNED" = "true" ]; then
  echo "release: signed pre-release — production appcast left unchanged."
else
  echo "release: unsigned build — production appcast left unchanged."
fi

# --- 7. gh release create ---------------------------------------------------
GH_FLAGS=( "$TAG" "$DMG_OUT" --repo "$GH_REPO" --title "${APP_DISPLAY_NAME} ${VERSION}" )
[ -n "$RELEASE_TARGET_RESOLVED" ] && GH_FLAGS+=( --target "$RELEASE_TARGET_RESOLVED" )
[ "$PRERELEASE" = "true" ] && GH_FLAGS+=( --prerelease )
[ "$PUBLISH_APPCAST" = "true" ] && GH_FLAGS+=( --draft )
[ -n "$NOTES" ] && GH_FLAGS+=( --notes-file "$NOTES" ) || GH_FLAGS+=( --generate-notes )

if command -v gh >/dev/null 2>&1; then
  echo "release: gh release create ${GH_FLAGS[*]}"
  echo "release: (DRY-RUN GUARD) set RELEASE_PUBLISH=1 to actually publish."
  if [ "${RELEASE_PUBLISH:-0}" = "1" ]; then
    if [ "$UNSIGNED" = "true" ]; then
      echo "release: ABORT — --unsigned is private/local dry-run packaging only." >&2
      echo "         Unsigned artifacts cannot be published or uploaded." >&2
      exit 9
    fi
    gh release create "${GH_FLAGS[@]}"
    if [ "$PUBLISH_APPCAST" = "true" ]; then
      mv "$APPCAST_CANDIDATE" "$APPCAST_PATH" || {
        echo "release: ERROR — $TAG exists, but the appcast candidate could not be installed." >&2
        echo "         Candidate retained at: $APPCAST_CANDIDATE" >&2
        exit 8
      }
      echo "release: created draft $TAG; appcast.xml updated locally but NOT committed or pushed."
      echo "         Commit it in the build repo, then use scripts/publish.sh stage and"
      echo "         scripts/publish.sh promote so the verified public main feed advances."
      echo "         Only then publish the draft: gh release edit $TAG --repo $GH_REPO --draft=false"
    elif [ "$SIGNED" = "true" ]; then
      echo "release: published signed pre-release $TAG; appcast unchanged."
    else
      echo "release: ABORT — unsigned upload reached an unreachable release branch." >&2
      exit 9
    fi
  else
    echo "release: skipped publish (dry run). DMG at $DMG_OUT."
    [ "$PUBLISH_APPCAST" = "true" ] \
      && echo "release: production appcast unchanged; review candidate at $APPCAST_CANDIDATE."
  fi
else
  if [ "${RELEASE_PUBLISH:-0}" = "1" ]; then
    echo "release: ABORT — RELEASE_PUBLISH=1 requires the gh CLI." >&2
    exit 9
  fi
  echo "release: NOTE — gh CLI not found; install it to publish (brew install gh)." >&2
  [ "$PUBLISH_APPCAST" = "true" ] \
    && echo "release: production appcast unchanged; candidate at $APPCAST_CANDIDATE." >&2
fi

echo "release: complete (version=$VERSION build=$BUILD notarized=$NOTARIZED signed=$SIGNED)."
