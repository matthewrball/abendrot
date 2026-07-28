#!/usr/bin/env bash
#
# notarize.sh — submit the finished DMG to Apple notarization, staple, verify.
#
# Notarization workflow: notarytool submit --wait + stapler staple, with release
# gates (spctl -a -vvv, parse notarytool log).
#
# LOCAL UNSIGNED MODE: if no App Store Connect API key is configured, this script
# prints a clear explanation and exits 0 so explicit local smoke packaging remains
# usable. Official/public releases still fail closed in release.sh.
#
# SIGNED MODE: set the env vars below (or pass --key/--key-id/--issuer) and it
# performs a real notarize + staple + Gatekeeper verify.
#
# Credentials needed when signing is enabled (see the release runbook):
# ASC_API_KEY_P8 path to the App Store Connect API key .p8 (or *_BASE64)
# ASC_API_KEY_ID the key ID (e.g. ABC123XYZ)
# ASC_API_ISSUER_ID the issuer UUID
# In CI these come from secrets (ASC_API_KEY_P8_BASE64 is base64-decoded here).
#
# Usage:
# scripts/release/notarize.sh <path-to-dmg> \
# [--key <p8>] [--key-id <id>] [--issuer <uuid>]
#
# Exit codes: 0 success OR cleanly-skipped (local unsigned); 2 args/type;
# 3 missing target;
# 4 notarization rejected; 5 staple/verify failed.

set -euo pipefail

TARGET="${1:-}"
[ -n "$TARGET" ] && shift || true

KEY_PATH="${ASC_API_KEY_P8:-}"
KEY_ID="${ASC_API_KEY_ID:-}"
ISSUER="${ASC_API_ISSUER_ID:-}"
TEMP_KEY_PATH=""
SUBMIT_LOG=""
MOUNT_POINT=""

cleanup() {
  if [ -n "$MOUNT_POINT" ]; then
    hdiutil detach "$MOUNT_POINT" -quiet >/dev/null 2>&1 || true
    rmdir "$MOUNT_POINT" >/dev/null 2>&1 || true
  fi
  if [ -n "$SUBMIT_LOG" ]; then rm -f -- "$SUBMIT_LOG"; fi
  if [ -n "$TEMP_KEY_PATH" ]; then rm -f -- "$TEMP_KEY_PATH"; fi
}
trap cleanup EXIT

while [ $# -gt 0 ]; do
  case "$1" in
    --key)    KEY_PATH="${2:-}"; shift 2 ;;
    --key-id) KEY_ID="${2:-}"; shift 2 ;;
    --issuer) ISSUER="${2:-}"; shift 2 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed -n '1,30p'; exit 0 ;;
    *) echo "notarize: unknown arg '$1'" >&2; exit 2;;
  esac
done

if [ -z "$TARGET" ]; then
  echo "notarize: usage: notarize.sh <path-to-dmg> [--key ..]" >&2
  exit 2
fi
if [ ! -e "$TARGET" ]; then
  echo "notarize: target not found at '$TARGET'." >&2
  exit 3
fi
case "$TARGET" in
  *.dmg);;
  *)
    echo "notarize: only accepts a finished .dmg; package app bundles before submission." >&2
    exit 2
    ;;
esac

# If a base64 key blob is provided (CI secret) but no path, materialize it.
if [ -z "$KEY_PATH" ] && [ -n "${ASC_API_KEY_P8_BASE64:-}" ]; then
  TEMP_KEY_PATH="$(mktemp "${TMPDIR:-/tmp}/asc_key.XXXXXX.p8")"
  KEY_PATH="$TEMP_KEY_PATH"
  printf '%s' "${ASC_API_KEY_P8_BASE64}" | /usr/bin/base64 -D > "$KEY_PATH"
  unset ASC_API_KEY_P8_BASE64
fi

# ---------------------------------------------------------------------------
# Local unsigned short-circuit: no credentials -> explain + exit 0.
# ---------------------------------------------------------------------------
if [ -z "$KEY_PATH" ] || [ -z "$KEY_ID" ] || [ -z "$ISSUER" ]; then
  cat >&2 <<'EOF'
notarize: SKIPPED (local unsigned mode — no notarization credentials configured).

  The DMG is valid only for local unsigned testing. It is NOT notarized and will
  trip Gatekeeper on another Mac.

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

echo "notarize: submitting '$TARGET' (notarytool submit --wait)..."
SUBMIT_LOG="$(mktemp "${TMPDIR:-/tmp}/notary-submit.XXXXXX.txt")"

# --wait blocks until Apple finishes; capture both human output and the request id.
set +e
xcrun notarytool submit "$TARGET" \
  --key "$KEY_PATH" \
  --key-id "$KEY_ID" \
  --issuer "$ISSUER" \
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
  xcrun notarytool log "$REQ_ID" \
    --key "$KEY_PATH" --key-id "$KEY_ID" --issuer "$ISSUER" || true
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

# Gatekeeper assessment: mount the finished DMG and assess its single app.
# spctl -a -vvv is the release gate.
echo "notarize: Gatekeeper verify (spctl -a -vvv)..."
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
