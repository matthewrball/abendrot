# DMG brand assets

`pretty-dmg.sh` looks for these files.

| File | Size | Purpose |
|---|---|---|
| `dmg-background.png` | 660 × 400 px (1×) | Finder window background |
| `dmg-background@2x.png` | 1320 × 800 px (2×) | Retina background |
| `volume.icns` | standard `.icns` | mounted-volume icon |

**Do not edit the PNGs.** They are generated:

```bash
scripts/dmg/render-background.sh --contrast
```

from `scripts/dmg/assets/dmg-background.html`, which is the source of truth. The
script inlines the app icon into the wordmark, renders with headless Chrome at
2×, and Lanczos-downscales the 1×. `dmgbuild` compiles the pair into a single
HiDPI TIFF when the DMG is built.

## Art direction (matches abendrot.app + the app icon)

A miniature of the site hero: the vertical sunset ramp from
`landing/src/styles/tokens.css` (`--sunset-sky`, #160A12 → #FD9228), a golden
sun cresting a glowing horizon at y=332 between the two icons, water with
ripples below, the app icon + serif wordmark up top, film grain throughout.
Each icon lands on a liquid-glass squircle "slot".

## The three Finder rules this layout encodes

All measured on macOS 26 (2026-07-27) by reading back `bounds of every item`
from the mounted window — that reports where Finder **actually rendered** each
icon, which is not necessarily where the `.DS_Store` says it is. **Re-verify
that way after changing any geometry**, e.g.:

```bash
osascript -e 'tell application "Finder" to get bounds of item 1 of window "Abendrot"'
```

1. **The window bounds include the title bar.** Finder's window is 32pt taller
   than its content area, so the art canvas must equal the *content* size.
   A 400pt-tall window showed only 368pt of a 400pt image — the bottom was
   silently cropped.

2. **Finder enforces a ~35pt minimum left margin.** If the leftmost icon's box
   is closer than that to the edge, Finder shifts *the entire layout* right to
   satisfy it, so every icon drifts off the artwork. A `.background` pinned at
   x=66 (left edge 6pt) pushed the whole row 29pt right. Keep on-window icons
   at x ≥ 100 with the 120pt icon size.

3. **Icon labels are ALWAYS black — Dark Mode does not apply.** A Finder
   window with a custom background image draws its labels in the
   light-appearance colour regardless of the viewer's system appearance. On a
   Dark-mode Mac, a plain folder window drew white labels while this DMG drew
   black ones; the labels stayed black over both a dark and a bright band, so
   it is not luminance-adaptive either. There is no way to force white, so the
   band behind the labels must be **bright**. That is what `.label-glow` does;
   `render-background.sh --contrast` samples the full label rectangles
   (currently ~6.4:1, WCAG AA).

   This is the single most counter-intuitive thing here: a dark, moody DMG
   background will give users unreadable black-on-dark labels, and testing in
   Dark Mode will not reveal it.

## Hidden dot-files

`.background.tiff` and `.VolumeIcon.icns` are parked **outside** the window
(`PARKED_X` in `pretty-dmg.sh`) so the window is exactly two icons for
everyone. With "show hidden files" enabled they sit off-canvas, which makes
the window horizontally scrollable — a deliberate trade, chosen over letting
them clutter the artwork. Pinning them *inside* the window is what tripped
rule 2 above, so if you ever move them back in, mind the margin.

> Reduce-Transparency / a11y note: the artwork is a fixed image, so it
> is unaffected by transparency settings; it stays an ember tint, never grey.
