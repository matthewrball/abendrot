# §18 Overlay "true multiply" — RESOLVED: not achievable permissionlessly

> **Decision, 2026-06-17.** Plan §18 listed a "per-channel multiply shader so blacks stay black"
> as a future overlay improvement. Investigation (cross-checked across Apple DTS, Core Animation
> architecture, private-API dumps, and a survey of every shipping warm/dim app) concludes that a
> **true per-channel multiply via a permissionless public overlay is impossible on macOS 26**.
> True multiply remains the job of the **DDC** and **gamma** layers. The overlay is deliberately an
> **alpha-over warm tint**, tuned to minimise black-lift. This file records why, so the question
> isn't re-litigated.

## Why a multiply overlay can't work

A borderless transparent `NSPanel` is composited over whatever is behind it by the WindowServer
using **source-over alpha only**: `result = dst·(1−a) + tint·a`. That operation can only *lift*
blacks toward the tint (`dst=0 → tint·a`); it can never produce `dst·k` for `k<1` (a multiply /
darkening). The avenues for a real multiply all fail or are out of bounds:

- **`CALayer.compositingFilter` (CIMultiplyBlendMode):** blends a layer only against **sibling
  layers inside the same window's layer tree**. Apple DTS ("Kabe", forums thread 133177): views
  composite to the parent "based on the resulting alpha" — there is no cross-window blend. On a
  standalone overlay panel there is nothing behind-window for it to multiply against, so it is a
  **silent no-op**. Do **not** add it (it misleads maintainers).
- **`CALayer.backgroundFilters` (the one public behind-window CIFilter path):** a **no-op on macOS
  since Big Sur 11.0** (FB9120139, unresolved). Unreliable on 26.
- **`CABackdropLayer.windowServerAware` / `.behindWindow`:** **private** (NSVisualEffectView uses
  it internally); only works when the backdrop *is* the window's own `contentView`, not for
  sampling arbitrary apps behind the panel. App Store rejection risk; doesn't do what we need.
- **Private CGS/SkyLight window blend mode:** **does not exist.** Only `CGSSetWindowAlpha` and
  `CGSAddWindowFilter` exist; neither is a per-channel multiply against content behind the window.
- **Framebuffer capture + Metal multiply shader:** the *only* way to truly multiply arbitrary
  behind-window content — but capturing the framebuffer **requires Screen Recording permission**,
  which breaks Abendrot's core no-permission promise (contract invariant 4). **Rejected.**

Survey: f.lux/Shade, Night Shift, Lunar, Gamma/Dimmer, HazeOver, ScreenDimmer, Shifty, nocturnal —
**none** achieve a true multiply via overlay; every app that keeps blacks black uses **gamma**.

## What the overlay does instead (alpha tint, tuned)

Warming is an alpha-over amber wash (`OverlayBackend`/`OverlayPanel`, click-through panel at
`CGShieldingWindowLevel()`, draw-on-change). Tuning that maximises warmth per unit of black-lift:

- **Saturated, low-luminance amber** tint (`OverlayVeil.tint`, sRGB) rather than a desaturated
  warm-white wash. Since black lifts to `tint·alpha`, a low-luma amber keeps blacks darker for the
  same perceived hue shift. Intensity is carried by **alpha**, not by changing the hue.
- **Gated alpha** (`OverlayVeil.maxAlpha`) so even the warmest setting stays a legible tint, never
  an opaque wash; `veilAlpha(for:)` returns **0 at neutral** (6500K) so the veil fully vanishes
  when warmth is off (regression-tested).
- **The hue and the alpha cap are visual-QA knobs.** The black-lift math is certain; how acceptable
  it looks (and whether saturated-amber reads better than warm-white on real content) can only be
  judged on a real screen — that's the on-screen pass, not a headless decision.

## HDR/EDR

An SDR alpha veil **under-warms EDR content**: an EDR pixel can carry a component value > 1.0, so a
sub-1.0 SDR amber barely dents an HDR highlight while SDR around it warms. Detection:
`NSScreen.maximumExtendedDynamicRangeColorComponentValue` (live) / `…Potential…` (capability) > 1.0.
**M0 handling (chosen): document the gap** — it's the same class of caveat as native-fullscreen
Spaces and DRM surfaces already listed in the `OverlayBackend` header (§21‑E2), and the badge says
`Overlay`, never "hardware". A future option (only if visual QA finds EDR highlights objectionably
cold): host the veil on a `CAMetalLayer` with `wantsExtendedDynamicRangeContent` in
`extendedLinearDisplayP3` so the amber can be drawn > 1.0 and tint EDR highlights — gated on
EDR-active screens, more GPU cost. Gamma/DDC handle EDR correctly by construction (they scale the
signal, not overlay it) — another reason true multiply lives there.

## Where true multiply lives (the real paths)

- **gamma LUT** (`CGSetDisplayTransferByTable`, `DisplayServices.GammaBackend`) — a real per-channel
  multiply on the internal display; classified/default-off on M5 Tahoe where it silently no-ops
  (the reason the overlay must be the floor), kill-switchable.
- **DDC RGB gain** (`HardwareDDC`, M2) — a real per-channel multiply in hardware on external
  displays; opt-in per display, kill-switchable.

`LayerResolver` already encodes this: overlay is the guaranteed floor; gamma/hardware are the
`privateAPIsEnabled`-gated true-multiply paths. No policy change needed.

## Confidence

High on the core verdict (permissionless public overlay cannot true-multiply; alpha-over lifts
blacks; multiply = gamma/DDC) — mathematically certain for the compositing, independently confirmed
by Apple DTS and a full shipping-app survey. The perceptual tuning (amber hue, alpha cap) and the
EDR-objectionability question are **on-screen-verify-only**.
