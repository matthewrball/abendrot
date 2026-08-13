#!/usr/bin/env python3
"""Guard Abendrot's semantic foreground colors against WCAG AA regressions."""

import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "App/Resources/Colors.xcassets"
SURFACES = (
    "GroundIndigo",
    "GroundPlum",
    "GroundTwilight",
    "GroundTwilight2",
    "SolidTop",
    "SolidBottom",
    "FrostTop",
    "FrostBottom",
)
FOREGROUNDS = ("TextPrimary", "TextMuted", "TextFaint", "AccentText")


def component(value: str) -> float:
    return int(value, 16) / 255 if value.startswith("0x") else float(value)


def colorset(name: str) -> dict[str, tuple[float, float, float, float]]:
    path = ASSETS / f"{name}.colorset/Contents.json"
    if not path.exists():
        raise SystemExit(f"Color contrast guard failed:\n- Missing {path.relative_to(ROOT)}")
    data = json.loads(path.read_text())
    variants = {}
    for entry in data["colors"]:
        appearance = entry.get("appearances", [{}])[0].get("value", "default")
        values = entry["color"]["components"]
        variants[appearance] = tuple(component(values[key]) for key in ("red", "green", "blue", "alpha"))
    return variants


def resolve(name: str, appearance: str) -> tuple[float, float, float, float]:
    variants = colorset(name)
    return variants.get(appearance, variants["default"])


def channel(value: float) -> float:
    return value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4


def luminance(rgb: tuple[float, float, float]) -> float:
    red, green, blue = map(channel, rgb)
    return 0.2126 * red + 0.7152 * green + 0.0722 * blue


def contrast(foreground, background) -> float:
    alpha = foreground[3]
    rendered = tuple(foreground[i] * alpha + background[i] * (1 - alpha) for i in range(3))
    high, low = sorted((luminance(rendered), luminance(background[:3])), reverse=True)
    return (high + 0.05) / (low + 0.05)


failures = []
for appearance in ("light", "dark"):
    for foreground in FOREGROUNDS:
        for surface in SURFACES:
            ratio = contrast(resolve(foreground, appearance), resolve(surface, appearance))
            if ratio < 4.5:
                failures.append(f"{appearance} {foreground} on {surface}: {ratio:.2f}:1")

# Fixed ink used on the sunset gradient and the fixed dark tooltip background.
ink_on_accent = (0x16 / 255, 0x0A / 255, 0x12 / 255, 1.0)
for accent in ("AccentHighlight", "AccentBase", "AccentPress", "AccentHi"):
    ratio = contrast(ink_on_accent, resolve(accent, "light"))
    if ratio < 4.5:
        failures.append(f"inkOnAccent on {accent}: {ratio:.2f}:1")
tooltip_ratio = contrast(resolve("TextCream", "light"), ink_on_accent)
if tooltip_ratio < 4.5:
    failures.append(f"TextCream on tooltip background: {tooltip_ratio:.2f}:1")

# Bright accent and adaptive ground colors are fills, not foreground roles.
misuse = re.compile(
    r"foreground(?:Style|Color)\([^\n]*Theme\.Color\."
    r"(?:accent|accentHighlight|accentHi|accentPress|groundIndigo)(?![A-Za-z])"
    r"|foregroundColor\s*=\s*Theme\.Color\.accent(?![A-Za-z])"
)
for source in (ROOT / "App/Sources/Abendrot").rglob("*.swift"):
    for line_number, line in enumerate(source.read_text().splitlines(), 1):
        if misuse.search(line):
            failures.append(f"{source.relative_to(ROOT)}:{line_number}: use a semantic foreground token")

if failures:
    raise SystemExit("Color contrast guard failed:\n- " + "\n- ".join(failures))

print("PASS: semantic text colors meet 4.5:1 in light and dark appearances")
