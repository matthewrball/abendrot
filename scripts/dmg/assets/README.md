# DMG brand assets

`pretty-dmg.sh` looks for these files. They are **brand-owned**.
Until they exist, `pretty-dmg.sh` builds a functional but un-arted DMG, and the
credential-less default `plain-dmg.sh` (no art at all) is used for credential-less builds.

## Required for the branded "unboxing" DMG

| File | Size | Purpose |
|---|---|---|
| `dmg-background.png` | 660 × 400 px (1×) | Finder window background |
| `dmg-background@2x.png` | 1320 × 800 px (2×) | Retina background |
| `volume.icns` *(optional)* | standard `.icns` | mounted-volume icon |

## Art direction (matches abendrot.app + the app icon)

The window is **660 × 400 pt**. The geometry in `pretty-dmg.sh` places:

- **Abendrot.app icon** at center **(170, 210)** — LEFT glass slot.
- **/Applications drop-link** at center **(490, 210)** — RIGHT glass slot.

The background is a miniature of the site hero / app icon: the vertical sunset
ramp from `landing/src/styles/tokens.css` (`--sunset-sky`, #160A12 → #FD9228),
a golden sun cresting a glowing horizon at y=332 between the two slots, water
reflection with ripples below, serif wordmark + "drag to install" eyebrow up
top, film grain throughout. A soft warm glow sits behind each Finder label
position (y ≈ 278–296) so labels stay legible in BOTH modes — Finder draws
them black in light mode, white in dark mode (~3.7:1 / ~5.6:1 there).

**Source of truth:** `outputs/dmg/dmg-background.html` — rendered with
headless Chrome at `--window-size=660,400 --force-device-scale-factor=2`,
then Lanczos-downscaled for the 1×. Render commands are in the HTML header
comment. Edit the HTML, re-render both PNGs; never edit the PNGs directly.

If you change the composition and need different icon coordinates, update the
`GEOMETRY` block in `scripts/dmg/pretty-dmg.sh` (or tell the team the new
numbers). Keep 1× and 2× perfectly aligned.

> Reduce-Transparency / a11y note: the warm side should remain an
> ember tint even at full opacity — never neutral grey.
