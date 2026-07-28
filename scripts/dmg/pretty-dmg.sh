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
# with a nondeterministic ~29px scroll-offset drift),
# - RETINA-CRISP (dmg-background.png + dmg-background@2x.png are compiled
# into a single HiDPI TIFF automatically).
# plain-dmg.sh remains the zero-dependency fallback. Releases are
# gated on >=1 notarized+stapled DMG when signing is enabled.
#
# Install: pipx install 'dmgbuild==1.6.7' && pipx pin dmgbuild
#
# Usage:
# scripts/dmg/pretty-dmg.sh --check
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
DMGBUILD_VERSION="1.6.7"
CHECK_ONLY="false"

usage() { grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed -n '1,32p'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --check)      CHECK_ONLY="true"; shift ;;
    --app)        APP="${2:-}"; shift 2 ;;
    --out)        OUT="${2:-}"; shift 2 ;;
    --volname)    VOLNAME="${2:-}"; shift 2 ;;
    --background) BACKGROUND="${2:-}"; shift 2 ;;
    --volicon)    VOLICON="${2:-}"; shift 2 ;;
    -h|--help)    usage; exit 0 ;;
    *) echo "pretty-dmg: unknown arg '$1'" >&2; usage >&2; exit 2;;
  esac
done

resolve_dmgbuild() {
  if ! command -v pipx >/dev/null 2>&1; then
    echo "pretty-dmg: 'pipx' not found." >&2
    echo "            Install pipx, then: pipx install 'dmgbuild==$DMGBUILD_VERSION'" >&2
    return 5
  fi
  if [ "$(pipx list dmgbuild --short 2>/dev/null)" != "dmgbuild $DMGBUILD_VERSION" ]; then
    echo "pretty-dmg: requires dmgbuild $DMGBUILD_VERSION via pipx." >&2
    echo "            Run: pipx install --upgrade 'dmgbuild==$DMGBUILD_VERSION'" >&2
    echo "                 pipx pin dmgbuild" >&2
    echo "            Zero-dependency fallback: scripts/dmg/plain-dmg.sh" >&2
    return 5
  fi
  local executable
  executable="$(pipx environment --value PIPX_BIN_DIR)/dmgbuild"
  [ -x "$executable" ] || {
    echo "pretty-dmg: pipx dmgbuild executable not found." >&2
    return 5
  }
  printf '%s\n' "$executable"
}

if [ "$CHECK_ONLY" = "true" ]; then
  resolve_dmgbuild >/dev/null
  exit $?
fi

if [ -z "$APP" ] || [ -z "$OUT" ]; then
  echo "pretty-dmg: --app and --out are required." >&2; usage >&2; exit 2
fi
if [ ! -d "$APP" ]; then
  echo "pretty-dmg: app not found at '$APP'." >&2; exit 3
fi

DMGBUILD="$(resolve_dmgbuild)" || exit $?

# Absolute paths — the settings module resolves them from its own cwd.
APP="$(cd "$(dirname "$APP")" && pwd)/$(basename "$APP")"
APP_NAME="$(basename "$APP")"
VERIFY_APP_SIGNATURE="false"
if command -v codesign >/dev/null 2>&1 \
  && codesign -dv "$APP" >/dev/null 2>&1; then
  codesign --verify --deep --strict "$APP" >/dev/null 2>&1 || {
    echo "pretty-dmg: signed source app has an invalid signature." >&2
    exit 6
  }
  VERIFY_APP_SIGNATURE="true"
fi
OUT_DIR="$(dirname "$OUT")"; mkdir -p "$OUT_DIR"
OUT="$(cd "$OUT_DIR" && pwd)/$(basename "$OUT")"
MOUNT_PATH="/Volumes/$VOLNAME"
if [ -e "$MOUNT_PATH" ] || [ -L "$MOUNT_PATH" ]; then
  echo "pretty-dmg: volume path already exists at '$MOUNT_PATH'." >&2
  echo "            Detach the existing volume before building so Finder records the correct background alias." >&2
  exit 6
fi
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
# Keep the volume's dot-files off the artwork but inside its vertical bounds.
# Finder still exposes them to the right when hidden files are enabled, without
# reserving the empty area below the branded background for everyone else.
HIDDEN_X_LEFT=$(( CONTENT_W + 100 ))
HIDDEN_X_RIGHT=$(( HIDDEN_X_LEFT + 160 ))
HIDDEN_Y_TOP=100
HIDDEN_Y_BOTTOM=280
# ---------------------------------------------------------------------------

SETTINGS="$(mktemp -t pretty-dmg-settings.XXXXXX).py"
MOUNT_POINT=""
cleanup() {
  if [ -n "$MOUNT_POINT" ]; then
    hdiutil detach "$MOUNT_POINT" -quiet >/dev/null 2>&1 || true
    rmdir "$MOUNT_POINT" >/dev/null 2>&1 || true
  fi
  rm -f "$SETTINGS"
}
trap cleanup EXIT

cat > "$SETTINGS" <<EOF
import os, os.path, re

app = os.environ["PDMG_APP"]
app_name = os.path.basename(app)

format = "UDZO"
files = [app]
symlinks = {"Applications": "/Applications"}
# dmgbuild implements hide_extensions by writing com.apple.FinderInfo to the
# app bundle, which invalidates an existing Developer ID signature.
hide_extensions = []

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
    # Dot-files use a compact grid to the right (see the GEOMETRY block).
    # Extra names are harmless — dmgbuild writes the Iloc records whether or
    # not the file exists, which also pins any a future macOS starts showing.
    ".VolumeIcon.icns": ($HIDDEN_X_LEFT, $HIDDEN_Y_TOP),
    ".DS_Store": ($HIDDEN_X_RIGHT, $HIDDEN_Y_TOP),
    ".fseventsd": ($HIDDEN_X_LEFT, $HIDDEN_Y_BOTTOM),
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
        $HIDDEN_X_RIGHT, $HIDDEN_Y_BOTTOM
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

# dmgbuild currently has an upstream path where a failed app copy can still
# leave a valid-looking image. Mount the result and prove the payload exists.
MOUNT_POINT="$(mktemp -d "${TMPDIR:-/tmp}/abendrot-pretty-dmg.XXXXXX")"
hdiutil attach "$OUT" -nobrowse -readonly -quiet -mountpoint "$MOUNT_POINT" \
  || { echo "pretty-dmg: built image could not be mounted." >&2; exit 6; }
if [ ! -d "$MOUNT_POINT/$APP_NAME" ] \
  || [ ! -L "$MOUNT_POINT/Applications" ] \
  || [ "$(readlink "$MOUNT_POINT/Applications")" != "/Applications" ]; then
  echo "pretty-dmg: built image is missing the app or /Applications link." >&2
  exit 6
fi
if [ "$VERIFY_APP_SIGNATURE" = "true" ] \
  && ! codesign --verify --deep --strict "$MOUNT_POINT/$APP_NAME" >/dev/null 2>&1; then
  echo "pretty-dmg: signed app signature was invalidated during DMG creation." >&2
  exit 6
fi
hdiutil detach "$MOUNT_POINT" -quiet \
  || { echo "pretty-dmg: could not detach verification image." >&2; exit 6; }
rmdir "$MOUNT_POINT" >/dev/null 2>&1 || true
MOUNT_POINT=""

if command -v shasum >/dev/null 2>&1; then
  echo "pretty-dmg: done. sha256: $(shasum -a 256 "$OUT" | awk '{print $1}')"
else
  echo "pretty-dmg: done -> $OUT"
fi
