# Abendrot landing page (Lane D)

Standalone static site for **abendrot.app**. Built **locally, for PREVIEW only**.

> ⚠️ **Do NOT deploy.** Live deploy to a production domain is the founder's gate.
> This builds to static and runs a local preview. A `vercel.json` is included so a
> preview deploy *could* be wired up later, but nothing here pushes live.

## Stack

Vanilla HTML / CSS / JS, bundled and previewed with **Vite** (no runtime framework).
This matches the team's idiom — the brand artifacts in `/brand/explorations` are all
hand-authored HTML/CSS. Output is a fully static `dist/`.

## Run it

```sh
cd landing
npm install
npm run dev        # local dev server (hot reload) → http://localhost:4317
```

Build + preview the production bundle:

```sh
npm run build      # → dist/  (static, minified)
npm run preview    # serves dist/ → http://localhost:4317
```

## What's real vs. placeholder

| Area | Status |
|---|---|
| Marketing copy (hero, science, trust) | **Real** — adapted from `docs/marketing/README-draft.md` + `science-snippets.md`. No invented claims. |
| Science citations + links | **Real** — every link points at the primary source in `science-snippets.md`. |
| "Audit the engine" Swift snippet | **Real** — drawn from the frozen `docs/engine/warmthkit-api-contract.md` (`WarmthEngine`, `DisplayMethod`). |
| Brand tokens (color, glass, type, motion) | **Provisional** — mirror of `/brand/tokens.css`. Re-sync on brand-lock (§5.5). |
| Sunset-arc icon / favicon / OG image | **Provisional mock** — inline SVG matching the working icon concept. Swap for the locked icon from Lane C. |
| Interactive cool↔warm demo | **Crafted mock** — CSS/JS simulation, not a real capture. Real product screenshots/video slot in from Lane B. |
| Per-display badges (Hardware/Gamma/Overlay) | **Real semantics** — exactly how the shipping app reports each display. |
| Metrics: `< 5 MB`, `~20 MB RAM`, `~0% idle CPU` | **Placeholder** — clearly labeled "to confirm". Not measured. Replace from a release build before publishing. |
| Download CTA | **Pre-release** — framed "Coming soon" → GitHub. No fake live download link. |

## Needs before this can go live

1. **Brand-lock (Lane C):** final accent ramp, locked Sunset-arc icon set, finalized type scale → re-sync `src/styles/tokens.css` from `brand/tokens.css` and replace `public/favicon.svg` + `public/og-image.*`.
2. **Real screenshots / demo video (Lane B):** replace the crafted demo mock and the placeholder note in `#demo`.
3. **Measured metrics:** replace the three "to confirm" figures in `#proof` with real release-build numbers, then remove the `.tbd` labels.
4. **Real release:** swap the "Coming soon" CTA for the live `.dmg` download + version, and confirm OG/Twitter cards render (the `og-image.png` is generated, 1280×640).
5. **Founder gate:** only then wire the Vercel deploy.

## Accessibility / performance notes

- Respects `prefers-reduced-motion` (disables scroll-warming animation curve transitions, scroll reveals, bob/rise keyframes) and `prefers-reduced-transparency` (ember-tinted SOLID glass fallback, never neutral grey).
- Single `<h1>`; semantic landmarks; skip link; the interactive demo is a keyboard-operable `role="slider"`; Reveal-True-Color button has hold semantics on pointer + Space/Enter.
- Mobile-first; lazy/idle work via `requestAnimationFrame`; one small Google Fonts request (Figtree) with system fallback; no tracking, no analytics, no cookies.

## Regenerating the OG / icon PNGs

The PNGs are rasterized from the SVGs with macOS `sips`:

```sh
cd landing/public
sips -s format png og-image.svg --out og-image.png
sips -s format png favicon.svg --resampleHeightWidth 180 180 --out apple-touch-icon.png
```
