# Show HN

> Claims must comply with `docs/marketing/evidence-base.md` guardrails (couple warmth with "lower brightness"; red = circadian-sparing, never therapy; no sleep-outcome promises).

Tuesday–Thursday, ~9 am–12 pm ET. Direct repo + `.dmg`, no signup gate. **Lead with the reliability/engineering/designer hook — NOT health.** The HN crowd is cynical about "circadian wellness"; health stays the brand story but is not the lede here (§21.5).

> Voice: precise, technical, honest, no overstatement, no exclamation marks. Don't oversell the science. Be present for hard questions.

---

## Title

`Show HN: Abendrot – f.lux silently stopped warming my M5, so I built an open-source fix`

**Alternates:**
- `Show HN: Abendrot – open-source Mac screen warmth that works on every display`
- `Show HN: Abendrot – why screen-warming apps fail on new Macs, and a fix (MIT)`

<!-- [FLAG] HN titles: no clickbait, no trailing punctuation games; the mods/community punish hype.
     Keep it factual. The "M5" specificity reads as a real engineering story, which HN rewards. -->

---

## URL

Submit the **GitHub repo** (`github.com/matthewrball/abendrot`) — HN prefers source over a marketing page. Link `abendrot.app` and the direct `.dmg` from the top comment.

---

## Author top comment (post immediately after submitting)

> Author here. Abendrot is a free, MIT-licensed macOS menu-bar app that warms your screen color temperature in the evening. I built it because the existing tools broke for me in two specific, fixable ways.
>
> **1. The gamma path silently no-ops on the newest Apple Silicon.** f.lux, Iris, and most night-mode apps warm the screen by writing a gamma LUT via `CGSetDisplayTransferByTable`. On recent M-series Macs under Tahoe, that call _succeeds_ — returns no error — but produces no visible change. So the app looks like it's working and isn't. (Apple feedback filed.)
>
> **2. Night Shift and gamma-based apps are unreliable on external monitors** — they do nothing, or tint pink, often because macOS mis-identifies the panel.
>
> Abendrot uses a layered engine, best-available-wins per display:
> - **DDC** (`IOAVServiceWriteI2C`, VCP RGB-gain) for real hardware color temperature where the panel supports it;
> - **gamma** where it actually works (capability-classified per device/OS, never assumed);
> - a **universal per-screen Metal overlay** (a click-through `CAMetalLayer` multiply veil at shielding-window level) as the guaranteed fallback that works everywhere — buttonless Apple displays, the newest Macs, all of it.
>
> The key UX decision: it **shows you which method each display is using** (`Hardware` / `Gamma` / `Overlay`) instead of silently failing. The overlay has honest limits (native fullscreen Spaces, protected video, screenshots) and the UI says so; DDC ships opt-in per display until its restore tooling is fully proven.
>
> There's also a hold-to-**Reveal True Color** hotkey — hold it and accurate color returns across every display for color-critical work, release and warmth eases back. Built on `KeyboardShortcuts` so it needs no Accessibility permission.
>
> **What it doesn't do (yet) — so nobody's surprised:**
> - **Protected (HDCP) content stays untouched.** The overlay can't sit over DRM-protected video paths — Netflix/Apple TV+ and similar render outside what a click-through overlay can cover. On DDC/hardware displays the panel itself is still warmed; on overlay-only displays, protected windows show true color until you exit them.
> - **Native fullscreen and system layers escape the overlay.** A true-fullscreen Space, and system UI like Mission Control, the login window, and the lock screen, render above the shielding-window level the overlay uses — so those moments read cool. The UI is explicit that overlay coverage is "almost everything, not literally everything," rather than pretending otherwise. (DDC/hardware-warmed displays don't have this gap, since the warmth lives in the panel.)
> - **DDC hardware warmth is opt-in per display in 1.0.** Best-available-wins picks the overlay by default; you turn on real DDC RGB-gain per monitor once you've seen it behave, because its restore tooling is still being proven. Not every panel exposes usable DDC, and a few misreport — hence opt-in, write-then-read verify, and an emergency "Restore Displays" command.
> - **No automatic screenshot/screen-recording suspend in 1.0.** The overlay tints captures of an overlay-warmed display, and 1.0 won't auto-detect-and-lift for a screenshot. Use Reveal True Color (or DDC, where the capture is clean) when you need an accurate grab. Auto-suspend-on-capture is on the list, not in 1.0.
>
> Stack: native Swift 6 (SwiftUI + AppKit), macOS 26, Metal. The engine is a separate `WarmthKit` Swift package with headless tests. No telemetry by default (opt-in analytics are anonymous and the code is right there). No account, no paywall, free forever.
>
> Repo: github.com/matthewrball/abendrot · Download: abendrot.app
>
> I know "another blue-light app" raises eyebrows — so to be clear on the health angle: I treat it as general wellness, not medicine. I link the circadian research rather than claiming Abendrot improves anyone's sleep, and I'm happy to argue the nuance (the effect is mostly about melanopic _dose_, i.e. dimming as well as warming, and individual sensitivity varies enormously). Happy to go deep on the engine, the private-API risk, or the science. Feedback very welcome — especially if it misbehaves on your display.

<!-- [FLAG] If launching an UNSIGNED beta, add one sentence on first-launch Gatekeeper bypass and DO NOT
     claim "signed and notarized." For the 1.0 build (intended signed+notarized state), you may state it.
     [FLAG] Founder must be available to answer for the first few hours — HN threads live/die on author presence. -->

---

## Anticipated questions (prep answers)

- **"How is this different from Lunar / MonitorControl / BetterDisplay?"** Those are dense brightness/display utilities where warmth is buried and never health-framed, and they're not all free+OSS. Abendrot is warmth-first, transparent about method per display, and MIT.
- **"Private APIs — will this break / get you in trouble?"** Resolved via `dlopen`/`dlsym` with null checks + OS-version gating; a kill-switch falls back to overlay-only. Notarization doesn't scan for private APIs (MonitorControl/Lunar/BetterDisplay ship the same way). Outside the Mac App Store by design.
- **"Isn't the blue-light thing debunked?"** Partly — the _eye-damage_ claim is overblown (AAO agrees), and warming without dimming does little. The circadian melatonin effect is real but dose-dependent and varies per person. That's exactly why I cite rather than assert.
- **"Telemetry?"** Off by default, opt-in, anonymous, ≤8 categorical events, code is open. See PRIVACY.md.
- **"DDC safety?"** Opt-in per display, write-then-read verify, native-state snapshot, and an emergency "Restore Displays" command; launch-time recovery rather than relying on crash handlers.
