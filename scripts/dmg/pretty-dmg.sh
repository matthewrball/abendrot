#!/usr/bin/env bash
#
# pretty-dmg.sh — branded "unboxing" DMG (Abendrot).
#
# Two DMG modes (branded + plain),
# (DMG as unboxing: the window is a miniature of the abendrot.app hero —
# sunset ramp, sun cresting the horizon between the two icons; see
# scripts/dmg/assets/README.md for the full art contract).
#
# ENGINE: dmgbuild (https://github.com/dmgbuild/dmgbuild) — it writes the
# volume's .DS_Store directly instead of driving Finder via AppleScript the
# way create-dmg does. That makes this script:
# - HEADLESS-SAFE (no WindowServer / logged-in session needed — the old
# "UI runner only" constraint is gone),
# - DETERMINISTIC (create-dmg's Finder scripting applied icon positions
# with a nondeterministic ~29px scroll-offset drift, and parked hidden
# files OUTSIDE the window, giving AppleShowAllFiles users a window that
# scrolls right into a white void — both observed 2026-07-27, v1.2.3),
# - RETINA-CRISP (dmg-background.png + dmg-background@2x.png are compiled
# into a single HiDPI TIFF automatically).
# plain-dmg.sh remains the zero-dependency fallback. Releases are
# gated on >=1 notarized+stapled DMG when signing is enabled.
#
# Install: pipx install dmgbuild (or: pip3 install --user dmgbuild)
#
# Usage:
# scripts/dmg/pretty-dmg.sh --app <Abendrot.app> --out <out.dmg> \
# [--volname "Abendrot"] [--background <png>] [--volicon <icns>]
#
# Exit codes: 0 ok; 2 args; 3 missing app; 5 dmgbuild missing; 6 build fail.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSETS_DIR="$SCRIPT_DIR/assets"

APP=""
OUT=""
VOLNAME="Abendrot"
BACKGROUND="$ASSETS_DIR/dmg-background.png"   # brand art (see assets/README.md)
VOLICON="$ASSETS_DIR/volume.icns"             # brand volume icon (optional)

usage() { grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed -n '1,32p'; }

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

DMGBUILD="$(command -v dmgbuild || true)"
# pipx installs outside the default PATH on fresh shells; look there too.
[ -n "$DMGBUILD" ] || [ ! -x "$HOME/.local/bin/dmgbuild" ] || DMGBUILD="$HOME/.local/bin/dmgbuild"
if [ -z "$DMGBUILD" ]; then
  echo "pretty-dmg: 'dmgbuild' not found." >&2
  echo "            Install:  pipx install dmgbuild   (or pip3 install --user dmgbuild)" >&2
  echo "            Zero-dependency fallback: scripts/dmg/plain-dmg.sh" >&2
  exit 5
fi

# Absolute paths — the settings module resolves them from its own cwd.
APP="$(cd "$(dirname "$APP")" && pwd)/$(basename "$APP")"
OUT_DIR="$(dirname "$OUT")"; mkdir -p "$OUT_DIR"
OUT="$(cd "$OUT_DIR" && pwd)/$(basename "$OUT")"
rm -f "$OUT"

# ---------------------------------------------------------------------------
# GEOMETRY — must stay in lockstep with the background art
# (scripts/dmg/assets/README.md).
#
# TWO FINDER RULES THIS BLOCK ENCODES (both measured on macOS 26, 2026-07-27,
# by reading back `bounds of every item` from the mounted window):
#
# 1. WINDOW_H INCLUDES THE TITLE BAR. Finder's window bounds are the frame,
# not the content area, so the usable content is WINDOW_H - TITLEBAR_H.
# The art canvas must equal the CONTENT size or it gets clipped at the
# bottom (the previous 400pt window showed only 368pt of a 400pt image).
#
# 2. FINDER ENFORCES A ~35pt MINIMUM LEFT MARGIN. If the leftmost icon's box
# lands closer than that to the window edge, Finder shifts THE WHOLE
# LAYOUT right to satisfy it — every icon moves, so the art no longer
# lines up. With a .background pinned at x=66 (left edge 6pt) the entire
# row rendered 29pt right of where it was stored. Keep every on-window
# icon's box >= EDGE_MARGIN from the edges: at ICON_SIZE=120, x >= 100.
# VERIFY after changing anything here — see assets/README.md.
TITLEBAR_H=32         # Finder title bar (macOS 26)
CONTENT_W=660         # == background art width
CONTENT_H=400         # == background art height
EDGE_MARGIN=35        # Finder's minimum; icon boxes must clear it
WINDOW_X=200          # window top-left on screen
WINDOW_Y=120
WINDOW_W=$CONTENT_W
WINDOW_H=$(( CONTENT_H + TITLEBAR_H ))
ICON_SIZE=120
TEXT_SIZE=12          # Finder's native label size
APP_ICON_X=170        # Abendrot.app — LEFT glass slot   (box 110..230)
APP_ICON_Y=210
DROP_LINK_X=490       # /Applications drop link — RIGHT glass slot (box 430..550)
DROP_LINK_Y=210
# The volume's dot-files (.background, .VolumeIcon.icns, ...) are parked off
# the right edge so the window stays exactly two icons for everyone. They are
# invisible in a normal Finder; with "show hidden files" on they sit outside
# the window, which makes the view scrollable — a deliberate trade, chosen
# over letting them clutter the artwork. PARKED_X must stay clear of the
# LEFT margin rule above (it does: it is far to the right).
PARKED_X=$(( CONTENT_W + 100 ))
PARKED_Y=100
# ---------------------------------------------------------------------------

SETTINGS="$(mktemp -t pretty-dmg-settings.XXXXXX).py"
trap 'rm -f "$SETTINGS"' EXIT

cat > "$SETTINGS" <<EOF
import os, os.path, re

app = os.environ["PDMG_APP"]
app_name = os.path.basename(app)

format = "UDZO"
files = [app]
symlinks = {"Applications": "/Applications"}
hide_extensions = [app_name]

background = os.environ.get("PDMG_BACKGROUND") or None
icon = os.environ.get("PDMG_VOLICON") or None

window_rect = (($WINDOW_X, $WINDOW_Y), ($WINDOW_W, $WINDOW_H))
default_view = "icon-view"
show_status_bar = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = $ICON_SIZE
text_size = $TEXT_SIZE
scroll_position = (0.0, 0.0)
# Thumbnail the dot-files rather than drawing generic white document icons:
# .background.tiff previews as the artwork itself and .VolumeIcon.icns as the
# app icon, so the system-file row stays on-brand for AppleShowAllFiles users.
show_icon_preview = True

icon_locations = {
    app_name: ($APP_ICON_X, $APP_ICON_Y),
    "Applications": ($DROP_LINK_X, $DROP_LINK_Y),
    # Dot-files parked off the right edge (see the GEOMETRY block). Extra
    # names are harmless — dmgbuild writes the Iloc records whether or not
    # the file exists, which also pins any that a future macOS starts showing.
    ".VolumeIcon.icns": ($PARKED_X, $PARKED_Y),
    ".DS_Store": ($PARKED_X, $PARKED_Y + 140),
    ".fseventsd": ($PARKED_X, $PARKED_Y + 280),
}

# dmgbuild stages the art as ".background<ext>" — .tiff when a @2x sibling
# exists (it compiles a HiDPI TIFF), else the original extension.
if background:
    _name, _ext = os.path.splitext(os.path.basename(background))
    _dir = os.path.dirname(background) or "."
    _has2x = any(
        re.match(rf"^{re.escape(_name)}@\d+x{re.escape(_ext)}$", f)
        for f in os.listdir(_dir)
    )
    icon_locations[".background" + (".tiff" if _has2x else _ext)] = (
        $PARKED_X, $PARKED_Y + 420
    )
EOF

if [ -f "$BACKGROUND" ]; then
  echo "pretty-dmg: using brand background -> $BACKGROUND"
else
  echo "pretty-dmg: NOTE — background not found at '$BACKGROUND'." >&2
  echo "            Building a functional (un-arted) branded DMG." >&2
  BACKGROUND=""
fi
[ -f "$VOLICON" ] || VOLICON=""

echo "pretty-dmg: building branded DMG -> $OUT"
if ! PDMG_APP="$APP" PDMG_BACKGROUND="$BACKGROUND" PDMG_VOLICON="$VOLICON" \
     "$DMGBUILD" -s "$SETTINGS" "$VOLNAME" "$OUT"; then
  echo "pretty-dmg: dmgbuild failed." >&2
  echo "            Fallback: scripts/dmg/plain-dmg.sh produces a plain DMG." >&2
  exit 6
fi

if command -v shasum >/dev/null 2>&1; then
  echo "pretty-dmg: done. sha256: $(shasum -a 256 "$OUT" | awk '{print $1}')"
else
  echo "pretty-dmg: done -> $OUT"
fi
