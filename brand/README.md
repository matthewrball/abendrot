# Abendrot — Brand & Design System (Lane C)

> **Status: PROVISIONAL.** This is the iterate-en-masse refinement round (plan §5.5, §21.3, §21.4). It produces **variations + a recommendation** for founder selection. **Nothing here is locked.** Once the founder picks, we refine the winner, build the full `.icns` ramp, mirror into Figma (§5.4), and Lanes B (app) + D (landing) inherit the finalized tokens.

Open the HTML files in a browser — they are self-contained (inline SVG/CSS, no build step). Recommended viewing order: `explorations/index.html` (the original starting artifact) → `explorations/icons-round-1.html` → `explorations/menubar-template.html` → `explorations/components.html`.

---

## Artifact index

| File | What it is | Founder decision it informs |
|---|---|---|
| `tokens.css` | **Source of truth** — Ember tokens with explicit **dark + light** variants, glass/frost params, reserved true-white, motion. CSS custom properties + reusable `.glass`/`.frost` classes. | Consumed by Lane B + Lane D. Founder confirms the accent ramp. |
| `tokens.json` | Same tokens as structured data (for Swift/asset-catalog generation + Figma variables). | — |
| `explorations/icons-round-1.html` | **3-3-1 icon strategy** (§21.4): 3 pure-glyph · 3 glass-pebble-squircle · 3 abstract-orb takes on the Sunset-arc direction, each at **512 / 128 / 32px** on the dark glossy squircle, ending with a recommended convergence. | **Pick the icon family + variant.** |
| `explorations/menubar-template.html` | The **18px "vibrant template"** menu-bar icon: active (amber glow) vs inactive, on light + dark bars, and over 4 warm/busy wallpapers proving it survives desktop-tinting. Includes the SVG template master + AppKit notes. | Confirm the active-glow treatment + safety stroke. |
| `explorations/components.html` | **Liquid Glass component kit** (real recipe): simple popover, advanced "liquid expansion," frosted-ember Settings, "3 clicks to warmth" onboarding, ember-tinted SOLID Reduce-Transparency fallback, reveal-veil, + specular-tracking / variable-thickness-blur notes. | Confirm material hierarchy + component direction. |
| `explorations/index.html` | The **original** starting artifact (hue + icon toggler). **Preserved, not overwritten.** | Reference / baseline. |
| `brand-direction.md` | The working direction chosen 2026-06-16 (provisional). | Reference. |

---

## Provisional recommendation (founder confirms or overrides)

1. **Accent:** keep **Ember amber `#FFAB5C`** (highlight `#FFD6A3`, deep `#C2591F`). It reads as candlelight/hearth on the twilight base and survives both light and dark surfaces. Validated across all mockups. *Recommend: keep.*
2. **Icon family:** converge on **B3 — the glossy arc with reflections** (glass-pebble family). It keeps the poetry of the half-sun + water-reflections (the most "Abendrot" mark) while gaining Tahoe-native glass depth, and it **degrades cleanly** to the A1 half-sun + horizon glyph at menu-bar size — so the app icon and the menu-bar template are one coherent mark. *Fallback if the founder wants more abstract/ownable:* **C2 (setting orb)**, which collapses to the same arc glyph, so the menu-bar template is unaffected either way. **Honest note:** the 32px tiles in `icons-round-1.html` are *deliberately drawn from the shared A1 glyph template* (one template, redrawn per size), not auto-downscaled from the 512px art — so "degrades cleanly/perfectly" describes that **design decision**, not a measured result. It's only proven once the chosen master is built into the full `.icns` ramp and checked on-device.
3. **Menu-bar template:** half-sun + horizon, monochrome NSImage template, **amber glow + fill when active**, with a **0.5pt dark safety stroke + dual outer glow** so it never disappears on warm wallpapers.
4. **Material hierarchy:** transient clear glass for the popover (`blur 16 / sat 190`); more-opaque **frosted ember** for Settings (`blur 30 / sat 160`); **solid ember** (never grey) for Reduce-Transparency.
5. **White discipline:** pure `#FFFFFF` appears **only** in the Reveal-True-Color veil. Body text is `#ECE8F4`; control chrome that would normally be white — the toggle and slider knobs — uses off-white **`--cream #F7ECD9`** instead (and the wordmark gradient tops out at warm `--accent-hi`), so nothing but the reveal veil is pure white. Enforced consistently across `tokens.css`, `components.html`, and these notes.

---

## Decisions left explicitly to the founder

- [ ] **Icon family + variant** — A-family (pure glyph, most minimal) vs **B3 (recommended, glass arc + reflections)** vs C-family (abstract orb, most ownable but least literal). The 9 options are in `icons-round-1.html`.
- [ ] **Accent ramp** — keep Ember amber as-is, or nudge (the original `index.html` also has coral and candle-gold toggles if you want to revisit hue).
- [ ] **Reflection lines on the icon** — in or out (they add poetry but slightly more visual complexity at mid sizes).
- [ ] **Active menu-bar treatment** — full amber fill+glow (recommended, glanceable) vs glow-only on a monochrome glyph (more restrained).
- [ ] **Onboarding step order** — current is notifications → max warmth → schedule (§21.3); founder may prefer warmth first.
- [ ] **Optional confirmation tone** on activation (Wispr-style "ping") — ship default-on or default-off.

---

## Build note — generating the `.icns` from the SVG master

The HTML/SVG here are masters; they cannot emit binary `.icns`/PNG. Once the founder picks a family, produce the icon as a **1024×1024 master** (Figma or vector export), then build the iconset:

```bash
# 1. From the chosen 1024 master, render the required sizes (sips or a vector export):
#    Apple wants: 16, 32, 128, 256, 512 — each at @1x and @2x.
mkdir Abendrot.iconset
sips -z 16   16   icon_1024.png --out Abendrot.iconset/icon_16x16.png
sips -z 32   32   icon_1024.png --out Abendrot.iconset/icon_16x16@2x.png
sips -z 32   32   icon_1024.png --out Abendrot.iconset/icon_32x32.png
sips -z 64   64   icon_1024.png --out Abendrot.iconset/icon_32x32@2x.png
sips -z 128  128  icon_1024.png --out Abendrot.iconset/icon_128x128.png
sips -z 256  256  icon_1024.png --out Abendrot.iconset/icon_128x128@2x.png
sips -z 256  256  icon_1024.png --out Abendrot.iconset/icon_256x256.png
sips -z 512  512  icon_1024.png --out Abendrot.iconset/icon_256x256@2x.png
sips -z 512  512  icon_1024.png --out Abendrot.iconset/icon_512x512.png
cp                icon_1024.png      Abendrot.iconset/icon_512x512@2x.png

# 2. Pack the iconset into a .icns:
iconutil -c icns Abendrot.iconset   # -> Abendrot.icns
```

**Important for small sizes:** render the 16/32px variants from the **simplified glyph** (the A1 half-sun + horizon), *not* a down-scaled glossy 512 — fine detail (reflections, sheen) muddies at menu-bar size. Maintain two SVG masters: the **glossy app-icon** master and the **flat menu-bar template** master (see `menubar-template.html` §03 for the template SVG). The menu-bar image ships separately as an 18px template PDF/PNG with `isTemplate = true`, not inside the `.icns`.

---

## Constraints honored (so reviewers can verify)

- Warmth-default twilight palette; **never pure `#000`** (grounds are warm-tinted near-blacks).
- **White reserved** for the reveal moment only.
- Liquid Glass uses the real recipe; **specular-tracking + variable-thickness-blur** approximated in `components.html` and noted for the app.
- **Reduce-Transparency = solid ember** (never grey); **Reduce-Motion** suppresses specular + springs (tokens drop durations to ~1ms).
- ~100–150ms eases; calm/premium/non-clinical (Wispr Flow + DopeDrop references).
- No "Generated with Claude Code" / AI attribution anywhere in these files.
