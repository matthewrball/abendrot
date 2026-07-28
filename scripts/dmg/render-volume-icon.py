#!/usr/bin/env python3
"""Render Abendrot's disk-shaped DMG volume icon."""

from pathlib import Path
import subprocess
import tempfile

from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "scripts" / "dmg" / "assets"
APP_ICON = ROOT / "assets" / "abendrot-icon.png"
MASTER = ASSETS / "volume.png"
ICNS = ASSETS / "volume.icns"
SCALE = 2
SIZE = 1024


def scaled_box(box):
    return tuple(value * SCALE for value in box)


def vertical_gradient(size, top, bottom):
    image = Image.new("RGBA", size)
    pixels = image.load()
    for y in range(size[1]):
        amount = y / max(size[1] - 1, 1)
        color = tuple(
            round(start + (end - start) * amount)
            for start, end in zip(top, bottom)
        )
        for x in range(size[0]):
            pixels[x, y] = color
    return image


def rounded_mask(size, box, radius):
    mask = Image.new("L", size)
    ImageDraw.Draw(mask).rounded_rectangle(
        scaled_box(box),
        radius=radius * SCALE,
        fill=255,
    )
    return mask


def render_master():
    canvas_size = (SIZE * SCALE, SIZE * SCALE)
    canvas = Image.new("RGBA", canvas_size)

    shadow = rounded_mask(canvas_size, (260, 204, 764, 816), 78)
    shadow = shadow.filter(ImageFilter.GaussianBlur(30 * SCALE))
    shadow_layer = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
    shadow_layer.putalpha(shadow.point(lambda alpha: round(alpha * 0.32)))
    canvas.alpha_composite(shadow_layer, (0, 20 * SCALE))

    body_box = (260, 184, 764, 796)
    body_mask = rounded_mask(canvas_size, body_box, 82)
    body = vertical_gradient(
        canvas_size,
        (252, 252, 253, 255),
        (174, 177, 184, 255),
    )
    body.putalpha(body_mask)
    canvas.alpha_composite(body)

    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle(
        scaled_box(body_box),
        radius=82 * SCALE,
        outline=(255, 255, 255, 230),
        width=6 * SCALE,
    )
    draw.rounded_rectangle(
        scaled_box((270, 194, 754, 786)),
        radius=68 * SCALE,
        outline=(92, 96, 104, 105),
        width=2 * SCALE,
    )

    badge_size = 132
    badge_left = (SIZE - badge_size) // 2
    badge_top = 404
    badge = Image.open(APP_ICON).convert("RGBA").resize(
        (badge_size * SCALE, badge_size * SCALE),
        Image.Resampling.LANCZOS,
    )
    badge_shadow = Image.new("L", canvas_size)
    ImageDraw.Draw(badge_shadow).rounded_rectangle(
        scaled_box(
            (
                badge_left,
                badge_top,
                badge_left + badge_size,
                badge_top + badge_size,
            )
        ),
        radius=30 * SCALE,
        fill=130,
    )
    badge_shadow = badge_shadow.filter(ImageFilter.GaussianBlur(7 * SCALE))
    badge_shadow_layer = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
    badge_shadow_layer.putalpha(badge_shadow)
    canvas.alpha_composite(badge_shadow_layer, (0, 5 * SCALE))
    canvas.alpha_composite(
        badge,
        (badge_left * SCALE, badge_top * SCALE),
    )

    return canvas.resize((SIZE, SIZE), Image.Resampling.LANCZOS)


def build_icns(master):
    names = (
        ("icon_16x16", 16),
        ("icon_16x16@2x", 32),
        ("icon_32x32", 32),
        ("icon_32x32@2x", 64),
        ("icon_128x128", 128),
        ("icon_128x128@2x", 256),
        ("icon_256x256", 256),
        ("icon_256x256@2x", 512),
        ("icon_512x512", 512),
        ("icon_512x512@2x", 1024),
    )
    with tempfile.TemporaryDirectory(prefix="abendrot-volume-icon.") as temp:
        iconset = Path(temp) / "Volume.iconset"
        iconset.mkdir()
        for name, size in names:
            master.resize((size, size), Image.Resampling.LANCZOS).save(
                iconset / f"{name}.png"
            )
        subprocess.run(
            ["iconutil", "-c", "icns", "-o", str(ICNS), str(iconset)],
            check=True,
        )


def main():
    master = render_master()
    master.save(MASTER)
    build_icns(master)
    print(MASTER)
    print(ICNS)


if __name__ == "__main__":
    main()
