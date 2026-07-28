#!/usr/bin/env bash
#
# render-background.sh — build the DMG background PNGs from the HTML source.
#
# scripts/dmg/assets/dmg-background.html (source of truth, hand-edited)
# -> scripts/dmg/assets/dmg-background.png (1x, 660x400)
# -> scripts/dmg/assets/dmg-background@2x.png (2x, 1320x800)
#
# It renders with headless Chrome at devicePixelRatio 2, then Lanczos-
# downscales for the 1x (rendering 1x separately would re-hint the text and
# the two scales would no longer align). dmgbuild compiles the pair into a
# single HiDPI TIFF at DMG-build time.
#
# Two substitutions happen before rendering:
# APP_ICON_DATA_URI the wordmark's app icon, inlined as base64 so the HTML
# renders identically from any cwd
# LABEL_A1/LABEL_A2 the label-glow alphas (see LABEL BAND below)
#
# LABEL BAND: a Finder window with a custom background image ALWAYS draws its
# icon labels in the light-appearance colour — black — no matter the viewer's
# system appearance. Verified 2026-07-27 on a Dark-mode Mac: a plain folder
# window drew white labels while this DMG drew black ones, and the labels
# stayed black over both a dark and a bright band, so it is not luminance-
# adaptive. So the band behind them must be BRIGHT; there is no white-text
# case to trade against. .label-glow is that warm lift, tuned by sweeping
# these alphas and measuring contrast across the text rows. Re-run --contrast
# after moving the icon row or changing the sky.
#
# Usage: scripts/dmg/render-background.sh [--contrast]
# --contrast also report worst-case label contrast (vs black text)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
SRC="$REPO/scripts/dmg/assets/dmg-background.html"
ICON="$REPO/assets/abendrot-icon.png"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

# Solved label-glow alphas — see LABEL BAND above. Overridable from the env
# so the tuning sweep can drive this script instead of duplicating it.
LABEL_A1="${LABEL_A1:-.60}"
LABEL_A2="${LABEL_A2:-.312}"

WIDTH=660
HEIGHT=400

CONTRAST=0
[ "${1:-}" = "--contrast" ] && CONTRAST=1

[ -f "$SRC" ]  || { echo "render-background: missing $SRC" >&2; exit 3; }
[ -f "$ICON" ] || { echo "render-background: missing $ICON" >&2; exit 3; }
[ -x "$CHROME" ] || { echo "render-background: Google Chrome not found at $CHROME" >&2; exit 5; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

python3 - "$SRC" "$ICON" "$TMP/page.html" "$LABEL_A1" "$LABEL_A2" <<'PY'
import base64, sys
src, icon, out, a1, a2 = sys.argv[1:6]
html = open(src).read()
uri = "data:image/png;base64," + base64.b64encode(open(icon, "rb").read()).decode()
html = (html.replace("APP_ICON_DATA_URI", uri)
            .replace("LABEL_A1", a1).replace("LABEL_A2", a2))
for token in ("APP_ICON_DATA_URI", "LABEL_A1", "LABEL_A2"):
    assert token not in html, f"unsubstituted {token}"
open(out, "w").write(html)
PY

"$CHROME" --headless=new --screenshot="$TMP/bg@2x.png" \
  --window-size="$WIDTH,$HEIGHT" --force-device-scale-factor=2 \
  --hide-scrollbars --disable-gpu "file://$TMP/page.html" >/dev/null 2>&1

python3 - "$TMP/bg@2x.png" "$REPO" "$WIDTH" "$HEIGHT" "$CONTRAST" <<'PY'
import sys
from PIL import Image
shot, repo, w, h, contrast = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), sys.argv[5] == "1"
src = Image.open(shot).convert("RGB")
assert src.size == (w * 2, h * 2), f"unexpected render size {src.size}"

src.save(f"{repo}/scripts/dmg/assets/dmg-background@2x.png", optimize=True)
one = src.resize((w, h), Image.LANCZOS)
one.save(f"{repo}/scripts/dmg/assets/dmg-background.png", optimize=True)
print(f"render-background: wrote {w}x{h} + @2x")

if contrast:
    def lum(c):
        def lin(v):
            v /= 255
            return v / 12.92 if v <= .04045 else ((v + .055) / 1.055) ** 2.4
        return .2126 * lin(c[0]) + .7152 * lin(c[1]) + .0722 * lin(c[2])
    # Sample conservative rectangles covering both Finder labels, not only
    # their center pixels. Finder draws them BLACK over a custom background.
    label_rects = ((250, 430, 560, 596), (900, 1080, 560, 596))
    worst = min((lum(src.getpixel((x, y))) + .05) / .05
                for x1, x2, y1, y2 in label_rects
                for x in range(x1, x2, 2) for y in range(y1, y2, 2))
    verdict = "AAA" if worst >= 7 else "AA" if worst >= 4.5 else "BELOW AA"
    print(f"render-background: label contrast vs black text: {worst:.2f}:1 ({verdict})")
PY
