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
#   1. Read version + build number from the EXPORTED app's Info.plist (plutil).
#   2. Warn on a duplicate/sub-decreasing build number vs the existing appcast.
#   3. Build the DMG (pretty on a UI runner, else plain) — credential-less safe.
#   4. When signing is enabled: notarize + staple + verify via notarize.sh.
#   5. Sparkle-sign the DMG with `sign_update` (EdDSA) — the SINGLE release
#      authority's key (local machine, key in login keychain).
#   6. Update appcast.xml PRESERVING existing <item> entries (prepend the new one).
#   7. `gh release create` the tag, upload the DMG, attach notes.
#
# DESIGN RULE: release is GATED on >=1 notarized+stapled DMG WHEN
# signing is enabled. When signing is deferred (no Apple account) the gate is
# relaxed and the script clearly stamps the output as an UNSIGNED pre-release.
#
# This file is a working SKELETON: the Sparkle + appcast + gh steps are real
# command lines, guarded so the script runs end-to-end TODAY without credentials
# and tells you exactly what each later step will do. Configurable placeholders
# (scheme/app name) are env vars at the top.
#
# SIGNING RULE: an appcast <item> that carries a
# `sparkle:edSignature` attribute is a PROMISE that the enclosure is EdDSA-signed
# by the single release authority. Therefore:
#   * SIGNED path (default for a real release): a missing/empty EdDSA signature is
#     a HARD FAILURE — the script exits non-zero and writes NOTHING to the
#     appcast. We never publish an item that claims to be signed but isn't.
#   * UNSIGNED path (--unsigned, local testing only): the script OMITS the signature
#     attributes entirely (never an empty string), stamps the build UNSIGNED, and
#     forces a GitHub pre-release. Such an item must not feed an auto-update
#     channel (Sparkle with SUPublicEDKey set will reject an unsigned enclosure).
#
# Usage:
#   scripts/release/release.sh --app <exported/Abendrot.app> [--prerelease] \
#       [--notes <notes.md>] [--dmg-mode auto|pretty|plain] [--unsigned]
#
# Env (signing-enabled only): ASC_API_KEY_P8(_BASE64), ASC_API_KEY_ID, ASC_API_ISSUER_ID,
#   SPARKLE_SIGN_UPDATE (path to Sparkle's sign_update tool; auto-discovered).
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# ---- PLACEHOLDERS ----
APP_DISPLAY_NAME="Abendrot"
GH_REPO="matthewrball/abendrot"
APPCAST_PATH="$REPO_ROOT/appcast.xml"            # hosted via GitHub (raw)
DOWNLOAD_URL_BASE="https://github.com/${GH_REPO}/releases/download"
# --------------------------------------------

APP=""
NOTES=""
PRERELEASE="false"
DMG_MODE="auto"
UNSIGNED="false"   # --unsigned: local-testing path; OMITS edSignature attributes.

while [ $# -gt 0 ]; do
  case "$1" in
    --app)        APP="${2:-}"; shift 2 ;;
    --notes)      NOTES="${2:-}"; shift 2 ;;
    --prerelease) PRERELEASE="true"; shift ;;
    --dmg-mode)   DMG_MODE="${2:-}"; shift 2 ;;
    --unsigned)   UNSIGNED="true"; shift ;;
    -h|--help)    grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed -n '1,50p'; exit 0 ;;
    *) echo "release: unknown arg '$1'" >&2; exit 2 ;;
  esac
done

[ -n "$APP" ] || { echo "release: --app <exported app> is required." >&2; exit 2; }
[ -d "$APP" ] || { echo "release: app not found at '$APP'." >&2; exit 3; }

# --- 1. Read version + build from Info.plist -------------------------------
PLIST="$APP/Contents/Info.plist"
[ -f "$PLIST" ] || { echo "release: Info.plist missing in app bundle." >&2; exit 3; }
VERSION="$(/usr/bin/plutil -extract CFBundleShortVersionString raw "$PLIST" 2>/dev/null || echo '')"
BUILD="$(/usr/bin/plutil -extract CFBundleVersion raw "$PLIST" 2>/dev/null || echo '')"
[ -n "$VERSION" ] || { echo "release: could not read CFBundleShortVersionString." >&2; exit 3; }
echo "release: $APP_DISPLAY_NAME version=$VERSION build=$BUILD prerelease=$PRERELEASE"
TAG="v$VERSION"

# --- 2. Duplicate/decreasing build guard vs existing appcast ----------------
# The appcast uses the ELEMENT form (<sparkle:version>BUILD</sparkle:version>),
# written in step 6 below and in appcast.template.xml — NOT the attribute form.
# Grep the same format the appcast actually uses so this guard really fires.
if [ -f "$APPCAST_PATH" ] && grep -q "<sparkle:version>$BUILD</sparkle:version>" "$APPCAST_PATH" 2>/dev/null; then
  echo "release: WARNING — build number $BUILD already appears in appcast.xml." >&2
  echo "         Bump CFBundleVersion before releasing (Sparkle compares builds)." >&2
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
# SIGNING IS GUARDED behind the SAME "no Developer ID" condition the rest of the
# pipeline uses (signing deferred): when ASC_API_KEY_ID is unset OR --unsigned is
# passed, we EMBED the helper but SKIP codesign, leaving a clear note. This keeps
# the structure exercised end-to-end locally (the binary really is embedded) while
# never attempting to sign without an identity.
CLI_PKG="$REPO_ROOT/cli"
CLI_SIGN_ID="app.abendrot.Abendrot.cli"     # unique helper identifier (NOT the app's id)
DEVELOPER_ID_APP="${DEVELOPER_ID_APP:-Developer ID Application}"  # signing identity

embed_cli_helper() {
  local app="$1"
  [ -d "$CLI_PKG" ] || { echo "release: NOTE — no cli/ package at '$CLI_PKG'; skipping helper embed." >&2; return 0; }

  echo "release: building abendrot CLI helper (swift build -c release)..."
  ( cd "$CLI_PKG" && swift build -c release ) || {
    echo "release: WARNING — CLI helper build failed; shipping app WITHOUT the embedded helper." >&2
    return 0
  }
  local cli_bin="$CLI_PKG/.build/release/abendrot"
  [ -x "$cli_bin" ] || { echo "release: WARNING — built CLI not found at '$cli_bin'." >&2; return 0; }

  # Contents/Helpers/ (NOT Contents/MacOS/) — avoids the case-insensitive collision
  # with the app's own `Abendrot` executable (see the DEVIATION note above).
  local helpers_dir="$app/Contents/Helpers"
  local dest="$helpers_dir/abendrot"
  mkdir -p "$helpers_dir"
  echo "release: embedding helper -> $dest"
  cp "$cli_bin" "$dest"
  chmod 755 "$dest"

  # Sign the helper FIRST, inside-out — ONLY when a Developer ID identity is
  # configured and this is a SIGNED build. Otherwise leave it unsigned
  # (unsigned local builds) with a clear note; the app's own export step is
  # likewise unsigned today.
  if [ "$UNSIGNED" = "true" ] || [ -z "${ASC_API_KEY_ID:-}" ]; then
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
  echo "release: helper signed + verified. (App is signed inside-out AFTER this, at export.)"
  # NOTE: after the .app is signed at export, also run (when signing is enabled):
  #   codesign --verify --deep --strict "$app"
  #   spctl -a -vvv --type execute "$dest"
  # These live with the export/notarize step (the app must be signed first).
}

embed_cli_helper "$APP"

# --- 3. Build the DMG -------------------------------------------------------
DMG_OUT="$REPO_ROOT/release-scratch/${APP_DISPLAY_NAME}-${VERSION}.dmg"
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
    *) echo plain ;;
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
if "$REPO_ROOT/scripts/release/notarize.sh" "$DMG_OUT"; then
  # Distinguish "actually notarized" from "skipped" by checking for a stapled ticket.
  if xcrun stapler validate "$DMG_OUT" >/dev/null 2>&1; then
    NOTARIZED="true"
  fi
fi

# Release gate: block a SIGNED release that failed to notarize/staple.
if [ -n "${ASC_API_KEY_ID:-}" ] && [ "$NOTARIZED" != "true" ]; then
  echo "release: ABORT — signing is configured but the DMG is not notarized+stapled." >&2
  echo "         Releases are gated on >=1 notarized+stapled DMG." >&2
  exit 4
fi
if [ "$NOTARIZED" != "true" ]; then
  echo "release: NOTE — UNSIGNED pre-release. Mark the GitHub release as" >&2
  echo "         pre-release and document the right-click>Open / xattr workaround." >&2
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

ED_SIGNATURE=""
DMG_SIZE="$(stat -f%z "$DMG_OUT" 2>/dev/null || wc -c < "$DMG_OUT")"

if [ "$SIGNED" = "false" ]; then
  echo "release: --unsigned -> building an UNSIGNED local-test release." >&2
  echo "         The appcast item will OMIT sparkle:edSignature entirely (not an" >&2
  echo "         empty string) and the GitHub release is forced to pre-release." >&2
  PRERELEASE="true"
else
  SIGN_UPDATE="${SPARKLE_SIGN_UPDATE:-}"
  if [ -z "$SIGN_UPDATE" ]; then
    # Auto-discover within an SPM/Sparkle checkout or Homebrew.
    SIGN_UPDATE="$(command -v sign_update 2>/dev/null || true)"
    [ -z "$SIGN_UPDATE" ] && SIGN_UPDATE="$(find "$REPO_ROOT" ~/Library/Developer -name sign_update -type f 2>/dev/null | head -1 || true)"
  fi
  if [ -n "$SIGN_UPDATE" ] && [ -x "$SIGN_UPDATE" ]; then
    echo "release: Sparkle sign_update -> $SIGN_UPDATE"
    # Emits e.g.:  sparkle:edSignature="...." length="...."
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

# --- 6. Update appcast.xml (PRESERVING existing items) ----------------------
# We PREPEND a new <item> into <channel>, never rewriting old entries (Sparkle
# clients dedupe by build). If appcast.xml does not exist, scaffold a minimal one.
DOWNLOAD_URL="${DOWNLOAD_URL_BASE}/${TAG}/$(basename "$DMG_OUT")"
PUBDATE="$(date -u +'%a, %d %b %Y %H:%M:%S +0000')"
# Build the <enclosure> two ways:
#   SIGNED   -> include sparkle:edSignature (guaranteed non-empty by step 5).
#   UNSIGNED -> OMIT the attribute entirely (never edSignature="") and tag the
#               title so the item self-documents as a local test build.
if [ "$SIGNED" = "true" ]; then
  ITEM_TITLE="${APP_DISPLAY_NAME} ${VERSION}"
  ENCLOSURE="<enclosure url=\"${DOWNLOAD_URL}\"
                 length=\"${DMG_SIZE}\"
                 type=\"application/octet-stream\"
                 sparkle:edSignature=\"${ED_SIGNATURE}\" />"
else
  ITEM_TITLE="${APP_DISPLAY_NAME} ${VERSION} (UNSIGNED dev build)"
  ENCLOSURE="<enclosure url=\"${DOWNLOAD_URL}\"
                 length=\"${DMG_SIZE}\"
                 type=\"application/octet-stream\" />"
fi
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

if [ ! -f "$APPCAST_PATH" ]; then
  echo "release: scaffolding new appcast.xml"
  cp "$REPO_ROOT/scripts/release/appcast.template.xml" "$APPCAST_PATH"
fi
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
if grep -qF "$ANCHOR" "$APPCAST_PATH"; then
  MATCH="$ANCHOR"
else
  MATCH="</language>"
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
' "$APPCAST_PATH" > "$TMP_APPCAST"
mv "$TMP_APPCAST" "$APPCAST_PATH"
rm -f "$ITEM_FILE"
echo "release: appcast.xml updated (new item prepended; existing items preserved)."

# --- 7. gh release create ---------------------------------------------------
GH_FLAGS=( "$TAG" "$DMG_OUT" --repo "$GH_REPO" --title "${APP_DISPLAY_NAME} ${VERSION}" )
[ "$PRERELEASE" = "true" ] && GH_FLAGS+=( --prerelease )
[ -n "$NOTES" ] && GH_FLAGS+=( --notes-file "$NOTES" ) || GH_FLAGS+=( --generate-notes )

if command -v gh >/dev/null 2>&1; then
  echo "release: gh release create ${GH_FLAGS[*]}"
  echo "release: (DRY-RUN GUARD) set RELEASE_PUBLISH=1 to actually publish."
  if [ "${RELEASE_PUBLISH:-0}" = "1" ]; then
    # Order matters: create the GitHub release FIRST (so the enclosure download
    # URL resolves), THEN commit+push the appcast so the RAW GitHub URL Sparkle
    # reads on `main` actually reflects the new <item>. Without this push, clients
    # would fetch a stale appcast that omits the just-published release.
    gh release create "${GH_FLAGS[@]}"
    echo "release: committing + pushing updated appcast.xml so its raw URL is coherent..."
    if git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
      git -C "$REPO_ROOT" add "$APPCAST_PATH"
      git -C "$REPO_ROOT" commit -m "release: appcast for ${APP_DISPLAY_NAME} ${VERSION}" \
        && git -C "$REPO_ROOT" push \
        || echo "release: WARNING — appcast commit/push failed; commit + push it MANUALLY," >&2
    else
      echo "release: WARNING — not a git checkout; COMMIT + PUSH appcast.xml manually so" >&2
      echo "         the raw GitHub URL Sparkle reads reflects the new item." >&2
    fi
    echo "release: published $TAG."
  else
    echo "release: skipped publish (dry run). DMG at $DMG_OUT, appcast staged."
    echo "release: (on publish, the appcast is committed+pushed AFTER the release so its"
    echo "         raw URL reflects the new item — see step 7.)"
  fi
else
  echo "release: NOTE — gh CLI not found; install it to publish (brew install gh)." >&2
fi

echo "release: complete (version=$VERSION build=$BUILD notarized=$NOTARIZED signed=$SIGNED)."
