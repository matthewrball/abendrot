#!/usr/bin/env python3
"""Regenerate Abendrot's macOS app icon set from one master PNG.

Usage:
    python3 scripts/icon/build-icons.py [master.png]

Default master: assets/abendrot.png  (1024x1024 RGBA, transparent corners).

Pipeline / steps (documented so the icon can be swapped later):
  1. Load the master (square; auto-resized to 1024 if needed).
  2. Write assets/AppIcon.iconset/  with the 10 Apple-named size variants.
  3. iconutil -c icns -> assets/abendrot.icns  (for the DMG volume icon, etc.).
  4. Write App/Resources/Colors.xcassets/AppIcon.appiconset/  (PNGs + Contents.json)
     — this is what the app bundle uses (Xcode applies the Tahoe squircle mask).
Re-run after replacing assets/abendrot.png to refresh every size + the .icns.
The corners of the master are already transparent (see scripts/icon/README.md).
"""
import os
import sys
import json
import subprocess
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
master_path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "assets", "abendrot.png")

im = Image.open(master_path).convert("RGBA")
if im.size != (1024, 1024):
    im = im.resize((1024, 1024), Image.LANCZOS)


def sized(px):
    return im if px == 1024 else im.resize((px, px), Image.LANCZOS)


# 1 + 2) .iconset for iconutil
iconset = os.path.join(ROOT, "assets", "AppIcon.iconset")
os.makedirs(iconset, exist_ok=True)
iconset_files = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for name, px in iconset_files:
    sized(px).save(os.path.join(iconset, name + ".png"))

# 3) .icns
icns = os.path.join(ROOT, "assets", "abendrot.icns")
subprocess.run(["iconutil", "-c", "icns", "-o", icns, iconset], check=True)

# 4) AppIcon.appiconset (one PNG per unique pixel size, referenced by Contents.json)
appicon = os.path.join(ROOT, "App", "Resources", "Colors.xcassets", "AppIcon.appiconset")
os.makedirs(appicon, exist_ok=True)
for px in (16, 32, 64, 128, 256, 512, 1024):
    sized(px).save(os.path.join(appicon, f"icon_{px}.png"))
entries = [
    ("16x16", "1x", 16), ("16x16", "2x", 32),
    ("32x32", "1x", 32), ("32x32", "2x", 64),
    ("128x128", "1x", 128), ("128x128", "2x", 256),
    ("256x256", "1x", 256), ("256x256", "2x", 512),
    ("512x512", "1x", 512), ("512x512", "2x", 1024),
]
contents = {
    "images": [{"idiom": "mac", "size": s, "scale": sc, "filename": f"icon_{px}.png"} for s, sc, px in entries],
    "info": {"author": "xcode", "version": 1},
}
with open(os.path.join(appicon, "Contents.json"), "w") as f:
    json.dump(contents, f, indent=2)

print("OK")
print("  iconset:    ", iconset)
print("  icns:       ", icns)
print("  appiconset: ", appicon)
