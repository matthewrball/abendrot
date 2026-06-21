# Abendrot — Brand Direction (working)

> Status: **provisional working direction, chosen 2026-06-16.** The icon and full aesthetic get a dedicated iterate-en-masse refinement exercise before lock — see plan §5.5. Treat tokens below as the starting point, not final.
>
> **Update 2026-06-21:** the **menu-bar status-item glyph is now LOCKED** (see “Menu-bar glyph” below). The rest of the aesthetic remains provisional.

## Chosen this session
- **Accent hue:** **Ember amber** — candlelight/hearth warmth on the twilight base.
- **Icon concept:** **Sunset arc over horizon** — a half-sun/warm arc rising on a horizon line; reads instantly as a simple arc template at menu-bar size. (Menu-bar glyph now locked — see below.)

## Menu-bar glyph — LOCKED (2026-06-21)
**"Old sun, lights up + ripple."** Chosen from the menu-bar icon lab rounds (`brand/explorations/menubar-*-lab.html`). Resting and warming share the **same shape and width** so the icon never jumps:
- **Resting / inactive** — a filled half-sun cresting a full-width horizon line. Monochrome **NSImage template** (`isTemplate = true`) so macOS tints it for light/dark bars.
- **Warming / active** — the identical sun + horizon, now **ember-amber `#FD9228`** with a soft glow, plus **one reflection ripple** line below the horizon (the app icon's sun-on-water reflection, reduced to a single ripple). Non-template so the amber + glow survive the bar's auto-tinting.
- Swaps on `AppModel.isWarmingActive` (`enabled && schedule warm now && !revealing`).
- **Geometry** (24-unit grid, AppKit y-up): horizon `y=9.6` (0.40·h), sun radius `7.2` (0.30·w), line weight `1.92` (0.08·w), ripple at `y=5.5` spanning `x 8.5→15.5`.
- **Implemented in** `App/Sources/Abendrot/Views/SunsetArcGlyph.swift` (`MenuBarGlyph.template()` / `.active()`).

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
- ✅ Menu-bar glyph locked (see above) — `MenuBarGlyph` template + active states shipped.
- Next: full `.icns` app-icon ramp, finalized tokens, component kit, then mirror to Figma.

## References
- DopeDrop (aesthetic + "tiny, native macOS app" copy formula, proof-by-demonstration), Wispr Flow (calm HUD/named-states/motion, anti-clinical warmth), Liquid Glass.
