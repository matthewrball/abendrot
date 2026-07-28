#!/usr/bin/env python3
"""Pad the Abendrot icon for dmgbuild's fixed-size native disk badge."""

from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "assets" / "abendrot-icon.png"
OUTPUT = ROOT / "scripts" / "dmg" / "assets" / "volume-badge.png"
SIZE = 1024
BADGE_SIZE = 640


icon = Image.open(SOURCE).convert("RGBA").resize(
    (BADGE_SIZE, BADGE_SIZE),
    Image.Resampling.LANCZOS,
)
canvas = Image.new("RGBA", (SIZE, SIZE))
offset = (SIZE - BADGE_SIZE) // 2
canvas.alpha_composite(icon, (offset, offset + 136))
canvas.save(OUTPUT, dpi=(72, 72))
print(OUTPUT)
