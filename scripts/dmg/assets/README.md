# DMG brand assets

`pretty-dmg.sh` looks for these files. They are **brand assets** that are not
finalized yet. Until they exist, `pretty-dmg.sh` builds a functional but un-arted
DMG, and the Mode-B default `plain-dmg.sh` (no art at all) is used for
credential-less builds.

## Required for the branded "unboxing" DMG

| File | Size | Purpose |
|---|---|---|
| `dmg-background.png` | 660 × 400 px (1×) | Finder window background |
| `dmg-background@2x.png` | 1320 × 800 px (2×) | Retina background |
| `volume.icns` *(optional)* | standard `.icns` | mounted-volume icon |

## Art direction (the demo-by-dragging idea)

The window is **660 × 400 pt**. The geometry in `pretty-dmg.sh` places:

- **Abendrot.app icon** at center **(170, 210)** — the **LEFT / "cold / blue"** side.
- **/Applications drop-link** at center **(490, 210)** — the **RIGHT / "warm"** side.

So the user **drags the app across a cold → warm gradient** to install — the DMG
itself demonstrates the product. Paint the background as a left-cold-blue →
right-warm-amber gradient with a connecting arrow between the two icon centers.
Match the Ember-amber accent (`#FFAB5C`, provisional) on the warm side.

If you change the gradient composition and need different icon coordinates,
update the `GEOMETRY` block in `scripts/dmg/pretty-dmg.sh` to match the new
numbers. Keep 1× and 2× perfectly aligned.

> Reduce-Transparency / a11y note: the warm side should remain an
> ember tint even at full opacity — never neutral grey.
