#!/usr/bin/env bash
#
# notarize.sh — submit a finished DMG (or, with --app-bundle, the .app itself)
# to Apple notarization, staple, verify.
#
# Notarization workflow: notarytool submit --wait + stapler staple, with release
# gates (spctl -a -vvv, parse notarytool log).
#
# TWO TARGET KINDS, same credentials and same staple/verify contract:
# default <path-to-dmg> the finished disk image
# --app-bundle <path-to-app> the app bundle itself, submitted as
# a ditto -c -k --keepParent zip and
# stapled IN PLACE, so the ticket
# travels with the app once a user
# drags it out of the DMG (offline
# first launch). A bare .app target
# without --app-bundle is still
# rejected.
#
# LOCAL UNSIGNED MODE: if no App Store Connect API key is configured, this script
# prints a clear explanation and exits 0 so explicit local smoke packaging remains
# usable. Official/public releases still fail closed in release.sh.
#
# SIGNED MODE: set the env vars below (or pass --key/--key-id/--issuer) and it
# performs a real notarize + staple + Gatekeeper verify.
#
# Credentials needed when signing is enabled (see the release runbook),
# either App Store Connect API key credentials:
# ASC_API_KEY_P8 path to the App Store Connect API key .p8 (or *_BASE64)
# ASC_API_KEY_ID the key ID (e.g. ABC123XYZ)
# ASC_API_ISSUER_ID the issuer UUID
# In CI these come from secrets (ASC_API_KEY_P8_BASE64 is base64-decoded here).
# or a locally stored notarytool profile:
# NOTARY_KEYCHAIN_PROFILE profile name created by notarytool store-credentials
# NOTARY_KEYCHAIN optional keychain path for that profile
#
# Usage:
# scripts/release/notarize.sh <path-to-dmg> \
# [--key <p8>] [--key-id <id>] [--issuer <uuid>]
# scripts/release/notarize.sh <path-to-app> --app-bundle [--key ...]
# (the target is always FIRST; options follow it)
#
# Exit codes: 0 success OR cleanly-skipped (local unsigned); 2 args/type;
# 3 missing target;
# 4 notarization rejected; 5 packaging/staple/verify failed.

set -euo pipefail

TARGET="${1:-}"
[ -n "$TARGET" ] && shift || true

KEY_PATH="${ASC_API_KEY_P8:-}"
KEY_ID="${ASC_API_KEY_ID:-}"
ISSUER="${ASC_API_ISSUER_ID:-}"
KEYCHAIN_PROFILE="${NOTARY_KEYCHAIN_PROFILE:-}"
KEYCHAIN="${NOTARY_KEYCHAIN:-}"
TEMP_KEY_PATH=""
SUBMIT_LOG=""
MOUNT_POINT=""
ZIP_DIR=""
APP_BUNDLE="false"

cleanup() {
  if [ -n "$MOUNT_POINT" ]; then
    hdiutil detach "$MOUNT_POINT" -quiet >/dev/null 2>&1 || true
    rmdir "$MOUNT_POINT" >/dev/null 2>&1 || true
  fi
  if [ -n "$ZIP_DIR" ]; then rm -rf -- "$ZIP_DIR"; fi
  if [ -n "$SUBMIT_LOG" ]; then rm -f -- "$SUBMIT_LOG"; fi
  if [ -n "$TEMP_KEY_PATH" ]; then rm -f -- "$TEMP_KEY_PATH"; fi
}
trap cleanup EXIT

while [ $# -gt 0 ]; do
  case "$1" in
    --app-bundle) APP_BUNDLE="true"; shift ;;
    --key)    KEY_PATH="${2:-}"; shift 2 ;;
    --key-id) KEY_ID="${2:-}"; shift 2 ;;
    --issuer) ISSUER="${2:-}"; shift 2 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed -n '1,45p'; exit 0 ;;
    *) echo "notarize: unknown arg '$1'" >&2; exit 2;;
  esac
done

if [ -z "$TARGET" ]; then
  echo "notarize: usage: notarize.sh <path-to-dmg>|<path-to-app> [--app-bundle] [--key ..]" >&2
  exit 2
fi
if [ ! -e "$TARGET" ]; then
  echo "notarize: target not found at '$TARGET'." >&2
  exit 3
fi
if [ "$APP_BUNDLE" = "true" ]; then
  # App-bundle mode is explicit and never inferred: the DMG stage must not be
  # able to reach it by accident, and a bare .app target still fails closed.
  case "$TARGET" in
    *.app);;
    *)
      echo "notarize: --app-bundle requires a .app bundle target." >&2
      exit 2
      ;;
  esac
  [ -d "$TARGET" ] || {
    echo "notarize: --app-bundle target '$TARGET' is not an app bundle directory." >&2
    exit 2
  }
else
  case "$TARGET" in
    *.dmg);;
    *)
      echo "notarize: only accepts a finished .dmg; package app bundles before submission." >&2
      exit 2
      ;;
  esac
fi

if [ -n "$KEYCHAIN_PROFILE" ] && {
  [ -n "$KEY_PATH" ] || [ -n "$KEY_ID" ] || [ -n "$ISSUER" ] || [ -n "${ASC_API_KEY_P8_BASE64:-}" ]
}; then
  echo "notarize: NOTARY_KEYCHAIN_PROFILE cannot be combined with ASC API-key credentials." >&2
  exit 2
fi

# If a base64 key blob is provided (CI secret) but no path, materialize it.
if [ -z "$KEY_PATH" ] && [ -n "${ASC_API_KEY_P8_BASE64:-}" ]; then
  TEMP_KEY_PATH="$(mktemp "${TMPDIR:-/tmp}/asc_key.p8.XXXXXX")"
  KEY_PATH="$TEMP_KEY_PATH"
  printf '%s' "${ASC_API_KEY_P8_BASE64}" | /usr/bin/base64 -D > "$KEY_PATH"
  unset ASC_API_KEY_P8_BASE64
fi

# ---------------------------------------------------------------------------
# Local unsigned short-circuit: no credentials -> explain + exit 0.
# ---------------------------------------------------------------------------
AUTH_ARGS=()
if [ -n "$KEYCHAIN_PROFILE" ]; then
  AUTH_ARGS=(--keychain-profile "$KEYCHAIN_PROFILE")
  if [ -n "$KEYCHAIN" ]; then
    AUTH_ARGS+=(--keychain "$KEYCHAIN")
  fi
elif [ -n "$KEY_PATH" ] && [ -n "$KEY_ID" ] && [ -n "$ISSUER" ]; then
  AUTH_ARGS=(--key "$KEY_PATH" --key-id "$KEY_ID" --issuer "$ISSUER")
else
  cat >&2 <<'EOF'
notarize: SKIPPED (local unsigned mode — no notarization credentials configured).

  The artifact is valid only for local unsigned testing. It is NOT notarized and
  will trip Gatekeeper on another Mac.

  For a signed release, provide all three:
      ASC_API_KEY_P8 (or ASC_API_KEY_P8_BASE64), ASC_API_KEY_ID, ASC_API_ISSUER_ID
  See the release runbook's "Signing credentials" section.
EOF
  echo "notarize: exiting 0 (clean skip)."
  exit 0
fi

if ! command -v xcrun >/dev/null 2>&1; then
  echo "notarize: xcrun not available — requires macOS + Xcode CLT." >&2
  exit 3
fi

# notarytool cannot ingest a bundle directly. Zip the app with ditto so the
# bundle (and its symlinks) survive the round trip; the TICKET is still stapled
# to the .app itself below, not to this throwaway archive.
SUBMIT_TARGET="$TARGET"
if [ "$APP_BUNDLE" = "true" ]; then
  ZIP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notary-app.XXXXXX")"
  SUBMIT_TARGET="$ZIP_DIR/$(basename "$TARGET").zip"
  echo "notarize: packaging '$TARGET' for submission (ditto -c -k --keepParent)..."
  /usr/bin/ditto -c -k --keepParent "$TARGET" "$SUBMIT_TARGET" || {
    echo "notarize: could not archive the app bundle for submission." >&2
    exit 5
  }
fi

echo "notarize: submitting '$TARGET' (notarytool submit --wait)..."
SUBMIT_LOG="$(mktemp "${TMPDIR:-/tmp}/notary-submit.txt.XXXXXX")"

# --wait blocks until Apple finishes; capture both human output and the request id.
set +e
xcrun notarytool submit "$SUBMIT_TARGET" \
  "${AUTH_ARGS[@]}" \
  --wait \
  --output-format plist > "$SUBMIT_LOG" 2>&1
SUBMIT_RC=$?
set -e

if [ $SUBMIT_RC -ne 0 ]; then
  echo "notarize: notarytool submit failed (rc=$SUBMIT_RC). Raw output:" >&2
  cat "$SUBMIT_LOG" >&2
  exit 4
fi

# Parse status + request id from the plist output.
STATUS="$(/usr/libexec/PlistBuddy -c 'Print :status' "$SUBMIT_LOG" 2>/dev/null || echo '')"
REQ_ID="$(/usr/libexec/PlistBuddy -c 'Print :id' "$SUBMIT_LOG" 2>/dev/null || echo '')"
echo "notarize: status='$STATUS' id='$REQ_ID'"

# Always fetch + print the detailed log (the audit trail).
if [ -n "$REQ_ID" ]; then
  echo "notarize: fetching notarytool log for $REQ_ID ..."
  xcrun notarytool log "$REQ_ID" "${AUTH_ARGS[@]}" || true
fi

if [ "$STATUS" != "Accepted" ]; then
  echo "notarize: REJECTED (status='$STATUS'). See the log above for issues." >&2
  exit 4
fi

# Staple the ticket so first launch works OFFLINE (no Gatekeeper round-trip).
echo "notarize: stapling ticket -> $TARGET"
if ! xcrun stapler staple "$TARGET"; then
  echo "notarize: stapler staple failed." >&2
  exit 5
fi
xcrun stapler validate "$TARGET" || { echo "notarize: stapler validate failed." >&2; exit 5; }

# Gatekeeper assessment: assess the stapled app directly (app-bundle mode) or
# mount the finished DMG and assess its single app. spctl -a -vvv is the
# release gate in both cases.
echo "notarize: Gatekeeper verify (spctl -a -vvv)..."
if [ "$APP_BUNDLE" = "true" ]; then
  spctl -a -vvv -t execute "$TARGET" \
    || { echo "notarize: spctl rejected the stapled app bundle." >&2; exit 5; }
  echo "notarize: SUCCESS — '$TARGET' notarized, stapled, and Gatekeeper-accepted."
  exit 0
fi
MOUNT_POINT="$(mktemp -d "${TMPDIR:-/tmp}/abendrot-verify.XXXXXX")"
hdiutil attach "$TARGET" -nobrowse -quiet -mountpoint "$MOUNT_POINT" \
  || { echo "notarize: could not mount notarized DMG for verification." >&2; exit 5; }
APPS=("$MOUNT_POINT"/*.app)
if [ "${#APPS[@]}" -ne 1 ] || [ ! -d "${APPS[0]}" ]; then
  echo "notarize: expected exactly one app at the DMG root." >&2
  exit 5
fi
spctl -a -vvv -t execute "${APPS[0]}" \
  || { echo "notarize: spctl rejected app in DMG." >&2; exit 5; }
hdiutil detach "$MOUNT_POINT" -quiet \
  || { echo "notarize: could not detach verification DMG." >&2; exit 5; }
rmdir "$MOUNT_POINT" >/dev/null 2>&1 || true
MOUNT_POINT=""

echo "notarize: SUCCESS — '$TARGET' notarized, stapled, and Gatekeeper-accepted."
