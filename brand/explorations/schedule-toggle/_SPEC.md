# Schedule Toggle Exploration — Shared Build Spec

We are redesigning ONE control in the macOS app **Abendrot** (a display-warming app; "Abendrot" = the
red glow of sunset). The control is an **either-or selector** in Settings → Schedule that picks between:

- **Sunset** — warms automatically around local sunset (eases in beforehand, holds through the night)
- **Always on** — keeps warmth on around the clock

Today it's a small ember-gradient segmented pill. The founder wants it **bigger, more custom, more
artful** — a control that *showcases* this either-or choice. You are producing fully-realized,
**interactive** HTML/CSS concepts for a side-by-side evaluation gallery. The winner gets ported to
SwiftUI later, so favor ideas that are buildable natively (gradients, shapes, springs) over anything
that needs a real raster image.

This is a faithful in-context mock: every concept renders inside the real Settings → Schedule layout.

---

## NON-NEGOTIABLE CONSTRAINTS

1. **Use ONLY the palette below** (the current "icon" tokens from `brand/tokens.json`). Do NOT invent
   colors. Do NOT use the older purple palette from `components.html` — that's stale.
2. **Self-contained**: one standalone `.html` file. No CDNs, no web fonts, no external images. Inline
   SVG only. System font stack only.
3. **Every concept sits in the identical Settings context** (the panel markup below). Only the control
   itself changes between concepts.
4. **Interactive**: clicking switches the selection with the brand warm ease; show hover, `:focus-visible`,
   and selected states; keyboard operable (Tab + Enter/Space or arrows); respect
   `prefers-reduced-motion: reduce` (drop transforms/animation, keep instant state change).
5. **Accessible**: real focus rings (see CSS), `role`/`aria-pressed` or radio semantics, contrast-safe
   text. Selected text on the bright gradient must be the dark ink `--indigo`, never white/cream
   (cream fails contrast on gold) — this is the app's high-contrast convention.
6. **Include the height-reporter script** (bottom of this file) verbatim so the gallery can auto-size
   your iframe.

---

## PALETTE — paste this `:root` block verbatim into your `<style>`

```css
:root{
  /* Accent ramp (golden sun core → deep ember) */
  --accent:#FD9228; --accent-hl:#FFC061; --accent-deep:#C2310A; --accent-rim:#FFE0B8;
  --accent-press:#E2740F; --ink-on-cream:#9C4310;
  /* Twilight grounds (warm near-blacks — NEVER pure #000) */
  --indigo:#160A12; --plum:#221019; --twilight:#341320; --twilight-2:#45192A;
  /* Text (warm off-white, never #fff) */
  --text:#F3EADF; --muted:rgba(243,234,223,.60); --faint:rgba(243,234,223,.38); --cream:#F7ECD9;
  /* Lines / dividers */
  --line:rgba(255,240,230,.10); --line-strong:rgba(255,240,230,.16);
  /* RESERVED — Reveal-True-Color veil only; do not reuse for chrome */
  --reveal:#FFFFFF;
  /* Sunset gradients */
  --sunset:linear-gradient(180deg,var(--accent-hl) 0%,var(--accent) 52%,var(--accent-press) 100%); /* control fill */
  --sunset-h:linear-gradient(90deg,var(--accent-hl) 0%,var(--accent) 52%,var(--accent-press) 100%);
  --sky:linear-gradient(180deg,#160A12 0%,#2A0F16 34%,#6A100F 60%,#C2310A 80%,#FB7C0E 92%,#FD9228 100%); /* the icon's sky→sun ramp */
  /* Glass + glow (liquid-glass recipe) */
  --glass-tint:linear-gradient(140deg,rgba(255,255,255,.11) 0%,rgba(255,255,255,.035) 46%,rgba(255,255,255,.06) 100%);
  --glass-inset:inset 0 1px 1.5px rgba(255,255,255,.55), inset 0 0 0 .5px rgba(255,255,255,.22);
  --glow-accent:0 0 24px -6px rgba(253,146,40,.9);
  --glow-soft:0 0 36px -10px rgba(253,146,40,.7);
  /* Motion — the brand's signature warm ease */
  --ease-warm:cubic-bezier(.22,.61,.36,1); --ease-standard:cubic-bezier(.4,0,.2,1);
  --dur-fast:.11s; --dur-base:.14s; --dur-reveal:.22s;
  /* Radius */
  --r-card:22px; --r-control:12px; --r-pill:999px;
}
```

### Body background (paste verbatim — matches the real Settings window)

```css
*{box-sizing:border-box} html,body{margin:0;padding:0}
body{
  font-family:-apple-system,"SF Pro Text",BlinkMacSystemFont,system-ui,sans-serif;
  color:var(--text); -webkit-font-smoothing:antialiased; letter-spacing:-.01em;
  background:
    radial-gradient(900px 520px at 80% -14%, rgba(253,146,40,.10), transparent 60%),
    linear-gradient(168deg,#2A1119 0%, var(--plum) 46%, var(--indigo) 100%);
  background-attachment:fixed; min-height:100vh; padding:34px 0 64px;
}
/* warm keyboard focus ring (mirror the shipping app) */
:focus-visible{outline:3px solid var(--accent-hl); outline-offset:3px; border-radius:8px;}
@media (prefers-reduced-motion: reduce){ *{transition:none!important; animation:none!important;} }
```

---

## THE CONTEXT PANEL — wrap EVERY concept in this exact structure

Reproduces the real Settings → Schedule tab (title, subtitle, control, descriptive paragraph) so each
idea is judged in situ. Only swap what's between the `<!-- CONTROL -->` markers.

```html
<section class="concept">
  <div class="ctag">A1 · Sliding ember</div>            <!-- letter = your family, number = variant -->
  <div class="panel">
    <div class="ptitle">Schedule</div>
    <div class="psub">When Abendrot warms your displays.</div>

    <!-- CONTROL ↓↓↓ -->
    <div class="ctl">  ...your custom either-or control...  </div>
    <!-- CONTROL ↑↑↑ -->

    <p class="pdesc">Sunset warms automatically around your local sunset — easing in beforehand and
    holding through the night — using your time zone to estimate sunrise and sunset. No location
    permission required. Always on keeps warmth on around the clock.</p>
  </div>
  <div class="cnote">One-line rationale: what this concept is going for.</div>
</section>
```

### Chrome CSS for the panel (paste verbatim)

```css
.wrap{max-width:920px;margin:0 auto;padding:0 28px;}
.hd{max-width:920px;margin:0 auto 26px;padding:0 28px;}
.hd h1{font-size:22px;font-weight:700;margin:0 0 4px;letter-spacing:-.02em;}
.hd p{margin:0;color:var(--muted);font-size:13px;}
.concept{margin:0 0 30px; padding:22px; border:1px solid var(--line); border-radius:18px;
  background:linear-gradient(180deg, rgba(255,255,255,.018), rgba(0,0,0,.06));}
.ctag{font-size:11px;font-weight:600;letter-spacing:.06em;text-transform:uppercase;color:var(--accent-hl);
  margin-bottom:16px;}
.panel{max-width:520px;}
.ptitle{font-size:19px;font-weight:700;letter-spacing:-.02em;margin-bottom:3px;}
.psub{color:var(--muted);font-size:13px;margin-bottom:18px;}
.pdesc{color:var(--muted);font-size:12.5px;line-height:1.55;margin:16px 0 0;}
.cnote{margin-top:16px;font-size:12px;color:var(--faint);font-style:italic;}
/* page title + per-family heading you add at top of <body> */
.fam{max-width:920px;margin:30px auto 18px;padding:0 28px;}
.fam h2{font-size:15px;font-weight:600;margin:0;color:var(--text);}
.fam p{margin:4px 0 0;color:var(--muted);font-size:12.5px;max-width:70ch;}
```

---

## DESIGN BIAS — Liquid Glass + macOS-native (READ THIS)

The app's real material is **Apple Liquid Glass** (native `.glassEffect` / `NSGlassEffectView`). The
**majority of your concepts should read as Liquid Glass + macOS-native**: translucent frosted/glassy
surfaces over the warm ground, a bright specular top sheen, subtle lensing/refraction, hairline light
rims, soft depth shadows, and native-feeling idioms (segmented control, switch, popover-style chrome).
It should look like it belongs in macOS Tahoe Settings. One or two concepts may push more
expressive/artful, but even those should use the glass materials — not flat paint. Use `backdrop-filter`
for genuine translucency (the gallery sits on the warm ground, so the blur will show through).

### Liquid Glass helpers — paste verbatim, then build on them

```css
/* Clear liquid glass — for tracks, thumbs, unselected chrome */
.glass{
  background:var(--glass-tint);
  -webkit-backdrop-filter:blur(16px) saturate(190%); backdrop-filter:blur(16px) saturate(190%);
  box-shadow:var(--glass-inset), 0 16px 40px rgba(0,0,0,.40);
}
/* Frosted ember — denser material for cards/panels */
.frost{
  background:linear-gradient(150deg,rgba(58,21,33,.80),rgba(36,16,25,.90));
  -webkit-backdrop-filter:blur(30px) saturate(160%); backdrop-filter:blur(30px) saturate(160%);
  box-shadow:var(--glass-inset), 0 16px 40px rgba(0,0,0,.45);
}
/* Specular top sheen — overlay on any glassy/selected fill so it reads as wet glass, not flat.
   Apply via a pseudo-element: position:absolute; inset:0; border-radius:inherit; pointer-events:none; */
.sheen::after{content:"";position:absolute;inset:0;border-radius:inherit;pointer-events:none;
  background:linear-gradient(180deg,rgba(255,255,255,.34) 0%,rgba(255,255,255,.05) 40%,transparent 70%);
  mix-blend-mode:soft-light;}
```

The **selected** state should still wear the warm `--sunset` fill (that's the brand signal), but layer
the specular sheen + a hairline `rgba(255,255,255,.18)` rim + a soft ember `--glow-soft` over it so the
selection looks like lit glass. Unselected/track surfaces use clear `.glass`.

## THE CURRENT BASELINE (what to beat)

A small capsule track (2px gap, 3px pad). Selected segment = `--sunset` vertical fill + a white top
specular sheen (soft-light) + 0.5px white .16 border + ember drop shadow (`--accent-deep` .45, blur 5,
y 1.5); selected text `--indigo` **bold** 12px; unselected text `--muted` medium. Track = `--line` .5
fill + `--line-strong` .5 border. Selection slides between segments on `--ease-warm` ~140ms (a
matched-geometry pill). It's tasteful but small and generic. Go bigger and more expressive.

Thematic hooks you may exploit (Sunset ↔ Always-on is rich): a sun dipping to / sitting on a horizon,
a day→night arc, a warm glow that eases in vs. one that holds steady, dawn/dusk gradients, a clock or
half-clock, a sun that travels along a track. Lean into "Abendrot" = sunset glow.

---

## DELIVERABLE

- Write your file to the exact path given in your task.
- Start `<body>` with a `<div class="fam">` heading (your family name + one-sentence thesis), then your
  concepts in `<div class="wrap">`.
- Produce **4–5 distinct concepts**, ordered restrained → bold. Distinct = genuinely different
  mechanisms/forms, not recolors. Each must actually work (click to switch, animate, keyboard, a11y).
- Make them beautiful and *finished* — this is a real evaluation, not wireframes. Sweat the motion,
  the glow, the spacing, the selected-state delight.
- End with the height-reporter script below, verbatim.

### Height-reporter script (paste verbatim, just before `</body>`)

```html
<script>
  function reportH(){ try{ var b=document.body, kids=b.children, max=0; for(var i=0;i<kids.length;i++){ var el=kids[i]; if(el.tagName==='SCRIPT'||el.tagName==='STYLE') continue; var r=el.getBoundingClientRect(), mb=parseFloat(getComputedStyle(el).marginBottom)||0, bottom=r.bottom+window.scrollY+mb; if(bottom>max) max=bottom; } var pad=parseFloat(getComputedStyle(b).paddingBottom)||0; parent.postMessage({type:'iframeHeight', name:location.pathname.split('/').pop(), h:Math.ceil(max+pad)}, '*'); }catch(e){} }
  addEventListener('load', reportH); addEventListener('resize', reportH);
  if (window.ResizeObserver) new ResizeObserver(reportH).observe(document.body);
  setTimeout(reportH, 400);
</script>
```
