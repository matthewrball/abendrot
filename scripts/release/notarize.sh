#!/usr/bin/env bash
#
# notarize.sh — submit a DMG (or .app/.zip) to Apple notarization, staple, verify.
#
# Submits with notarytool submit --wait, then stapler staple; the release gate is
# spctl -a -vvv plus parsing the notarytool log. Signing is currently deferred, so
# this MUST no-op gracefully with no Apple credentials (Mode B).
#
# MODE B (default, TODAY, no Apple account): if no App Store Connect API key is
# configured, this script prints a clear explanation and exits 0 (success) so the
# release/CI pipeline is never blocked by the absence of credentials.
#
# MODE A (when the founder buys the $99 Apple Developer Program): set the env
# vars below (or pass --key/--key-id/--issuer) and it performs a real notarize +
# staple + Gatekeeper verify.
#
# Credentials needed for Mode A:
#   ASC_API_KEY_P8       path to the App Store Connect API key .p8     (or *_BASE64)
#   ASC_API_KEY_ID       the key ID  (e.g. ABC123XYZ)
#   ASC_API_ISSUER_ID    the issuer UUID
# In CI these come from secrets (ASC_API_KEY_P8_BASE64 is base64-decoded here).
#
# Usage:
#   scripts/release/notarize.sh <path-to-dmg|app|zip> \
#       [--key <p8>] [--key-id <id>] [--issuer <uuid>]
#
# Exit codes: 0 success OR cleanly-skipped (Mode B); 2 args; 3 missing target;
#             4 notarization rejected; 5 staple/verify failed.

set -euo pipefail

TARGET="${1:-}"
[ -n "$TARGET" ] && shift || true

KEY_PATH="${ASC_API_KEY_P8:-}"
KEY_ID="${ASC_API_KEY_ID:-}"
ISSUER="${ASC_API_ISSUER_ID:-}"

while [ $# -gt 0 ]; do
  case "$1" in
    --key)    KEY_PATH="${2:-}"; shift 2 ;;
    --key-id) KEY_ID="${2:-}"; shift 2 ;;
    --issuer) ISSUER="${2:-}"; shift 2 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed -n '1,30p'; exit 0 ;;
    *) echo "notarize: unknown arg '$1'" >&2; exit 2 ;;
  esac
done

if [ -z "$TARGET" ]; then
  echo "notarize: usage: notarize.sh <path-to-dmg|app|zip> [--key ..]" >&2
  exit 2
fi
if [ ! -e "$TARGET" ]; then
  echo "notarize: target not found at '$TARGET'." >&2
  exit 3
fi

# If a base64 key blob is provided (CI secret) but no path, materialize it.
if [ -z "$KEY_PATH" ] && [ -n "${ASC_API_KEY_P8_BASE64:-}" ]; then
  KEY_PATH="$(mktemp "${TMPDIR:-/tmp}/asc_key.XXXXXX.p8")"
  # shellcheck disable=SC2064
  trap "rm -f '$KEY_PATH'" EXIT
  echo "${ASC_API_KEY_P8_BASE64}" | base64 --decode > "$KEY_PATH"
fi

# ---------------------------------------------------------------------------
# MODE B short-circuit: no credentials -> explain + exit 0 (do not block).
# ---------------------------------------------------------------------------
if [ -z "$KEY_PATH" ] || [ -z "$KEY_ID" ] || [ -z "$ISSUER" ]; then
  cat >&2 <<'EOF'
notarize: SKIPPED (Mode B — no Apple credentials configured).

  The signing/notarization step is DEFERRED per the Wave-1 founder decision
  (no $99 Apple Developer Program yet). The DMG/app you built is valid for
  LOCAL/unsigned testing today, but it is NOT notarized: on another Mac it will
  trip Gatekeeper (right-click > Open, or `xattr -dr com.apple.quarantine`).

  To enable notarization (Mode A), provide all three:
      ASC_API_KEY_P8 (or ASC_API_KEY_P8_BASE64), ASC_API_KEY_ID, ASC_API_ISSUER_ID
  These come from an App Store Connect API key created under your Apple Developer
  Program account.
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

# Always fetch + print the detailed log (the record trail; parse notarytool log).
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

# Gatekeeper assessment. For a DMG, assess the mounted app; for an .app assess
# directly. spctl -a -vvv is the release gate.
echo "notarize: Gatekeeper verify (spctl -a -vvv)..."
case "$TARGET" in
  *.dmg)
    MNT="$(mktemp -d "${TMPDIR:-/tmp}/abendrot-verify.XXXXXX")"
    hdiutil attach "$TARGET" -nobrowse -quiet -mountpoint "$MNT"
    APP_IN_DMG="$(find "$MNT" -maxdepth 1 -name '*.app' -print -quit)"
    if [ -n "$APP_IN_DMG" ]; then
      spctl -a -vvv -t execute "$APP_IN_DMG" || { hdiutil detach "$MNT" -quiet; echo "notarize: spctl rejected app in DMG." >&2; exit 5; }
    fi
    hdiutil detach "$MNT" -quiet
    ;;
  *.app)
    spctl -a -vvv -t execute "$TARGET" || { echo "notarize: spctl rejected app." >&2; exit 5; }
    ;;
  *)
    echo "notarize: note — stapled '$TARGET'; spctl execute-assessment skipped for this type."
    ;;
esac

echo "notarize: SUCCESS — '$TARGET' notarized, stapled, and Gatekeeper-accepted."
