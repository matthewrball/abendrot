#!/usr/bin/env bash
#
# plain-dmg.sh — scripted, headless DMG builder (Abendrot MODE B default).
#
# Why this exists: create-dmg's branded path runs AppleScript
# Finder automation that HANGS on headless CI (create-dmg issue #154). This
# script uses only `hdiutil` + `ln -s`, so it works:
#   - TODAY, with no Apple Developer account (the app can be unsigned/ad-hoc),
#   - on headless CI runners and forked-PR runs (no secrets needed),
#   - as a fully scripted fallback (fixed volume name, no random Finder state).
#
# NOTE: this is NOT byte-for-byte reproducible. `hdiutil create -format UDZO`
# embeds build timestamps and gzip metadata, so two runs from identical inputs
# produce different bytes/SHA256. If you ever need reproducible output, normalize
# the environment (e.g. export SOURCE_DATE_EPOCH) and post-process — out of scope
# here. We rely on Apple code-signing + Sparkle EdDSA for integrity, not on a
# stable hash of the DMG itself.
#
# It produces a functional drag-to-Applications DMG WITHOUT custom background
# art or window geometry. For the branded "unboxing" DMG, see pretty-dmg.sh
# (UI runner only). Releases are gated on >=1 notarized+stapled DMG *when
# signing is enabled*; this plain DMG is the always-available baseline.
#
# Usage:
#   scripts/dmg/plain-dmg.sh --app <path/to/Abendrot.app> --out <path/to/out.dmg> \
#                            [--volname "Abendrot"]
#
# Exit codes: 0 success; 2 bad/missing args; 3 missing app; 4 hdiutil failure.

set -euo pipefail

APP=""
OUT=""
VOLNAME="Abendrot"

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed -n '1,30p'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --app)     APP="${2:-}"; shift 2 ;;
    --out)     OUT="${2:-}"; shift 2 ;;
    --volname) VOLNAME="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "plain-dmg: unknown arg '$1'" >&2; usage >&2; exit 2 ;;
  esac
done

if [ -z "$APP" ] || [ -z "$OUT" ]; then
  echo "plain-dmg: --app and --out are required." >&2
  usage >&2
  exit 2
fi

if [ ! -d "$APP" ]; then
  echo "plain-dmg: app not found at '$APP'." >&2
  echo "           (Expected a built Abendrot.app. In Mode B this can be an" >&2
  echo "            unsigned/ad-hoc local build — no Apple account required.)" >&2
  exit 3
fi

# hdiutil is part of macOS; bail clearly on non-macOS (e.g. a Linux runner).
if ! command -v hdiutil >/dev/null 2>&1; then
  echo "plain-dmg: hdiutil not available — this script requires macOS." >&2
  exit 4
fi

APP_NAME="$(basename "$APP")"
OUT_DIR="$(dirname "$OUT")"
mkdir -p "$OUT_DIR"

# Stage the DMG contents in a temp dir: the .app + a symlink to /Applications
# (the universal "drag here to install" affordance; works in every Finder
# without any custom window scripting).
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/abendrot-dmg.XXXXXX")"
cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT

echo "plain-dmg: staging '$APP_NAME' + /Applications symlink..."
# ditto preserves the app bundle (and any code signature/xattrs) faithfully.
ditto "$APP" "$STAGE/$APP_NAME"
ln -s /Applications "$STAGE/Applications"

# Build the compressed, read-only DMG (scripted, headless — not byte-reproducible).
#   -format UDZO : zlib-compressed, read-only (standard distributable DMG).
#   -fs HFS+     : broad compatibility for app DMGs.
# Remove any stale output first so reruns are idempotent.
rm -f "$OUT"

echo "plain-dmg: creating DMG -> $OUT"
if ! hdiutil create \
      -volname "$VOLNAME" \
      -srcfolder "$STAGE" \
      -fs HFS+ \
      -format UDZO \
      -ov \
      "$OUT" >/dev/null; then
  echo "plain-dmg: hdiutil create failed." >&2
  exit 4
fi

# Report SHA256 — the Homebrew cask + appcast both need it.
if command -v shasum >/dev/null 2>&1; then
  SHA="$(shasum -a 256 "$OUT" | awk '{print $1}')"
  echo "plain-dmg: done."
  echo "  path   : $OUT"
  echo "  sha256 : $SHA"
else
  echo "plain-dmg: done -> $OUT"
fi
