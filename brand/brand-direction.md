# Abendrot — Brand Direction (working)

> Status: **provisional working direction, chosen 2026-06-16.** The icon and full aesthetic get a dedicated iterate-en-masse refinement exercise before lock — see plan §5.5. Treat tokens below as the starting point, not final.

## Chosen this session
- **Accent hue:** **Ember amber** — candlelight/hearth warmth on the twilight base.
- **Icon concept:** **Sunset arc over horizon** — a half-sun/warm arc rising on a horizon line; reads instantly as a simple arc template at menu-bar size.

## Working tokens
| Token | Value | Use |
|---|---|---|
| `--accent` | `#FFAB5C` | primary ember amber |
| `--accent-2` | `#FFD6A3` | highlight / gradient top |
| `--accent-deep` | `#C2591F` | deep ember / gradient base |
| `--indigo` | `#0C0A16` | deepest twilight ground |
| `--plum` | `#171029` | mid twilight |
| `--twilight` | `#1D1533` | raised surfaces |
| `--cream` | `#F7ECD9` | warm light text/accents |
| `--true-white` | `#FFFFFF` | **reserved** for the Reveal-True-Color moment only |

## Type
- **Wordmark + hero numerals:** New York serif (`ui-serif, "New York", Georgia`).
- **UI chrome:** SF Pro Text (`-apple-system`).
- Optional humanist sans (Figtree-style) for marketing surfaces.

## Material / motion
- Liquid Glass recipe: `backdrop-filter: blur(16px) saturate(190%)` + double inset highlight (`inset 0 1px 1.5px rgba(255,255,255,.65)`, `inset 0 0 0 .5px rgba(255,255,255,.30)`) + soft outer shadow. Native `NSGlassEffectView` / `.glassEffect` in-app.
- Motion = emotional pacing, ~100–150ms eases; one signature interaction (warmth ease / reveal-true-color veil). Audit via `/design-motion-principles`.

## Artifacts
- `explorations/index.html` — live hue + icon exploration (served locally during the session that produced it). Basis for the next round of icon/screen variations.
- Next: refined Sunset-arc icon set (`.icns` ramp + 16/18px menu-bar template, light/dark), finalized tokens, component kit, then mirror to Figma.

## References
- DopeDrop (aesthetic + "tiny, native macOS app" copy formula, proof-by-demonstration), Wispr Flow (calm HUD/named-states/motion, anti-clinical warmth), Liquid Glass.
