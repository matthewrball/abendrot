---
name: abendrot
title: "Abendrot — Master Plan (build → release → growth)"
status: APPROVED for execution (2026-06-16) — staged-beta strategy confirmed
owner: matthewrball (matthewball.me)
created: 2026-06-16
positioning: circadian-health-first (reliability as proof)
license: MIT
stack: native Swift (SwiftUI + AppKit), macOS 26 "Tahoe", Xcode 26
repo: github.com/matthewrball/abendrot
domain_primary: abendrot.app (purchased 2026-06-16)
landing_secondary: matthewball.me/abendrot (301-redirect → abendrot.app)
home_dir: /Users/ball/Documents/abendrot (canonical working dir going forward)
research_artifacts:
  - main sweep: docs/research/research-sweep-main.json (competitive, ux, naming, tech, analytics, marketing, science + synthesis)
  - stack sweep: docs/research/research-sweep-stack-exemplars.json (build-stack decision + exemplar app teardowns incl. Wispr Flow)
  - ccg naming: docs/research/naming-{codex,gemini}.md
  - clearance: agent report (Ruhe/Schimmer/Abendrot name clearance)
  - references studied: github.com/fayazara/macos-app-skills, dopedrop.app, wisprflow.ai
---

# Abendrot — Master Plan

**Abendrot** (German: *the red glow of sunset*) is a free, open-source, native macOS menu-bar app that warms your screen's color temperature across **every** display — built-in *and* external — to support your circadian rhythm in the evening, with an instant **Reveal True Color** hotkey for designers and a beautiful Liquid Glass interface. It is the first app to treat reliable warmth on every display as a solved engineering problem rather than a buried side-feature, and the only one that is simultaneously free, auditable, and built for the newest Apple Silicon Macs where the incumbents silently break.

This document is the full plan: opportunity → product → brand → architecture → build → QA → release → landing page → analytics → community → go-to-market → execution orchestration. It is marked **pending approval**; on approval we hand off to an OMC team + `/goal` execution (see §15).

---

## 1. Vision & North Star

- **One-line:** *"Your Mac's screen warms with the evening — on every display — so your nights stay calm and your mornings stay sharp."*
- **North-star feeling:** calm vitality, not clinical urgency. The app should feel like dusk: warm, quiet, premium, trustworthy. (Borrowed from the Wispr Flow rebrand and DopeDrop's confident minimalism.)
- **The promise we can uniquely keep:** real warmth that *actually works* on the LG UltraFine, Studio Display, Pro Display XDR, and M5 Macs — where f.lux/Night Shift/Iris fail — delivered by an app you can read every line of.
- **What we are NOT:** not a medical device, not a brightness Swiss-army knife, not a Night Shift wrapper, not a telemetry vacuum.

---

## 2. The Opportunity — Benefit & Differentiation (the core of this plan)

### 2.1 What's broken in the market (2026, evidence-based)
- **f.lux is stale and now breaks on new hardware.** Dated non-native UI; built on the single global gamma API (`CGSetDisplayTransferByTable`) which is **silently ignored on M5 Pro/Max under macOS Tahoe 26.3.1+/26.4** — gamma writes "succeed" but produce no visual warmth. Every gamma-based app (f.lux, Iris, Gamma Control, the gamma paths in Lunar/MonitorControl) is quietly failing on the newest Macs.
- **Apple Night Shift is unreliable on externals** — frequently does nothing or tints pink (often because macOS mis-identifies the monitor as a "TV"), no per-display control, no designer escape hatch.
- **The tools that DO warm externals reliably** (BetterDisplay, Lunar, MonitorControl) are dense brightness/display utilities where warmth is buried and never health-framed; they're also closed or source-available, not truly free+OSS.
- **Iris owns the "health" framing but discredited it** through bloat and aggressive/confusing monetization.
- **Trust vacuum:** NightOwl's 2023 hidden-botnet incident (cert revoked) primed the category for a transparent, auditable, open-source alternative.

### 2.2 Our differentiation (beyond "it's free")
1. **DDC-first layered warmth engine, best-available-wins per display, fully transparent.** Try real hardware color temp via DDC → fall back to gamma → fall back to a universal Metal overlay, and **tell the user exactly which method each display is using** instead of silently no-op'ing. This is the moat: warmth that works on *every* display including buttonless Apple panels and M5 Tahoe.
2. **"Reveal True Color" hotkey** — hold to momentarily restore accurate color across **all** displays for color-critical work; release to ease warmth back (a "lift the veil" motion). No incumbent does this well across externals. Designer/photographer hero feature.
3. **Credible, non-salesy circadian-health narrative** — own the health angle Iris squandered, but evidence-honest (we cite peer-reviewed sources *and* the nuance, never overclaim).
4. **Genuine open-source trust** — MIT, signed + notarized, zero telemetry by default, "read every line." The anti-NightOwl.
5. **"Works on the newest Macs"** — we detect the M5 Tahoe gamma breakage and route around it. Tagline-worthy: *the warmth app that still works on your new Mac.*
6. **Tiny, native, beautiful** — a Mac-assed Mac app (DopeDrop's "A tiny, native macOS app…" boast, made *more* credible because we're open source and can publish real numbers).

### 2.3 Positioning statement (LOCKED: circadian-health-first)
> For Mac users and designers who want their screens to wind down with the evening — on the built-in display and every external monitor — **Abendrot** is a free, open-source circadian warmth app that applies real, reliable warmth across all displays and reveals true color instantly when you need it, unlike f.lux and Night Shift, which are closed, dated, and quietly fail on external monitors and the newest Apple Silicon.

Reliability-on-every-display is the *proof*; circadian health is the *story*.

---

## 3. Locked Decisions

| Decision | Choice | Notes |
|---|---|---|
| **Name** | **Abendrot** | Cleared GO: empty namespace, best thematic fit, ownable/rankable. German "sunset glow." |
| **Positioning** | Circadian-health-first | Reliability is the proof point |
| **License** | **MIT** | Matches MonitorControl precedent; license is marketing here |
| **Stack** | Native Swift (SwiftUI + AppKit) | Only stack that reaches gamma/DDC/Metal/CBBlueLightClient *and* gets Liquid Glass free |
| **Deployment target** | macOS 26.0 "Tahoe" | Commit to Tahoe; revisit a lower floor only if demand appears |
| **Distribution** | Developer ID, notarized, **outside MAS** | Private APIs (IOAVService, CBBlueLightClient) preclude the App Store |
| **Domain** | **abendrot.app** (primary, purchased) | matthewball.me/abendrot 301-redirects to it; `.app` TLD forces HTTPS (HSTS preload) |
| **Repo** | github.com/matthewrball/abendrot | Public, MIT (create at execution kickoff) |
| **Build scope** | Full-featured 1.0 in one push | All 3 layers + advanced + settings + analytics at launch |
| **In-app analytics** | Aptabase, opt-in, OFF by default | Open-source/self-hostable; downloads via GitHub/Homebrew |
| **Reveal hotkey** | Ship both; default hold | Toggle option in Settings |
| **Launch** | Soft pre-launch → PH + Show HN day | Then awesome-* PRs + newsletters → sustained |
| **Pricing** | Free forever, optional Sponsors | Never a paywall |
| **Accent (working)** | Ember amber `#FFAB5C` (highlight `#FFD6A3` / deep `#C2591F`) | Chosen 2026-06-16; exact hue/tokens finalized in the brand-refinement exercise (§5.5) |
| **Icon (working)** | Sunset arc over horizon | Chosen concept; icon + full aesthetic iterated en masse before lock (§5.5) |

Pre-decided product shape (confirmed from the brief): menu-bar app **with hide/remove-from-menu-bar option**; **hold-to-reveal-true-color** hotkey; **advanced mode** behind a right-click / modifier; schedule can **follow system Night Shift** or run manually; **Liquid Glass** aesthetic; **science as a tasteful easter egg**; **free + open source**.

---

## 4. Product Definition

### 4.1 Core model (simple by default)
Modeled on Lungo / Wispr Flow: **one click → done.** The default surface is a small Liquid Glass popover:
- Big **on/off** + a warmth **strength** control (a warm-tinted slider, labeled in plain language "Softer ⟷ Warmer," with the Kelvin value available but not dominant).
- A **mode** segmented control: **Follow sunset** (system Night Shift schedule) · **Schedule** (custom) · **Always on** · **Off**.
- A glanceable **per-display status** line (Wispr-Flow "named states"): each connected display shows its name + the method in use as a tiny badge — `Hardware` (DDC) / `Gamma` / `Overlay` — so we never silently no-op (this transparency is a differentiator, not a debug detail).
- Footer: gear (Settings), and a subtle "Reveal True Color: ⌥⌘T (hold)" hint.

### 4.2 Reveal True Color (signature feature)
- **Hold** the global hotkey → all warmth suspends (true color) across every display; **release** → warmth eases back over ~100–150ms (Emil-Kowalski-style ease-out, "lift the veil"). Default behavior.
- Configurable to **toggle** instead of hold (Settings → Shortcuts).
- **Watchdog**: auto-resume after N seconds if a key-up is lost (e.g., Space switch eats the event), so warmth never gets stuck off.
- Optional **auto-suspend during screenshot/screen-recording** (so captures show true color) — Settings toggle.

### 4.3 Menu-bar presence & the hide option
- **LSUIElement** agent app: no Dock icon, no Cmd-Tab. Template menu-bar glyph (a small sunset-arc) that reads on Tahoe's translucent bar.
- **Hide/Remove from menu bar** (explicitly requested): Settings offers "Show in menu bar" (on/off). When off, the app keeps running and is reachable via (a) the global hotkey to open the popover, and (b) re-launching the app, which re-opens Settings. We surface a clear re-entry instruction so users never feel they've lost it. (Pattern reference: Ice/Bartender hide-from-bar UX.)

### 4.4 Simple vs Advanced
- **Default (left-click):** the simple popover above.
- **Advanced (right-click or ⌥-click the menu-bar icon):** reveals power rows — per-display independent warmth curves, per-app/website exclusions, fine Kelvin + sunset/sleep ramp control, the layer override (force Overlay/DDC/Gamma per display), screenshot-exempt toggle.
- **Settings window** (Liquid Glass, programmatic `NSWindowController` so the glass chrome actually renders): tabs **General / Schedule / Displays / Shortcuts / Advanced / Privacy / About**. Settings double as onboarding + trust-builder (CleanShot X pattern: plain-language explanations, status-aware hints, molly-guards, graceful permission walkthroughs).

### 4.5 Scheduling
- **Follow sunset (default):** mirror the system Night Shift schedule by *reading* `CBBlueLightClient` and following its `active` boolean — we never write to Night Shift, so the user's real setting is untouched. Degrade gracefully to a built-in solar scheduler (CLLocation + solar calc) if the private API fails.
- **Schedule:** custom from/to times + warmth target.
- **Always on / Off.**

### 4.6 Onboarding
- ~90-second first run (Wispr Flow pattern): pick a warmth default + schedule mode and **see it apply live**; graceful permission explainer only for what we truly need (we need *no* Accessibility permission thanks to `KeyboardShortcuts`). Skippable, re-invokable.

### 4.7 The science easter egg
- A tasteful, hedged "The Science" panel (Settings → About, plus an optional gentle nudge): short, cited snippets (e.g., *"Your eyes have a third light sensor (ipRGCs ~480nm) that tells your brain it's day or night."*) each linking to a primary source. Strictly **general-wellness, non-medical** framing (see §13). Easter-egg flavor: a couple of snippets surface playfully, not preachy.

---

## 5. Brand & Design System

### 5.1 Identity
- **Name/wordmark:** Abendrot. High-contrast serif (New York) for the wordmark + hero Kelvin readout; **SF Pro Text** for all UI chrome (literary warmth over clinical sans). Optional humanist sans (Figtree-style) for marketing surfaces.
- **Icon = the logo** (invest here): **working concept = Sunset arc over horizon** — a half-sun/warm arc rising on a horizon line, gradient from accent to deep indigo on a glossy dark squircle, with a lit-gloss treatment; a simple arc template for the menu bar. To be refined en masse (§5.5).
- **Palette:** a twilight system where *warmth is the default state* — deep indigo / dusk plum grounding a dark, glassy UI, warming through ember amber to soft candle cream. **Working accent (chosen): Ember amber** — `#FFAB5C` (highlight `#FFD6A3`, deep `#C2591F`) on a warm-tinted near-black (never pure `#000` — a cold black would fight a warmth product). **Pure white is reserved exclusively for the "Reveal True Color" moment**, so accuracy reads as a deliberate event. Exact tokens + dark/light variants finalized in §5.5.
- **Voice:** poetic but precise, never alarmist; "soften into the evening." Invites rather than warns. Scrupulously non-medical, evidence-honest. No exclamation marks, no growth-hack CTAs.

### 5.2 Motion & material (audited via /design-motion-principles)
- **Liquid Glass** done with the real recipe (from DopeDrop teardown, verified against macOS 26 SDK): `backdrop-filter: blur(16px) saturate(190%)` + double inset highlight (`inset 0 1px 1.5px rgba(255,255,255,0.65)`, `inset 0 0 0 0.5px rgba(255,255,255,0.30)`) + soft outer shadow + `border-radius: 999px` for web; native `NSGlassEffectView` / SwiftUI `.glassEffect` in-app.
- **Motion = emotional pacing, not spectacle** (Wispr Flow): slow fades, soft corners, ~100–150ms eases. One signature interaction done perfectly (the warmth ease / reveal-true-color veil). Optimistic UI — state changes apply instantly, **no spinners** (Linear). Respect Reduce Motion / Reduce Transparency.
- **Sound (optional, off-friendly):** a soft confirmation tone on activation, à la Wispr Flow's "ping."

### 5.3 Design references (to model)
- **DopeDrop** — aesthetic + "tiny, native macOS app" copy formula + proof-by-demonstration (they hid "12 MB" in the demo).
- **Wispr Flow** — calm non-modal HUD with named states; anti-clinical warm palette; humanist type; personalizing onboarding. (Avoid its cloud/screenshot trust posture — we are local-first.)
- **Exemplars to borrow specific patterns from:** Lungo (one-click core action), CleanShot X (settings-as-onboarding, molly-guards, permission walkthroughs), Notion Calendar/Dato (glanceable menu-bar value), Things 3 (one signature delight, physical motion), Ice/Bartender (tiered simple/advanced, hide-from-bar), Linear (perceived speed as brand).

### 5.4 Deliverables (design system)
Brand guide (logo, icon set incl. `.icns`, palette tokens, type scale, motion specs), Figma library, app UI kit, landing-page kit, OG/social cards, GitHub social-preview, DMG background art, Product Hunt gallery assets.

### 5.5 Brand Refinement — dedicated exercise (iterate to perfect)
The visual identity is a first-class, **separate, iterate-en-masse workstream**, not a one-shot. The chosen working direction — **Ember amber accent + Sunset arc icon**, twilight palette, New York serif wordmark — is the *starting point*; the icon and full aesthetic get refined until the brand is perfect **before** it's locked into the app, landing page, and assets.
- **Starting artifact:** `brand/explorations/index.html` — live Liquid-Glass exploration of hues + icon concepts (served locally; the basis for the next iterations).
- **Scope:** refine the Sunset-arc icon (proportions, ray/horizon treatment, gloss, depth, full `.icns` size ramp incl. the 16/18px menu-bar template + light/dark); settle exact palette tokens + dark/light variants; finalize type scale + wordmark lockup; motion specs (warmth ease, reveal-true-color veil) audited via `/design-motion-principles`; component kit (popover, advanced menu, Settings, badges, onboarding, landing hero).
- **Method:** generate many parallel variations of the icon + key screens, review side-by-side, designer-led selection; then mirror the locked system into Figma (§5.4). Runs as **Lane C** in execution (§15) as its own dedicated pass.
- **Gate:** brand is "done" only when the icon + core screens read beautifully at every size and the founder signs off; the build inherits the finished system. Until then, treat current picks as provisional.

---

## 6. Technical Architecture

### 6.1 Shape
- **App target `Abendrot.app`** (LSUIElement, no Dock icon): SwiftUI `MenuBarExtra` UI + `Settings` scene + Liquid Glass surfaces + onboarding; orchestrates the engine. **No privileged helper/daemon** — DDC, gamma, overlay, CBBlueLightClient, and the hotkey all run in the user session. Login-launch via `SMAppService.mainApp.register()`.
- **Local SPM package `WarmthKit`** (the testable engine):
  - `WarmthEngine` — actor; per-display state machine keyed by **stable identity** (`CGDisplayCreateUUIDFromDisplayID`, *not* the reassigned displayID); `setWarmth(cct/strength)`; best-available-layer selection per display.
  - `MetalOverlayBackend` — per-`NSScreen` borderless click-through `NSWindow` at screen-saver level hosting a `CAMetalLayer` per-channel-multiply warm shader. **The reliable universal fallback** (works on LG UltraFine / Studio Display / Pro Display XDR / M5 Tahoe). Draw-on-change only → ~0% idle GPU.
  - `DDCBackend` — `IOAVService` write path (VCP 0x16/0x18/0x1A gain) + IORegistry `AppleCLCD2`/`DCPAVServiceProxy` ↔ `CGDirectDisplayID` matching via `CoreDisplay_DisplayCreateInfoDictionary`. Capability-probe (read 0x16) before writing; fire-and-verify with retry.
  - `GammaBackend` — `CGSetDisplayTransferByTable` wrapper, gated behind a **per-device/OS capability classification** — **not** a default runtime screen-capture probe (post-compositor pixel measurement needs Screen Recording permission and would break our no-permission promise; see §21‑E1). Default-off on M5 Tahoe; **overlay is always the safe default**. Optional lab/advanced verification only. Reset via `CGDisplayRestoreColorSyncSettings`.
  - `NightShiftBridge` — `CBBlueLightClient` (`getBlueLightStatus:` + `setStatusNotificationBlock:`) read-only schedule follow.
  - `CInterop` — C/Obj-C module map declaring private `IOAVService*`, `CBBlueLightClient`, `CoreDisplay_DisplayCreateInfoDictionary`. Resolve private symbols via `dlopen`/`dlsym` with null checks + version gating.
  - `HotkeyService` — wraps `sindresorhus/KeyboardShortcuts` (Carbon `RegisterEventHotKey`; no Accessibility permission; supports keyDown **and** keyUp → exact fit for hold-to-reveal).
- **Safety:** on launch and on quit/crash, reset all displays to neutral before re-applying; re-baseline on hotplug/wake via `CGDisplayRegisterReconfigurationCallback` / `didChangeScreenParametersNotification`; store last-known native DDC gain to restore exactly.

### 6.2 The layered warmth engine (best-available-wins, per display)
| Layer | Mechanism | Apple Silicon | Externals | Role |
|---|---|---|---|---|
| **1 — DDC RGB-gain** | `IOAVServiceWriteI2C` VCP gain | works (basis of MonitorControl/Lunar) | **best** real warmth on DDC-capable panels; FAILS on buttonless Apple displays | true hardware warmth where available |
| **2 — Gamma LUT** | `CGSetDisplayTransferByTable` | **broken on M5 Tahoe** (silent no-op) | flaky pre-breakage, dead on M5 | best-effort, behind measured self-test only |
| **3 — Metal overlay** | per-screen `CAMetalLayer` multiply veil | full | **universal** (every display type) | **DEFAULT on M5 Tahoe**; guaranteed fallback |
| (1.5 — ColorSync, candidate) | `ColorSyncDeviceSetCustomProfiles` | may bypass broken gamma pipeline | TBD | evaluate at runtime; future |

Engine probes each display, picks the best working layer, and **reports it in the UI**. Self-test demotes silently-broken layers automatically.

### 6.3 Build-stack rationale (why native Swift, no contest)
Electron/Tauri/RN-macOS/Flutter/Catalyst all force you to write the entire low-level engine in native Swift/Obj-C++ *anyway* (to reach gamma/DDC/Metal/private frameworks) — so you pay a second-runtime + FFI tax for negative benefit, and you lose first-class Liquid Glass. Catalyst additionally can't host `NSStatusItem` and gets `kIOReturnNotPermitted` on privileged IOKit. **Decision: native Swift 6.x (strict concurrency) + SwiftUI/AppKit, Xcode 26, macOS 26 SDK.**

### 6.4 Key libraries
`sindresorhus/KeyboardShortcuts` (global hold hotkey), `Sparkle` 2.x (auto-update, EdDSA), `apple/swift-log` (+OSLog), `swift-format`/`SwiftLint` (CI). DDC approach vendored from the MonitorControl/BetterDisplay technique (mind MPL attribution — reimplement patterns, credit carefully). No DDC dependency exists; vendor it.

### 6.5 De-risking learnings adopted (from fayazara/macos-app-skills — reimplement, don't copy; README-only "MIT", no LICENSE file)
- Overlay `NSPanel` recipe: `[.borderless, .nonactivatingPanel]`, `isOpaque=false`, clear bg, `ignoresMouseEvents=true`, `collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]`, level `CGShieldingWindowLevel()`.
- Sparkle timing: init `SPUStandardUpdaterController(startingUpdater:false)` early, `start()` in `applicationDidFinishLaunching`; use `ObservableObject`+Combine KVO bridge (not `@Observable`); `#if DEBUG` guards; flip `.regular` + activate before showing the update window (menu-bar-only fix).
- Programmatic `NSWindowController` + `.fullSizeContentView` + `.scrollContentBackground(.hidden)` to actually get Liquid Glass chrome (SwiftUI `Window` scene can't).
- Reference-counted activation-policy helper (`enter()`/`leave()`) shared by Settings + Sparkle windows.
- Fork its **Go release CLI** (cleanest reusable asset; Go = license-cleaner to vendor) for DMG+sign+appcast+`gh release`.
- **Gaps it does NOT cover (first-class work for us):** CLI notarization (`notarytool`/`stapler`), GitHub Actions CI, Homebrew cask, DDC/private-API entitlements.

---

## 7. Build Plan & Milestones

Founder intent: **ship a fully-featured 1.0 in one coordinated push** (not a thin MVP), *but* internally sequenced so each milestone is dogfoodable and testable. Tradeoff accepted: slower to first public release, higher polish at launch.

- **M0 — Skeleton & overlay core (the reliable path first).** App target, `MenuBarExtra`, LSUIElement, `WarmthKit` package scaffold, `MetalOverlayBackend` applying warmth to **all** displays keyed by stable identity, crash/quit neutral-reset, hotplug re-baseline. *Exit:* warmth visibly works on built-in + UltraFine + an external via overlay.
- **M1 — Schedule + hotkey + simple UI.** `NightShiftBridge` follow-mode + custom + always-on; `HotkeyService` hold-to-reveal with watchdog; simple Liquid Glass popover with per-display status badges. *Exit:* end-to-end daily-use loop feels good.
- **M2 — DDC + gamma + capability engine.** `DDCBackend` with capability probe + fire-and-verify; `GammaBackend` behind measured self-test + auto-demote; best-available-wins selection; per-display method reporting. *Exit:* hardware warmth on DDC panels; correct fallback everywhere; honest method badges.
- **M3 — Advanced mode + Settings.** Right-click/⌥ advanced menu; tabbed Liquid Glass Settings (programmatic window); per-display curves, per-app exclusions, layer override, screenshot-exempt; hide-from-menu-bar; onboarding; "The Science" panel; login-at-launch.
- **M4 — Polish, a11y, perf, brand.** Motion pass (/design-motion-principles), Reduce Motion/Transparency, VoiceOver, EDR/HDR clamp, idle-GPU verification, final icon/wordmark, sound.
- **M5 — Release engineering.** Signing, notarization, branded DMG, ZIP, Sparkle appcast, Homebrew cask, CI (see §9).
- **M6 — Landing page + assets + launch prep** (see §10, §14).

Parallelizable across lanes (see §15): engine (M0–M2) is the long pole and stays with the strongest agent; UI/brand and landing page proceed in parallel once M1 contracts are stable.

---

## 8. Testing & QA

- **Unit (XCTest against WarmthKit, headless):** Kelvin↔gain math, schedule logic (mode 0/1/2 parsing, sun-follow), state-machine transitions, identity keying, watchdog, neutral-reset.
- **Integration (self-hosted runner with real displays):** DDC capability probe + write/verify on real panels; gamma measured self-test demotion on an M5 Tahoe machine; overlay coverage incl. full-screen Spaces; hotplug/sleep-wake re-baseline; multi-monitor (built-in + UltraFine + a DDC external).
- **Device matrix:** M5 (Tahoe, gamma-broken) + an M3/M4 (gamma works) × {built-in, LG UltraFine, Studio Display if available, a generic DDC monitor, HDMI-on-AS edge case}.
- **Manual/QA-tester (tmux):** onboarding, permission flows, hide-from-menu-bar re-entry, reveal-true-color feel + stuck-suspend recovery, screenshot-exempt, Reduce Motion/Transparency, light/dark.
- **Release gates:** `codesign --verify --deep --strict`, `spctl -a -vvv`, notarization stapled, Sparkle update dry-run from vN-1 → vN, fresh-Mac Gatekeeper first-launch.
- **Acceptance criteria** in §19; verifier pass (separate lane, never self-approve) before any "done."

---

## 9. Release Engineering

- **Signing:** Developer ID Application + **Hardened Runtime**; **no App Sandbox** (would block private-framework `dlopen` + IOAVService). Avoid `disable-library-validation` unless a load failure demands it. Sign nested Sparkle bundles (XPC, Autoupdate/Updater) inside-out with the same identity.
- **Notarization (CLI):** `xcrun notarytool submit --wait` with an App Store Connect API key; `xcrun stapler staple` the `.app` and the `.dmg`. (Notarization does *not* scan for private APIs — proven by MonitorControl/Lunar/BetterDisplay.)
- **ZIP:** `ditto -c -k --keepParent` (preserves signature/xattrs; never `zip`). Staple the `.app` before zipping for offline first-launch.
- **Branded DMG (custom download window — explicit requirement):** `create-dmg` (shell) art-directs the Finder window — background PNG (@2x, brand art + arrow), volume icon, window size/pos, app icon coordinate, **drag-to-Applications drop link**, hidden extension. On-brand with the design system. Gotcha: AppleScript Finder automation needs a logged-in UI agent (headless CI fails it) — run the DMG step on a UI runner or locally; keep the ZIP pipeline fully headless so releases never block. (DropDMG as designer-driven fallback.)
- **Auto-update:** Sparkle 2.x, EdDSA (`generate_keys` → public key in Info.plist `SUPublicEDKey`, private key **in login keychain only, never in repo**), `generate_appcast` signs each archive, appcast hosted on GitHub Pages/Releases over HTTPS; `SPUStandardUpdaterController` + a menu "Check for Updates" + auto-check toggle.
- **Homebrew cask:** `brew install --cask abendrot` (own tap first → submit to homebrew-cask central later). Cask version synced to releases.
- **CI (GitHub Actions, macOS 26 runner):** lint (`swift-format --lint` + SwiftLint) → `xcodebuild test` (WarmthKit headless; DDC/gamma integration gated to self-hosted) → archive + export (Developer ID) → import signing cert from encrypted secret into a temp keychain → notarize → staple → (UI runner) build+sign+staple DMG → sign appcast → `gh release create`. Add a job that builds against each macOS 26.x point release to catch recurring gamma regressions early. Keep secrets out of forked-PR runs.

---

## 10. Landing Page — abendrot.app

- **Structure:** locked-viewport cinematic hero (DopeDrop pattern) on a **warm-tinted near-black that subtly warms as you scroll** (the page embodies the product), then a scrolling body (we have real things to say: how it works, the science, privacy, install).
- **Hero:** outcome headline — *"Your Mac's screen warms with the evening. On every display."* Subhead: *"A tiny, native, open-source app for calmer nights and sharper mornings — free, runs entirely on your Mac."* **One** primary CTA: **Download for macOS** (version + "free forever, no account"). Adjectives-first, like DopeDrop.
- **Live demo:** autoplay-muted loop / interactive cool↔warm slider showing the screen warming + the menu-bar UI + reveal-true-color; the "aha" immediately. Crafted render, not a Loom.
- **Proof-by-demonstration (the "tiny native" boast):** a row of glass badges — `Native Swift` · `Menu-bar only` · `< 5 MB` · `No Electron` · `~20 MB RAM` · `0% idle CPU` · `Apple Silicon`. Bake a real number into the UI mock (DopeDrop's "12 MB" trick). Our unique proof they can't match: **`Open source — read every line`**.
- **Trust/science block:** non-medical "general wellness" line; cited circadian research links; "no tracking, no account, runs locally, open source — audit the code"; MIT badge.
- **Social proof (as earned):** GitHub stars, PH badge, HN points, download count, MacStories/press logos.
- **SEO/AI-visibility:** exact-match `.app` domain (strong brand SEO; `.app` is HSTS-preloaded so always HTTPS); `<title>`/meta targeting "free open source screen warmth / f.lux alternative for Mac"; single H1; clean factual copy LLMs can quote; OG + Twitter `summary_large_image` cards matching the GitHub social-preview. List on **AlternativeTo** as an f.lux/Night Shift alternative (evergreen traffic).
- **Mobile-first** (most discovery is mobile; download happens later on Mac): thumb-reach CTA, "email me the link"/QR.
- **Perf:** lightweight, compressed demo, lazy-load (PH/HN spikes punish slow pages).
- **Build/host:** standalone static site at **abendrot.app on Vercel** (fast, full control of the cinematic Liquid Glass page + instant rollbacks/preview URLs). matthewball.me is WordPress, so it hosts only a 301-redirect page at `/abendrot` → abendrot.app. Custom domain + auto-HTTPS via Vercel; verify OG/social cards + the redirect pre-launch.

---

## 11. Analytics & Telemetry

Two separate channels, both privacy-first:
- **Downloads (no in-app code, no PII):** sum GitHub Releases asset `download_count`; once in homebrew-cask central, also read Homebrew's aggregate analytics JSON. Landing-page **`download_click`** event via a cookieless tool (Plausible or Aptabase web — no GA4 on a health site). Report as trend, not exact installs.
- **In-app usage (opt-in, OFF by default):** **explicit opt-in** is both ethically right for a privacy/health/OSS audience and legally safe (the Audacity opt-out revolt is the cautionary tale; health context → GDPR Article 9). Plain-language first-run panel: *"Help improve Abendrot? Anonymous, aggregate usage stats — no account, no identifiers, no health data. Off by default."* All functionality works fully when declined.
  - **Recommended stack (confirm in §16):** **Aptabase, self-hosted or EU-managed** — fully open-source server + SDK, no identifiers/cookies/fingerprinting, strongest "we run our own analytics, here's the code" story for a health OSS app. Alternative: **TelemetryDeck** (best Swift DX, EU-hosted, 100k/mo free) if we want less ops burden.
  - **Events (≤6–8, categorical, payload-free):** `app_activated`, `warmth_mode_used` (schedule/manual), `advanced_mode_enabled`, `hotkey_used` (count only), `warmth_method_chosen_per_display` (DDC/gamma/overlay), coarse `app_version`+`macOS_major`, anonymous retention cohort. **Never:** health/schedule data, screen content, display serials, precise locale, IP, free-text, or any ID we control.
- **Privacy policy** (plain language): processor + EU hosting (or self-hosted), exact event categories, "anonymous/aggregate," "no health data/cookies/fingerprinting/IP," legal basis, retention, opt-out path, contact. Keep Apple privacy-label / disclosures consistent with actual data flows (EDPB "technical truth gap" risk).

---

## 12. Open-Source Repo & Community

- **README (conversion engine):** one-liner + free/OSS hook in the first 2 lines; social-preview banner; demo GIF of the warming; badges (MIT, latest release, macOS, stars); one-click Download; feature **table**; "Why" + circadian research links; install/usage screenshots; comparison vs Night Shift/f.lux/Redshift; build-from-source; contributing + license.
- **Repo hygiene:** custom Open Graph social-preview (1280×640, app + tagline); up to 20 **topics** (`macos, swift, blue-light, night-shift, f-lux, flux, circadian-rhythm, eye-strain, screen-dimmer, color-temperature, menu-bar, sleep, health, open-source, productivity`); pinned; Discussions on for support; clear `LICENSE` (MIT), `CONTRIBUTING`, `CODE_OF_CONDUCT`, `SECURITY` (EdDSA key handling).
- **awesome-\* PRs:** clean PRs to `jaywcjlove/awesome-mac` and macOS app lists per their CONTRIBUTING (alphabetical, AP title-case, one-sentence, match free/OSS icons, keep locales consistent) — *after* the README is polished and there's traction.
- **Sustainability signal:** active maintenance cadence (the Ice solo-maintainer slowdown is the cautionary tale). Optional GitHub Sponsors / "buy me a coffee" (never paywall).

---

## 13. Health / Science Content (cited, hedged)

- **Regulatory guardrail:** position as **general wellness, NOT a medical device**. FTC still requires substantiation for objective health claims. **Never** say "clinically proven," "treats insomnia," "cures eye strain," or "blue light damages your eyes." **Do** say "supports healthy evening light habits," "reduces blue-light exposure at night," and **link the research** rather than asserting outcomes.
- **Honest core:** it's the **melanopic (blue) content** that matters more than raw brightness (Schoellhorn 2023); warming *without* dimming blunts the benefit, so encourage lowering brightness too; individual sensitivity varies **>50-fold** (Phillips 2019) → offer a default to personalize, never a "safe for everyone" number; warming is "a small, sensible nudge, not a magic sleep button" (Hoehn 2024).
- **Easter-egg snippets** (each cited): the ipRGC "third light sensor (~480nm)" fact; "dim room light at night already suppresses most melatonin" (Zeitzer 2000); "bright by day, dim+warm at night, dark while you sleep" (Brown 2022 consensus: 250/10/1 lux melanopic EDI); "ophthalmologists say screen blue light doesn't damage your eyes — blink and take breaks" (AAO 2024); the 20-20-20 rule.
- **Sources** (primary/major reviews only, date-stamped): J Physiol 2000, PNAS 2015/2019, Commun Biol 2023, PLoS Biology 2022, PLoS ONE 2011, Cochrane 2023, AAO 2024, Brain Comms 2024. (Full list in research artifact `docs/research/research-sweep-main.json` → `science`.)

---

## 14. Go-to-Market & Launch

**Sequencing (not one blast):** soft pre-launch / build-in-public → coordinated **Product Hunt + Show HN** day → awesome-\* PRs + newsletters → sustained.

- **Product Hunt (Tue/Wed/Thu, 12:01am PT):** self-launch (keep maker narrative); prep gallery + 15–30s demo GIF of the warm-shift (strongest asset); **first maker comment within 5 min** (~85% correlation with top-10); notify supporters in 4–5 **staggered timezone waves** (never "please upvote" — ask for honest feedback); reply to every comment within 15 min. Free+OSS = high conversion.
- **Show HN (Tue–Thu, 9am–12pm ET):** title `Show HN: Abendrot – free, open-source screen-warmth/circadian app for macOS`; direct `.dmg`/repo, no signup gate; author top-comment (why, how it differs, stack, license); be present for hard technical + skeptical-of-health-claims questions; don't overstate benefits. FOSS converts ~1.4 stars/upvote.
- **Reddit (verify each sub's live rules; lead with free+OSS; disclose authorship; media in-post; ask feedback not upvotes):** r/macapps (primary, dev-friendly), r/macOS (discussion framing), r/QuantifiedSelf (data/method), r/eyestrain (high-intent), r/sleep (no medical claims), r/opensource/r/freesoftware (license+repo), r/Biohackers/r/HubermanLab (rigorous, non-promo). Never identical cross-posts same hour.
- **X / Mastodon / Bluesky:** build-in-public 2–4 weeks pre-launch (warm-shift clips, menu-bar UI, dev progress, circadian rationale); post repo early. Engage authentically (weeks before any ask) with indie-Mac devs, design accounts, circadian/sleep communicators, FOSS advocates — e.g., Sindre Sorhus, Jordi Bruin, MacStories/Viticci; *reference* (don't tag-spam) Huberman/Hattar science framing. Hashtags: #buildinpublic #indiedev #macOS #opensource. Mirror across all three (Croissant/Indigo).
- **Newsletters/curators:** MacStories/AppStories (personal pitch w/ embargoed access), Indie Dev Monday, iOS Dev Weekly (pitch a "how I built the warmth engine" technical post), Console.dev; AlternativeTo listing; 9to5Mac/MacRumors/AppleInsider post-traction.
- **Timeline:** Weeks −6→−4 finalize app + README + landing + reserve handles; −4→−2 build-in-public + warm-up + draft all assets; −1 pitch press privately + rehearse PH/HN + pre-write Reddit; **T-0** PH→Show HN→Reddit→socials in one orchestrated day; +1→+14 sustain replies, awesome-\* PRs, "how I built it" post, capture social proof; +2→+8 sequence more channels, ship visible updates, SEO the converting terms.

---

## 15. Execution Orchestration (OMC teams + tmux + /goal)

Per the founder's directive: **keep this main session on planning, design, brand, and high-level decisions** (its visual output + ideas are worth the token price). Dispatch heavy/backend implementation to separate **Opus 4.8, max-effort `/goal` sessions** with crisp specs. Use **tmux lanes** for parallel workstreams.

- **Lane A — Warmth engine (the long pole, hardest):** `WarmthKit` (overlay → DDC → gamma → capability/self-test → safety). Dispatch to a dedicated Opus 4.8 `/goal` with the §6 spec; *may keep the hardest parts in this session* (e.g., the measured-self-test demotion logic, IOAVService matching).
- **Lane B — App UI / UX:** `MenuBarExtra`, popover, advanced mode, Settings (Liquid Glass programmatic window), onboarding, hide-from-bar, reveal-true-color wiring. Opus 4.8 `/goal`, with /design-motion-principles audits routed back here.
- **Lane C — Brand & design system:** icon/wordmark, palette/type tokens, Figma library, DMG art, OG/PH assets. Designer agent + this session's taste.
- **Lane D — Landing page:** matthewball.me/abendrot (hero, demo, badges, science, SEO, OG). Opus 4.8 `/goal`.
- **Lane E — Release/CI:** signing, notarization, DMG, Sparkle appcast, Homebrew cask, GitHub Actions; fork the Go release CLI. Opus 4.8 `/goal`.
- **Lane F — Content & GTM:** README, privacy policy, science snippets (cited), PH/Show HN/Reddit drafts, launch timeline. Writer agent + this session.
- **Coordination:** shared task list; engine API contracts (Lane A) frozen early so B/D can proceed; verifier/reviewer in a **separate lane** (never self-approve); commit protocol per OMC. Kick off via `/team` after approval.

---

## 16. Decisions — CONFIRMED (2026-06-16)

1. **Build scope:** ✅ **Fully-featured 1.0 in one push** — all three layers + advanced mode + Settings + analytics at public launch, internally milestoned (§7). **Audit refinement (§21.6, ✅ CONFIRMED 2026-06-16):** keep the polished 1.0 as the public launch, but precede it with signed betas (0.1→0.9) for real-hardware validation. DDC ships **opt-in per display** until its restore/recovery tooling is proven (§21‑E3).
2. **In-app analytics:** ✅ **Aptabase, opt-in, OFF by default** (open-source/self-hostable; strongest OSS-health trust). Downloads always tracked via GitHub/Homebrew.
3. **Reveal-true-color:** ✅ **Ship both; default hold** (toggle option in Settings).
4. **Schedule default:** ✅ **Follow system sunset** (Night Shift schedule, read-only) + Custom + Always-on.
5. **Launch order:** ✅ **Soft pre-launch → coordinated Product Hunt + Show HN day** → awesome-* PRs + newsletters → sustained.
6. **Domain/hosting:** ✅ **abendrot.app purchased = primary canonical domain**; matthewball.me/abendrot 301-redirects to it. Landing = standalone static site at abendrot.app (host TBD; Vercel recommended — confirm at build).
7. **Homebrew:** ✅ **Own tap at launch**, submit to homebrew-cask central later.
8. **Pricing:** ✅ **Free forever**, optional GitHub Sponsors/tip, never a paywall.

---

## 17. Risks & Mitigations (top)

- **Gamma silently broken on M5 Tahoe** → overlay is the default layer; gamma only behind a measured self-test that demotes automatically. Track Apple FB22273782/FB19136488.
- **Buttonless Apple displays expose no DDC color** → capability-probe, fall straight to overlay.
- **Private APIs (IOAVService, CBBlueLightClient) shift between OS builds** → `dlopen`/`dlsym` + null checks + version gating; defensive degrade (DDC→overlay, schedule→solar); isolated swappable modules; CI builds per 26.x point release.
- **Overlay can't cover some native full-screen Spaces; visible in screenshots** → `collectionBehavior` + test top apps; screenshot-exempt toggle + reveal-true-color for captures.
- **Hold-to-reveal stuck-suspended (lost keyUp)** → watchdog auto-resume + debounce.
- **State left applied after crash** → neutral-reset on launch/quit + reconfiguration callback; store native DDC gain.
- **create-dmg AppleScript fails on headless CI** → DMG step on UI runner/local; ZIP pipeline stays headless.
- **Sparkle EdDSA key leak** → key in login keychain only; HTTPS appcast; Apple code-sign as second factor.
- **Telemetry backlash** → opt-in OFF by default; ≤8 anonymous events; honest privacy policy.
- **Health overclaim (FTC/community)** → general-wellness framing, cite-don't-assert, no medical claims; hedged language reviewed before any publish.
- **Solo-maintainer fragility** → signal active maintenance; clean contributor on-ramp; consider co-maintainers.

---

## 18. Roadmap

- **MVP (M0–M1 internal):** overlay warmth on all displays (stable identity, persisted), simple `MenuBarExtra` UI + strength + on/off, hold-to-reveal hotkey + watchdog, three schedule modes, crash/quit neutral-reset, Developer-ID signed + notarized, DMG+ZIP, MIT repo, a11y-respecting template icon.
- **v1.0 (public launch, M2–M6):** DDC layer + capability probe; measured best-available-wins + auto-demote; per-display transparency UI; advanced mode (per-display curves, per-app exclusions, fine Kelvin/ramp, layer override); gamma behind self-test; Night Shift external "TV" re-identify fix; coexistence detection (f.lux/Lunar/MonitorControl); Sparkle + Homebrew cask; tabbed Liquid Glass Settings; branded DMG; landing page; opt-in analytics; "The Science" panel.
- **Future:** ColorSync ICC injection (Layer 1.5) to bypass broken gamma; per-channel multiply shader so blacks stay black + HDR/EDR clamp; melanopic-aware warmth + dimming guidance; scenes/presets (Reading/Movie/Color-Critical) + Shortcuts/Siri/Control Center; ambient-light adaptive curves; localization; broader DDC panel-capability database.

---

## 19. Success Metrics & Acceptance Criteria

**Product acceptance (v1.0):**
- Warmth visibly applies to **built-in + ≥2 external display types** including one buttonless Apple panel (via overlay) and one DDC panel (via hardware), on **M5 Tahoe** (where gamma is broken) — verified by **lab/manual capture or capability classification** (NOT a default in-app screen-capture probe; see §21‑E1), with overlay as the guaranteed default.
- Each display shows the **correct method badge**; engine never silently no-ops (self-test demotes broken layers).
- Reveal-true-color: hold restores true color across all displays in <150ms and resumes on release; watchdog recovers a lost keyUp within N s; zero stuck-suspended in a 100-cycle test.
- Schedule follow tracks the system Night Shift `active` flip without altering the user's Night Shift setting; degrades to solar scheduler if the private API fails.
- Hide-from-menu-bar works and the app remains reachable + clearly re-enterable.
- Idle CPU/GPU ≈ 0% (overlay draws on change only); app bundle < ~5 MB; RAM ~tens of MB.
- Signed, notarized, stapled; clean Gatekeeper first-launch on a fresh Mac; Sparkle vN-1→vN update succeeds.
- A11y: Reduce Motion/Transparency + VoiceOver respected; light/dark correct.

**Launch metrics (directional):** GitHub stars + download_count trend; PH rank + HN front-page + points; r/macapps reception; AlternativeTo ranking for "f.lux alternative Mac"; (opt-in) activation + schedule-vs-manual + method-distribution aggregates.

---

## 20. Research Appendix

Deep detail and full source lists live in the persisted research artifacts:
- **Main sweep** (competitive landscape w/ 20 apps, UX, naming, tech APIs, analytics, marketing playbooks, science citations, synthesis): `docs/research/research-sweep-main.json`
- **Stack + exemplar teardowns** (native-Swift rationale, Wispr Flow deep-dive, 14 app teardowns, top patterns / anti-patterns): `docs/research/research-sweep-stack-exemplars.json`
- **Naming (CCG):** `docs/research/naming-codex.md`, `docs/research/naming-gemini.md`
- **Name clearance:** Ruhe/Schimmer/Abendrot clearance report (Abendrot = cleanest namespace, GO)
- **Reference apps studied:** github.com/fayazara/macos-app-skills (build/Sparkle/DMG/overlay patterns — reimplement, license caveat), dopedrop.app (aesthetic + "tiny native" copy formula), wisprflow.ai (HUD/motion/onboarding feel)
- **Reference build patterns:** `docs/research/reference-macos-app-skills.md` · **Name clearance:** `docs/research/name-clearance.md` · **Plan audit:** `docs/research/plan-audit-ccg.md`

---

## 21. Audit Revisions (CCG — Codex + Gemini, 2026-06-16)

These refine the sections above; where they conflict with earlier prose, **§21 wins.** Full findings: `docs/research/plan-audit-ccg.md`.

### 21.1 Engineering & correctness (refines §6, §8, §17)
- **E1 — Gamma is NOT screen-capture-verified by default** (fixed inline §6.1/§19). Post-compositor pixel measurement needs Screen Recording permission and breaks the no-permission promise. Gamma = per-device/OS **capability classification** + optional lab verification; **overlay is always the default**.
- **E2 — Overlay = documented-limitation UX fallback, not "hardware warmth."** Spec its limits (native fullscreen Spaces, Mission Control, login/lock, protected/HDR/EDR video, screenshots, multi-Space ordering). UI badge says `Overlay`; never market it as hardware.
- **E3 — DDC safety is a v1.0 gate, and DDC ships opt-in per display until proven.** Required before default-on: EDID native-state snapshot, per-display transaction queue, rate-limit/backoff, write-then-read verify, **emergency "Restore Displays" command**, launch-time stale-state recovery, and a user-facing "hardware mode active" note. Crash handlers can't reliably do async DDC → rely on launch-time recovery, not just exit handlers.
- **E4 — `DisplayIdentity` model** (not bare display UUID): `cgUUID` + current `CGDirectDisplayID` + EDID vendor/product/serial + transport + IORegistry path + NSScreen frame/scale (transient). Debounce `CGDisplayRegisterReconfigurationCallback` / `didChangeScreenParameters` bursts on the main actor; redaction rules for logs/analytics.
- **E5 — Private-API kill switch + release policy:** runtime feature flags, OS-build denylist, a "private APIs disabled → overlay-only" fallback mode, and **signed+notarized private-API smoke tests from M0** (not just at release).
- **E6 — Night Shift follow is best-effort:** rename internally `SystemNightShiftStateFollower`; UI copy "follow system Night Shift *when available*"; add manual/approx-timezone fallback **before** requesting Location Services.
- **E7 — Defer auto screenshot/recording-suspend** (no clean public API). v1.0 ships manual Reveal True Color + a "reveal during captures" shortcut.
- **E8 — v1.0 = per-app exclusions only** (`NSWorkspace.frontmostApplication`); per-website needs browser integration/Accessibility → **future**.
- **Module split (refines §6.1):** `WarmthCore` (pure, no AppKit/IOKit) · `DisplayServices` (identity/hotplug/ColorSync/gamma) · `HardwareDDC` (private IOAVService behind protocols) · `OverlayRenderer` (AppKit/Metal, main-actor) · `NightShiftBridge` (optional private) · `AbendrotApp`. `CInterop` stays thin; every private lookup returns a typed capability result.
- **E14 — Failure-injection/persistence test suite (refines §8):** crash-during-DDC-write, SIGKILL, wake-while-service-gone, hotplug-during-reveal-hold, lost-keyUp-across-Space, duplicate identical monitors, ColorSync changes, Night Shift/TrueTone/HDR on, competing apps (f.lux/Lunar/BetterDisplay/MonitorControl).

### 21.2 Release & DMG robustness (refines §9)
- **Two DMG modes:** `pretty-dmg` (branded Finder window on a logged-in UI runner) + `plain-dmg` (deterministic `hdiutil` fallback). **Gate every release on ≥1 notarized + stapled DMG.** In CI/UI-runner: mount the final DMG and verify layout, signature, quarantine first-launch, and `/Applications` drag-install. (create-dmg AppleScript hangs headless — issue #154.)
- **One Sparkle release authority** (resolves the keychain-vs-CI contradiction): either a **local release machine** (keychain-only EdDSA key) **or** a **GitHub Actions environment-protected secret with manual approval** — not both. Document key rotation/revocation.
- **M0 signed+hardened+notarized smoke build**; parse `notarytool log`; verify `spctl -a -vvv`.
- **Homebrew cask contract:** `livecheck`, `auto_updates true`, `zap` stanzas, SHA256, versioned URLs; publish only after Sparkle/appcast + DMG are coherent.
- **CI split:** hosted (lint/unit/archive/sign-dry-run) + **self-hosted physical matrix** (M5 Tahoe gamma-broken, M3/M4, Apple display, DDC monitor, HDMI/dock) + manual fresh-user Gatekeeper gate. (Hosted runners can't give every point release or real displays.)

### 21.3 Liquid Glass & UX — Tahoe-native (refines §4, §5.2)
- **Make the glass feel "wet," not flat:** cursor-aware **specular tracking** (edge glint follows pointer), **variable-thickness/lens blur** (tighter blur at edges implies volume) — the gap between "looks like Tahoe" and "is Tahoe."
- **Material hierarchy:** clear transient Liquid Glass for the popover; a more-opaque **"frosted ember"** for the persistent/data-heavy **Settings** so text stays legible over busy backgrounds.
- **Reduce-Transparency fallback = ember-tinted SOLID**, never neutral grey — keep the warm identity when opaque. (Critical a11y + brand fix.)
- **Reveal = spring, not fade:** SwiftUI `.interactiveSpring` "lift the veil" so it feels physical/elastic.
- **Advanced mode = "liquid expansion"** of the popover (the glass grows to hold power rows) for inline use; the Settings window remains for deep config.
- **Onboarding = "3 clicks to warmth"** (permit notifications → set max warmth → confirm schedule); everything else in Settings. (Tightens §4.6's 90-second flow.)

### 21.4 Icon iteration & DMG experience (refines §5.5, §9)
- **Icon: 3-3-1 variation strategy** — pure glyph / glass-pebble squircle / abstract orb — then converge. Build a **"vibrant template"** 18px menu-bar icon that subtly **glows amber when active**, validated against **wallpaper desktop-tinting** (faint outer glow or 0.5pt stroke so it never disappears on warm wallpapers).
- **DMG as unboxing:** split-screen **cold→warm** background (dragging the app from "cold/blue" to the "warm" Applications side demos the product); higher-gloss DMG-internal icon; and a **"move to /Applications" Liquid Glass HUD** (LetsMove-style) instead of a stock dialog.

### 21.5 GTM refinements (refines §10, §14)
- **"Audit the engine" on the landing page:** a code-snippet showing the real `WarmthKit` DDC write — transparency proof for the NightOwl-burned audience.
- **Tailor the launch LEAD by channel:** Show HN / PH lead with the **reliability/designer hook** ("f.lux is broken on my M5", Reveal True Color) — the tech crowd is cynical about "circadian health." Keep **health as the brand story** (positioning unchanged). Not a reversal — a channel-framing nuance.
- **Add a v0.9 designer beta ~2 weeks pre-PH** (X/Mastodon) to harvest real Liquid-Glass-UI screenshots for "social proof of beauty" in the PH gallery.

### 21.6 Decision change to confirm — staged betas before the polished 1.0
Codex flags "fully-featured 1.0 in one push" as the riskiest launch choice (the hard parts fail only on real hardware/point releases). **Refinement (preserves the 1.0 moment):** precede the branded 1.0 launch with signed public betas — `0.1` overlay+hotkey+schedule+DMG+notarization → `0.2` DDC opt-in + restore tooling → `0.3` Sparkle → **`1.0` branded launch after the hardware matrix passes.** This complements the GTM soft-pre-launch and the v0.9 designer beta. **✅ CONFIRMED by founder 2026-06-16 — staged-beta strategy adopted; DDC opt-in until restore tooling proven.**

### 21.7 Validated (no change needed)
- "Show each display's warmth method (Hardware/Gamma/Overlay)" — already a core differentiator (§4.1); independently flagged by Gemini as a top trust lever. Keep.

---

## 22. Execution Log — Session 2 (2026-06-16, build kickoff)

Execution started in `Documents/abendrot` (branch `build`, local only — not pushed). Lead session coordinates; heavy lanes run as parallel Opus subagents (not tmux). Amendments from this session:

- **Signing DEFERRED (cost decision).** Founder is not purchasing the $99/yr Apple Developer Program yet. Build + the full hardware test matrix run **unsigned/local** (no account needed for development); notarization is a **launch-time** decision. Lane E therefore ships a **two-mode** pipeline: mode A (Developer-ID signed + notarized + stapled, gated behind later-supplied credentials) and mode B (unsigned/local + plain `hdiutil` DMG — the current default). Trust copy must not hard-claim "notarized" during the unsigned phase; the load-bearing trust claims are "open source, auditable, no telemetry by default." (Amends §3, §9.)
- **Binaries + Sparkle appcast host = GitHub Releases** (free CDN + `download_count`); landing stays on **abendrot.app**. (Confirms §10/§11.)
- **Coming-soon placeholder** built at `../abendrot-site/` (sibling, outside the repo) — minimal aesthetic holding page; **not deployed** (founder's gate). Distinct from the full Lane D landing site (`landing/`).
- **Orchestration:** Wave-1 (A engine contract, C brand, E release, F content) done; C/E/F adversarially verified **pass-with-nits** then remediated. **Wave-2 lanes (B app UI, D landing, G QA) started early** against the **frozen engine contract** + **provisional brand tokens** — only final brand polish + real screenshots are gated on founder brand-selection.
- **Engine contract FROZEN:** `docs/engine/warmthkit-api-contract.md` + `WarmthKit/Package.swift` (6-module split: WarmthCore/DisplayServices/HardwareDDC/OverlayRenderer/NightShiftBridge/WarmthKit + CInterop). Xcode-26 compile gate owned by Lane G.
- **Pending founder input:** brand icon + screen selection (galleries served locally) — the only Wave-2 blocker for final polish. External gates unchanged (public repo, remote push, live deploy, external posts).

---

## 23. Execution Log — Session 3 (2026-06-17)

- **Public repo PUBLISHED:** github.com/matthewrball/abendrot (public, MIT, **clean single-commit history — all planning scrubbed/hidden**; clean export at `../abendrot-public`). CI green. It is BEHIND the private build repo (icon / sunset palette / M7 not yet public) → a **re-publish is needed** (founder push gate). Two-repo model: this dir = private (full planning, never pushed); the public repo carries no planning history.
- **Engine system layers landed (real, `swift test` = 53 tests pass):** M0 OverlayRenderer (alpha-tint veil; true per-channel multiply = §18 future), M7 hotplug/wake re-baseline observer, real Night Shift follower (`CBBlueLightClient` via runtime resolution), gamma capability classification. **DDC (`HardwareDDC`) remains the stub → M2 is next** (IOAVService + EDID snapshot / capability probe / write-then-read verify / restore / emergency "Restore Displays"; needs real external-monitor verification).
- **App icon shipped:** founder art → `assets/abendrot.png` (masked, transparent corners) → full iconset / `.icns` / `AppIcon.appiconset`, **baked into the built `.app`**; reproducible via `scripts/icon/build-icons.py`.
- **Brand direction pivoted to an icon-derived SUNSET palette** (founder: "maybe temporary"): grounds #160A12/#221019/#341320, accent #FD9228/#FFC061/#C2310A, signature `--sunset-sky` gradient — applied + build-verified across `brand/tokens.{css,json}`, the app's `Colors.xcassets` (19 colorsets, dark+light), the landing page, and the coming-soon site.
- **CCG review (Codex+Gemini) applied + verified** (engine coordination, release/CI integrity, app quit/login/Sparkle, landing a11y); both reskin lanes + the engine milestone adversarially reviewed.
- **Env:** full Xcode 26.5 (license agreed) — `swift build`/`swift test`/`xcodebuild` work; Xcode MCP registered (user scope), loads after a session restart. Tools: xcodegen / Pillow / sips / iconutil.
- **Next:** M2 (DDC) + real-hardware pass; re-publish public repo; live failure-injection + hardware-matrix runs; in-app motion polish (`/design-motion-principles`); landing deploy — externally-facing ones founder-gated. Full handoff: `RESUME-PROMPT.md`.

---

*Status: ✅ APPROVED for execution (2026-06-16). All decisions locked; §21.6 staged-beta strategy confirmed; no open items. Execution proceeds in `/Users/ball/Documents/abendrot` via `/team` across the §15 lanes, with heavy backend dispatched to Opus 4.8 `/goal` (max effort) and the hardest engine logic retained in the lead session. See `RESUME-PROMPT.md` to start the execution session.*
