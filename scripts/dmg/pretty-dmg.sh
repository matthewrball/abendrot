#!/usr/bin/env bash
#
# pretty-dmg.sh — branded "unboxing" DMG (Abendrot, UI-runner only).
#
# Two DMG modes (branded + plain),
# with the DMG as unboxing: split-screen cold->warm background so dragging the app
# from the "cold/blue" side to the "warm" Applications side demos the product).
#
# IMPORTANT — UI RUNNER ONLY. create-dmg art-directs the Finder window via
# AppleScript, which requires a logged-in WindowServer session. It HANGS on
# headless CI (create-dmg issue #154). Run this:
# - locally on the maintainer's Mac, OR
# - on the self-hosted UI runner with a logged-in user.
# For headless/forked-PR/Mode-B builds, use plain-dmg.sh instead. Releases are
# gated on >=1 notarized+stapled DMG when signing is enabled; the pretty
# DMG is preferred for public releases, with plain-dmg as the guaranteed fallback.
#
# Brand-asset dependency (BLOCKING for final art, NON-blocking for function):
# The split-screen cold->warm background PNG (@1x + @2x) is brand-owned
# . Until it lands, this script falls back to NO background (still a
# functional drag-to-Applications DMG). Drop the art at:
# scripts/dmg/assets/dmg-background.png (1x, 660x400 pt -> 660x400 px)
# scripts/dmg/assets/dmg-background@2x.png (2x, 1320x800 px)
# and (optional) a volume icon at:
# scripts/dmg/assets/volume.icns
# The window geometry + icon coordinates below are RESERVED to match that art
# (see GEOMETRY block). Design the background to these coordinates, or update them here.
#
# Usage:
# scripts/dmg/pretty-dmg.sh --app <Abendrot.app> --out <out.dmg> \
# [--volname "Abendrot"] [--background <png>] [--volicon <icns>]
#
# Exit codes: 0 ok; 2 args; 3 missing app; 5 create-dmg missing; 6 build fail.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSETS_DIR="$SCRIPT_DIR/assets"

APP=""
OUT=""
VOLNAME="Abendrot"
BACKGROUND="$ASSETS_DIR/dmg-background.png"   # brand art (placeholder until delivered)
VOLICON="$ASSETS_DIR/volume.icns"            # optional brand volume icon

usage() { grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed -n '1,40p'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --app)        APP="${2:-}"; shift 2 ;;
    --out)        OUT="${2:-}"; shift 2 ;;
    --volname)    VOLNAME="${2:-}"; shift 2 ;;
    --background) BACKGROUND="${2:-}"; shift 2 ;;
    --volicon)    VOLICON="${2:-}"; shift 2 ;;
    -h|--help)    usage; exit 0 ;;
    *) echo "pretty-dmg: unknown arg '$1'" >&2; usage >&2; exit 2;;
  esac
done

if [ -z "$APP" ] || [ -z "$OUT" ]; then
  echo "pretty-dmg: --app and --out are required." >&2; usage >&2; exit 2
fi
if [ ! -d "$APP" ]; then
  echo "pretty-dmg: app not found at '$APP'." >&2; exit 3
fi

# create-dmg = the create-dmg/create-dmg SHELL tool (brew install create-dmg).
# NOTE: this is NOT sindresorhus/create-dmg (a zero-config npm tool that accepts
# none of the window/icon flags below) — the flag set here is specific to the
# shell create-dmg and would fail under the npm one.
if ! command -v create-dmg >/dev/null 2>&1; then
  echo "pretty-dmg: 'create-dmg' not found." >&2
  echo "            Install:  brew install create-dmg  (create-dmg/create-dmg shell tool)" >&2
  echo "            For headless CI without credentials, use scripts/dmg/plain-dmg.sh instead." >&2
  exit 5
fi

# Headless guard: warn loudly if there's no GUI session (AppleScript will hang).
# We don't hard-fail (some UI runners report oddly), but we make the risk explicit.
if [ -z "${SSH_TTY:-}" ] && ! pgrep -x WindowServer >/dev/null 2>&1; then
  echo "pretty-dmg: WARNING — no WindowServer detected. create-dmg may HANG here." >&2
  echo "            Run on a logged-in UI session, or use plain-dmg.sh." >&2
fi

APP_NAME="$(basename "$APP")"
OUT_DIR="$(dirname "$OUT")"; mkdir -p "$OUT_DIR"
rm -f "$OUT"

# ---------------------------------------------------------------------------
# GEOMETRY (RESERVED for the split-screen cold->warm background).
# Window is 660x400 pt. The .app sits on the LEFT ("cold/blue") side; the
# /Applications drop-link sits on the RIGHT ("warm") side, so the drag gesture
# moves the icon across the cold->warm gradient — the unboxing demo.
# Paint the gradient + the connecting arrow to land under these points.
WINDOW_X=200          # window top-left X on screen
WINDOW_Y=120          # window top-left Y on screen
WINDOW_W=660          # window width  (pt)
WINDOW_H=400          # window height (pt)
ICON_SIZE=120         # icon size (pt)
APP_ICON_X=170        # Abendrot.app icon center — LEFT / "cold" side
APP_ICON_Y=210
DROP_LINK_X=490       # /Applications drop link — RIGHT / "warm" side
DROP_LINK_Y=210
# ---------------------------------------------------------------------------

ARGS=(
  --volname "$VOLNAME"
  --window-pos "$WINDOW_X" "$WINDOW_Y"
  --window-size "$WINDOW_W" "$WINDOW_H"
  --icon-size "$ICON_SIZE"
  --icon "$APP_NAME" "$APP_ICON_X" "$APP_ICON_Y"
  --app-drop-link "$DROP_LINK_X" "$DROP_LINK_Y"
  --hide-extension "$APP_NAME"
  --no-internet-enable
)

# Background art is OPTIONAL: include only if the brand art has been delivered.
if [ -f "$BACKGROUND" ]; then
  echo "pretty-dmg: using brand background -> $BACKGROUND"
  ARGS+=( --background "$BACKGROUND" )
else
  echo "pretty-dmg: NOTE — branded background not found at '$BACKGROUND'." >&2
  echo "            Building a functional (un-arted) branded DMG. Geometry is" >&2
  echo "            still applied so the art can be dropped in later unchanged." >&2
fi

# Volume icon is OPTIONAL.
if [ -f "$VOLICON" ]; then
  ARGS+=( --volicon "$VOLICON" )
fi

echo "pretty-dmg: building branded DMG -> $OUT"
# create-dmg signature: create-dmg [options] <out.dmg> <source-folder-or-app>
# We pass the .app directly; create-dmg stages it + the drop link itself.
if ! create-dmg "${ARGS[@]}" "$OUT" "$APP"; then
  echo "pretty-dmg: create-dmg failed (AppleScript timeout? headless session?)." >&2
  echo "            Fallback: scripts/dmg/plain-dmg.sh produces a scripted, headless DMG." >&2
  exit 6
fi

if command -v shasum >/dev/null 2>&1; then
  echo "pretty-dmg: done. sha256: $(shasum -a 256 "$OUT" | awk '{print $1}')"
else
  echo "pretty-dmg: done -> $OUT"
fi
