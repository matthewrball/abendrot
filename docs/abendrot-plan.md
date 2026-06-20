---
name: abendrot
title: "Abendrot — Master Plan (build → release → growth)"
status: IN EXECUTION — Session 6 (2026-06-17): §25 warming overhaul + max-warmth hybrid DONE & verified; public mirror re-synced/scrubbed. Living tracker = LAUNCH.md (workspace root).
owner: matthewrball (matthewball.me)
created: 2026-06-16
positioning: circadian-health-first (reliability as proof)
license: MIT
stack: native Swift (SwiftUI + AppKit), macOS 26 "Tahoe", Xcode 26
repo: github.com/matthewrball/abendrot
domain_primary: abendrot.app (purchased 2026-06-16)
landing_secondary: matthewball.me/abendrot (301-redirect → abendrot.app)
home_dir: /Users/ball/Documents/abendrot/abendrot-build (private build repo; inside the workspace umbrella /Users/ball/Documents/abendrot)
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

### 14.1 Future Initiative (TABLED 2026-06-17) — SEO/AEO content & AI-visibility engine

> **Status: parked, not yet started.** Founder vision (2026-06-17): build a large, durable
> **SEO + AEO (Answer-Engine Optimization)** content engine so Abendrot is *the* answer when a
> human searches — or an AI assistant is asked — "best f.lux alternative for Mac," "warm my
> external monitor," "screen warmth for circadian health," etc. Goal: front-of-mind in both
> classic search results **and** AI recommendations (ChatGPT/Claude/Perplexity/Gemini/Google AI
> Overviews). **Integrate with the website (`abendrot.app`) before the 1.0 launch.** Scope it as a
> dedicated workstream — likely a **large multi-agent team** producing the content + technical SEO
> at volume — when we pick it up; this entry just captures the vision so it isn't lost.

Anticipated pillars (to be fleshed out when un-tabled):
- **Technical SEO/AEO foundation on the site:** `robots.txt` + XML sitemap; an **`llms.txt`** (and
  per-page machine-readable summaries) so answer engines can cite us cleanly; rich **structured
  data** — `SoftwareApplication`, `FAQPage`, `Article`/`BlogPosting`, `BreadcrumbList` JSON-LD;
  clean factual copy LLMs can quote verbatim (extends §10's AI-visibility notes); canonical URLs,
  OG/Twitter cards, fast Core Web Vitals.
- **FAQ corpus:** a deep, schema-marked FAQ (does it work on external monitors? on M-series Tahoe?
  does it need permissions? is it private? how is it different from Night Shift/f.lux?) — high-
  intent, directly answer-engine-quotable.
- **Circadian-health editorial (cited, hedged — must obey §13's general-wellness guardrails):** a
  series of writeups/blogs on evening light, melanopic exposure, the science (cite-don't-assert,
  never medical claims), each targeting a real query cluster.
- **Comparison/alternative pages:** Abendrot vs f.lux, vs Night Shift, vs Lunar/MonitorControl, vs
  NightOwl — honest, feature-table-driven, capturing the large "f.lux alternative" evergreen
  traffic (ties to the AlternativeTo listing in §10/§12). Keep claims accurate and defensible.
- **Distribution/measurement:** internal linking, programmatic pages for the long tail, and a way
  to track AI-citation share + organic rankings over time (privacy-respecting analytics per §11).

Cross-refs: §10 (landing/SEO), §12 (repo/AlternativeTo/community), §13 (health-claim guardrails —
**binding** on all content), §14 (launch sequencing). When un-tabled, stand up the agent team via
the §15 orchestration model.

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
- **Future:** ColorSync ICC injection (Layer 1.5) to bypass broken gamma; per-channel multiply shader so blacks stay black + HDR/EDR clamp; melanopic-aware warmth + dimming guidance; scenes/presets (Reading/Movie/Color-Critical) + Shortcuts/Siri/Control Center; ambient-light adaptive curves; localization; broader DDC panel-capability database. **GTM/content:** the SEO/AEO content & AI-visibility engine (§14.1, tabled — integrate with the site before 1.0).

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

## 24. Execution Log — Session 4 (2026-06-17): M2 — DDC hardware path (the last engine layer)

- **M2 DDC implemented + verified (`swift test` = 81 tests in 20 suites pass; app `xcodebuild` = BUILD SUCCEEDED).** `HardwareDDC` is no longer a stub: the IOAVService DDC/CI write path is real, behind protocols and an actor, opt-in per display (§21‑E3), with overlay still the universal floor.
- **Protocol locked from canonical sources, not memory.** The exact Apple-Silicon IOAVService DDC/CI wire protocol was reconciled from two independent shipping implementations read in full at source — **m1ddc** (C) and **MonitorControl `Arm64DDC`** (Swift) — cross-checked byte-for-byte with every golden vector hand-recomputed; a third (memory-only) source's checksums were demonstrably wrong and discarded. Captured durably in **`docs/engine/ddc-protocol-spec.md`** (chip 0x37, write offset 0x51, set seed 0x3F, get-request seed 0x6E, reply seed 0x50, gain VCP 0x16/0x18/0x1A, per-monitor max, verify-by-readback, timing). **DDC cannot be verified headlessly** → the protocol is certain but hardware tolerance/timing/gain-support/targeting remain a **founder real-monitor pass** before the feature is claimed to work.
- **What landed:** pure VCP packet layer (`DDCProtocol`, golden-vector unit-tested) · dlsym-resolved `IOAVServiceBus`/`IOAVServiceBusProvider` (IORegistry→`DCPAVServiceProxy` resolution, `Location=="External"` gate + a `transport != .builtIn` defence-in-depth so built-in panels are **never** DDC'd) · `IOAVServiceDDCTransport` actor (serialized per-service transactions, native-gain snapshot, relative warming `native×gain`, write-then-read verify + retry/backoff, restore with **aggregate** verify) · `DDCSnapshotStore` (protocol + file-backed + in-memory) · engine wiring: **launch-time stale-state recovery** (reset-to-native BEFORE any apply), write-ahead dirty flag, honest DDC→overlay fallback (never a false Hardware badge), per-display settings retained across hotplug. Engine **public surface unchanged** (frozen contract intact); test seams (`WarmthEngine.test`, `simulateReconfiguration`, `DisplayIdentity.fixture`) are internal-only.
- **§21‑E14 failure-injection now runs headlessly:** S1 (crash-mid-write → launch recovery, reset-before-apply ordering), S2 (SIGKILL → relaunch restore, no teardown hook), S3 (wake-while-service-gone → no writes to a dead service, re-applies on return) — plus golden-vector protocol tests and the verify/retry transport state machine via a fake I²C bus.
- **Adversarial review (separate lane, 4 dimensions, per-finding verification) applied:** wire protocol confirmed **clean** (0 real byte-level defects); fixed a **critical** actor-reentrancy bug (held a `displays` index across `await` → snapshot-and-relocate-by-identity), a **medium** restore-swallows-failures bug (now reports aggregate verify failure so a partial restore stays dirty for recovery), and strengthened the S1/S3 assertions that were vacuous. Built-in defence-in-depth + a typedef-clarity nit also addressed.
- **Bonus critical fix (NightShiftBridge):** M2's tests were the first to actually run `WarmthEngine.start()` with a live `CBBlueLightClient` and surfaced a pre-existing **app-launch crash** — the `setStatusNotificationBlock:` block was passed to Objective-C as non-escaping but CoreBrightness retains it (`@noescape`-escaped trap). Fixed (`@escaping`). The app was built but never run, so this had never been hit.
- **Still STUBBED → none in the engine.** All five layers are now real (overlay alpha-tint M0, gamma classification, Night Shift follower, M7 hotplug/wake, **DDC M2**). Remaining engine follow-ups are the true-multiply overlay shader (§18) and the live real-hardware DDC pass.
- **Next:** founder real-external-monitor DDC pass (the one thing headless can't prove); then re-publish the public repo (now also includes M2 + the night-shift crash fix); live failure-injection + hardware-matrix; in-app motion polish; landing deploy — externally-facing ones founder-gated.

---

## 25. ⭐ TOP PRIORITY (next session) — Warming-mechanism overhaul: truly remove blue, don't just tint

**Founder feedback after the first real app run (2026-06-17):** enabling "Warm my displays" currently
"just adds a white tint — it doesn't really make the display warmer like BetterDisplay Pro does."
This is **the headline value prop**, so it is the #1 next thing to fix. Tackle in a **fresh session**
(founder's context is high). This section is the brief.

### Root cause (now understood, not speculative)
The engine defaults every display to the **overlay** layer. Per the §18 investigation
(`docs/engine/overlay-multiply-decision.md`), a permissionless overlay can only do **source-over
alpha** (`result = dst·(1−a) + tint·a`) — it **washes amber on top**, it can NOT remove blue from the
signal or darken (multiply) anything. So it inherently reads as a "tint," not a warm. **True warming
(white-point shift / blue removal, the BetterDisplay behaviour) only comes from the gamma LUT
(built-in display) or DDC RGB gain (external).** The engine already has the Kelvin↔gain math and both
backends — the problem is the **default policy** sends everything to the overlay.

### The pivotal unknown to settle FIRST
Gamma (`CGSetDisplayTransferByTable`) is currently **hard-classified `.unsupported(.gammaBrokenOnThisOS)`
on Apple-Silicon + macOS 26** (`GammaClassifier`), based on a *research assumption* that Tahoe silently
no-ops it. **This has never been tested on the founder's actual Mac** — and the classifier blocks even a
manual override, so we've never seen if it works. **Step 1: bypass the classifier and visually test
gamma on the founder's hardware.** If it warms → make gamma the built-in default (the fix is then mostly
a policy change). If it truly no-ops → we need the path below.

### Next-session agenda (dispatch research like the DDC/overlay passes)
1. **Gamma reality check (founder, ~15 min):** a tiny probe that force-applies a strong warm gamma ramp
   to the built-in display, bypassing `GammaClassifier`; founder eyeballs whether it warms or no-ops.
   Settles the central assumption.
2. **Research: how does BetterDisplay Pro (and f.lux) truly warm the BUILT-IN Apple display on macOS 26
   Tahoe?** It demonstrably works and is NOT an overlay — so there is a method (CoreDisplay private APIs
   e.g. `CoreDisplay_Display_SetUserColorMatrix` / gamma-table setters, a virtual-display/override, or
   SkyLight). Study it the way we studied **m1ddc** for DDC (waydabber authors both — likely documented).
   Output: an implementable, **kill-switchable** technique (private APIs → behind `privateAPIsEnabled`,
   like DDC/NightShift).
3. **Research: the blue-light / circadian benefit ("understand the benefit"):** melanopic EDI, the ipRGC
   ~480 nm peak, how white-point shift + dimming map to melanopic suppression, and the right warming
   curve + warmest-point default. Informs the engine (how much to warm) AND the value prop / §13 / §14.1
   SEO content. Hedged, cited, non-medical (§13 guardrails binding).
4. **Engine policy change:** make `recommend()` / `LayerResolver` prefer **gamma on the built-in**
   (where proven) and **DDC on externals** (opt-in) as the *active* warm path; demote the overlay to the
   genuine last-resort floor (displays where gamma is broken AND DDC is unavailable). Add an honest in-UI
   note when a display can only be tinted, not truly warmed.
5. **Overlay stays** as the fallback (already tuned: saturated amber + gated alpha, §18 resolved). It is
   not the headline mechanism.

**Bottom line for the next session:** the win is almost certainly "make gamma/DDC the real warming path"
— either gamma works on this hardware (policy fix) or BetterDisplay's built-in technique is reproducible
(new kill-switchable backend). The overlay was always meant to be the floor, not the product.

### Session-5 addendum (2026-06-17) — run-2 symptom, the macl/FDA gotcha, the gamma probe, in-flight research

Two things from the founder's runs that weren't yet in the docs (the files were write-locked at the
time — see the gotcha below), now recorded:

1. **Run-2 symptom — "no warming at all / app broken."** A later run showed not a weak tint but
   *nothing*. Two non-exclusive causes, both now located in code (the live-path audit is verifying
   which dominates):
   - **Schedule-gating (most likely, and by design).** `WarmthEngine` computes
     `engineOn = isEnabled && decision.isActiveNow && !isRevealing` (`WarmthEngine.swift:532`) and the
     effective target is `.off` whenever `engineOn` is false (`:552`). The default `scheduleMode` is
     `.followSystemNightShift` (`EngineConfiguration`, `EngineTypes.swift:18`). So if the founder's
     **Night Shift is OFF or it is daytime**, `decision.isActiveNow == false` → the engine warms
     NOTHING even though the toggle reads "enabled." That exactly reproduces "I turned it on and
     nothing happened." **Isolate by setting Always-On + max warmth before concluding the engine is
     broken.**
   - **A macl-corrupt partial build.** The "broken" build may have been a half-written/locked artifact
     from the macl issue below; a clean rebuild is the other half of the triage.

2. **The macl / Full-Disk-Access gotcha (was build-blocking).** A prior agent's **sandboxed** bash
   (xcodegen/xcodebuild/ditto) stamped `com.apple.macl` records on repo files under `~/Documents`, so
   xcodegen/xcodebuild *and even editor writes* hit **"Operation not permitted"** (confirmed on
   project.yml, scripts/dmg/plain-dmg.sh, project.pbxproj, this plan). **Fix:** System Settings →
   Privacy & Security → **Full Disk Access** → enable Terminal (and Claude Code if building through
   it) — FDA bypasses the macl. **Permanent alternative:** relocate the repo out of `~/Documents` (TCC
   only guards Documents/Desktop/Downloads). **RULE: never build the app from a sandboxed agent —
   build in the founder's FDA'd terminal.**
   **Status (this session): FDA is CLEARED** — the previously-locked files now carry only
   `com.apple.provenance` (the `com.apple.macl` is gone) and a repo write-test succeeds. The plan is
   editable again.

**Gamma reality-check probe — BUILT + type-checks clean (agenda step 1).**
`scripts/probe/gamma-probe.swift` — a standalone Swift script (public CoreGraphics only; no private
APIs, no entitlements, no app build) that **bypasses `GammaClassifier`** and calls
`CGSetDisplayTransferByTable` directly on the **built-in** display, using the engine's *exact* warm
curve (`rgbGain` + `GammaBackend.ramps`, copied verbatim). It sweeps 3400K → 2700K → 2000K → 1500K,
~6s each, then auto-restores (Ctrl-C restores instantly). **The founder runs it** (it changes the real
display, so it can't be run from an agent):
```
swift scripts/probe/gamma-probe.swift
```
Decision rule: screen visibly warms → **gamma works on this Mac**, and the fix is mostly a policy
change (today gamma is auto-blocked on Apple-Silicon + macOS ≥ 26 by
`GammaClassifier.firstBrokenAppleSiliconOSMajor = 26`, and `LayerResolver` never auto-selects gamma —
only via override, and only when `.supported`). Nothing changes at any step → the no-op assumption
holds → build BetterDisplay's private built-in path.

**Session-5 in flight (background workflow):** (a) how BetterDisplay Pro / f.lux *truly* warm the
built-in Apple panel on Tahoe (CoreDisplay private APIs → an implementable, kill-switchable backend);
(b) the melanopic / blue-light benefit → warming curve + warmest-point default + §13-safe value-prop
copy; (c) a live OverlayBackend/GammaBackend render-path audit (the 84 headless tests use fake
backends, so a live regression would pass CI). Each stream is adversarially verified in a separate
lane; findings fold into agenda steps 2–4.

### Session-5 RESULTS (2026-06-17) — gamma confirmed, the real fix found, run-2 fully explained

All three research/audit streams completed and were **adversarially verified `isSound` (high
confidence)**; the built-in-warming stream was independently reproduced **on the founder's exact
machine** (Apple **M5 MacBook Air, Mac17,3, macOS 26.5 build 25F71**). Headline outcomes:

**1. Gamma WORKS on the founder's Mac — the classifier assumption was over-broad.** The founder's
`gamma-probe.swift` sweep **visibly warmed** the built-in panel, and the research confirms why: the
2026 gamma-no-op regression is **specific to M5 Pro/Max/Neo on macOS 26.3/26.4** (Apple DTS
confirmed; FB22273730/FB22273782), and **base M5 / 26.5 round-trips correctly**. So
`GammaClassifier`'s blanket *"Apple Silicon + macOS ≥ 26 → broken"* is wrong for base M-series.
**Critical caveat (verifier):** a write+readback probe **cannot** detect the no-op (the bug makes
`CGGetDisplayTransferByTable` read back the values you wrote while the pixels don't change) — so gamma
must be gated by a **chip+OS allowlist or a visual check**, never a readback probe.

**2. The superior, universal path: `CoreDisplay_SetWhitePointWithDuration(x, y, duration)`.** This is
**Apple's own Night Shift / True Tone white-point mechanism** — a genuine white-point shift / blue
removal (not an overlay, not the gamma LUT), so it is **immune to the Tahoe gamma no-op** and works
even on the M5 Pro/Max where f.lux silently fails (a marketable wedge: *"warms the newest Macs where
f.lux can't"*). Verified on-host: the symbol resolves, signature is
`(double x, double y, double duration)`, it routes through `com.apple.CoreDisplay.master`, and
**CoreBrightness (which implements Night Shift) imports it**. Shipping precedent: **Vimes** (iccir,
MIT) uses it after `CBBlueLightClient setCCT:commit:`. No permission/entitlement. The founder's
guessed symbols (`CoreDisplay_Display_SetUserColorMatrix`, `…SetGammaTable`, etc.) **do not exist** —
the real color-matrix symbol is `CoreDisplay_SetAccessibilityMatrix` (lower priority). Pixel-level
warming is **proven-mechanism but pending-visual** → settled by `whitepoint-probe.swift` (built,
type-checks; founder runs it).

**3. The "no warming / broken" run-2 is fully explained — and it was NOT an overlay regression**
(393f300 *improved* the tint). Verified root causes, ranked:
   - **Schedule-gating (primary).** Default `scheduleMode = .followSystemNightShift` →
     `engineOn = isEnabled && decision.isActiveNow && …` is **false whenever the Night Shift follower
     truthfully reports OFF** (daytime / Night Shift disabled). The degrade-to-evening-window fires
     only when the follower is *unavailable* (`nil`), **not** when it reports a real `false`. So
     enabling the app while Night Shift is off warms nothing. (`WarmthEngine.swift:515-532`,
     `SchedulePolicy.swift:34-51`, `ScheduleResolver.swift:68-72`.)
   - **`globalWarmth` defaults to `.off` (strength 0).** Flipping the toggle without dragging the
     slider applies zero warmth. (`EngineTypes.swift:63`.)
   - **No UI state persists** (only `launchAtLogin` + `softConfirmationTone`) → every launch resets to
     disabled / off / follow-Night-Shift. A major "it worked then broke" contributor.
   - **Stale on-disk build** (Debug bundle predates the M2 `@escaping` crash-fix) → could crash at
     launch. Rebuild fresh.

**4. Curve + warmest-point (verified science).** The strength→Kelvin map is **Kelvin-linear** today
(`WarmthLevel.kelvin`) → "feels dead through the first half, then lurches warm." Fix: **mired-linear**
(`M = 1e6/K`). Warmest-point should be **2700K max / ~3400K default** (1900K is candle-territory and
invites the "just orange" verdict — keep `Kelvin.warmestSupported = 1900` only as the internal clamp).
6500K→2700K removes ≈60% of per-lumen melanopic content (typical display white points, equal
luminance) — a claim that is **honest only for the gamma/DDC/white-point path, not the overlay tint**.
Couple an optional dim nudge (warming without dimming blunts the benefit). Doc fixes: AAO citation is
**reviewed 2021, not 2024** (`science-snippets.md` L64/70/118-119); clean the Hoehn author string.

### Reframed §25 plan (priority order)

**STATUS (Session 6, 2026-06-17): P1 + P2 DONE; P3 mostly done; P0 partially done. Granular living
tracker is now `LAUNCH.md` (workspace root).**

- ✅ **P1 — "it truly warms (removes blue), not a tint" — DONE:** gamma is the UNIVERSAL true-warm path
  (built-in + external) via the chip+OS-aware `GammaClassifier`; overlay is the genuine floor; an honest
  in-UI "tint only" note ships (§25.J, iterating). The CoreDisplay white-point backend was researched and
  **SHELVED** (didn't warm in isolation; couples to Night Shift). (§25.F)
- ✅ **P2 — feel — DONE (and superseded):** mired-linear curve shipped; warmest point is now **1900K
  everyday max / 500K opt-in expanded range** (Session-6 hybrid — replaces the earlier 2700/3400 and the
  pure-red 500 default). (§25.D/E + Session-6 RESULTS below)
- 🟡 **P3 — hygiene — mostly done:** fresh rebuilds + 91/21 tests green; doc citation fixes done. A
  non-headless live-overlay smoke test is still open. (§25.G/H)
- ✅ **P0 — "enabling actually warms" — DONE:** schedule-gating fixed (follow the sunset *window*);
  warmth-on-enable default set (strength 0.7 → ~2412K); **all UI state now persists** — `warmestPoint`
  (Session-6) + `isEnabled` / `globalWarmth` / `scheduleMode` (Session-7) via `UserDefaults`, restored in
  `AppModel.start()` after `engine.start()` by replaying the setters. Fresh-install defaults preserved via
  the `object(forKey:)` guard (an unset key keeps the engine's 0.7 out-of-box warmth rather than reading
  0.0); `scheduleMode` is Codable JSON (carries `.solar`/`.custom` associated values) and self-heals a
  corrupt blob; a persisted strength 0.0 is honored as a real "off" choice, distinct from unset.
  Verified: 91/21 tests green, app BUILD SUCCEEDED, adversarial code-review APPROVE (0 Critical/High). (§25.B)

Full verified output (all three streams + verdicts): the Session-5 workflow result file.

### Session-5 RESULTS part 2 (2026-06-17) — external gamma works → gamma is the UNIVERSAL warm path

Founder ran `scripts/probe/gamma-probe-external.swift` (applies the gamma ramp to every display at
once): the **external LG UltraFine warmed via gamma just like the built-in** on the base M5. This
disproves the plan's standing assumption (§6.2) that "external gamma is flaky/dead on Apple Silicon"
— the same untested-assumption pattern as the built-in. **Decision: gamma is the universal true-warm
default for ANY display where the transfer table is supported** (built-in + external), not built-in
only. Why this matters beyond unifying the two displays:

- **Gamma is OS-level and display-agnostic** — it needs no per-monitor capability, so it's far more
  universal than DDC (which needs each monitor to implement RGB-gain VCP, which many don't).
- **It is the ONLY true-warm path for buttonless Apple displays** (LG UltraFine, Studio Display, Pro
  Display XDR), which expose no DDC gain VCP. This is precisely the §2.2 differentiator ("warms the
  UltraFine / Studio Display / Pro Display XDR where f.lux/Night Shift fail"). DDC literally cannot
  warm them; gamma can.

**New layered model** (supersedes the §6.2 "DDC-first for externals" table):

| Display / chip | Automatic default | Opt-in upgrade | Floor |
|---|---|---|---|
| Any display, gamma supported (base M-series / Intel / pre-26) | **gamma** (true warm) | DDC (external, hardware) | overlay |
| External, gamma broken (M5 Pro/Max/Ultra) | overlay | DDC (if monitor supports gain) | overlay |
| Built-in, gamma broken (M5 Pro/Max/Ultra) | overlay | — | overlay |

`LayerResolver` order is now: override → DDC (opt-in, external) → **gamma (any display, supported)** →
overlay floor. DDC stays valuable as the opt-in hardware upgrade and as the external true-warm path
for the gamma-broken Pro/Max bracket. **Universality caveat (honest):** gamma is verified on this base
M5 (built-in + UltraFine); it's OS-level so it should generalize, but specific monitor/GPU/connection
combos could still no-op — mitigated by the DDC opt-in escape, the overlay floor, the honest method
badge, and the planned one-tap "did this warm?" onboarding check (the real safety net, since a
readback probe can't detect a silent no-op). Implemented + 91 tests green; adversarially reviewed.

### Session-5 founder directives (2026-06-17) — warmth range, incompatibility honesty, testing, Quit

Four directives from the founder while dogfooding the real app:

1. **Maximum warmth must go MUCH warmer.** The research's 2700K warmest cap (chosen for legibility +
   melanopic diminishing returns) is too conservative for the founder — at full slider it "isn't warm
   enough." **Override the research rec in favor of user range:** lower `defaultWarmestPoint` so the
   slider's "Warmer" end reaches a deep candle warmth (~1500K), recalibrate the default strength to
   keep a comfortable out-of-box default, and lower `Kelvin.warmestSupported` to match. (Proper
   follow-up: expose `warmestPoint` as a user setting so each user picks their own warmest end.)
   Honesty stays intact: the melanopic-% claim is still only valid for the gamma/DDC path, and warmer
   = less legible.

2. **Be UPFRONT in-app about OS/hardware incompatibility (BINDING).** When a display can only be
   tinted — gamma is `.unsupported` on this chip/OS (M5 Pro/Max/Ultra on macOS ≥ 26) AND DDC isn't
   available — the app must say so *clearly*, not just via the subtle "Overlay" badge: e.g. a per-row
   "tinted, not truly warmed — your [chip] on macOS [version] can't truly warm this display" note, and
   an app-level banner when NOTHING connected can truly warm. The detection already exists
   (`GammaClassifier` + `DisplayState.capabilities`/`appliedMethod`); this is surfacing it honestly.
   **The founder wants to design this** — so build a preview path (below) and iterate the copy/visual
   with them, don't finalize unilaterally.

3. **Preview/simulate incompatible configs (so the founder can design the notice + we can test).**
   Add a dev hook to force the overlay-only/incompatible state on a *compatible* Mac (e.g. an env var
   that makes `GammaClassifier` return `.unsupported`, or reuse the kill switch
   `setPrivateAPIsEnabled(false)` which already drops to overlay-only). Lets the founder see exactly
   what an incompatible user sees and design the notice around it.

4. **Pre-release testing matrix (BINDING before 1.0).** Test gamma warming across MANY more monitors
   (brands, HDMI / DisplayPort / Thunderbolt / USB-C, resolutions, HDR/EDR) and Mac configs (M-series
   base / Pro / Max / Ultra, Intel, multiple macOS 26.x point releases) to map exactly where gamma
   works vs silently no-ops — and for each incompatible config, confirm the honesty notice (#2) fires
   and reads well. Extends §8 device matrix + §21.2 hardware matrix; the founder wants to design the
   incompatible-state UX as part of this.

Also shipped this session: a **Quit** control in the popover footer (the `LSUIElement` agent had no
Quit affordance) — `power` icon + ⌘Q, routed through `applicationShouldTerminate` so displays
neutral-reset on exit.

### Session-6 RESULTS (2026-06-17) — max-warmth ceiling decided (hybrid) + marketing evidence base

**The #1 task is resolved.** Ran a publication-grade circadian-research Workflow (12 primary-literature
finders → adversarial per-claim citation audit → synthesis → §13/FTC marketing compiler → skeptic
critic; 86 agents, 71 findings, **66 verified / 5 rejected**, 24-paper library). Full artifact:
`docs/research/max-warmth-circadian-research.md` (+ `.json`).

- **Science answer (Q1):** removing GREEN below ~1900K is a real-but-**negligible** additional melanopic
  reduction for sustained evening use — melanopsin/melatonin peak in the blue (Brainard 2001 464nm;
  Thapan 2001 459nm; CIE S 026 melanopic peak 490nm); the green primary (~550nm) carries s_mel ≈ 0.22
  and over a sustained evening the cone/green channel is only ~7% of suppression (St Hilaire 2022) and
  transient (Gooley 2010). Pure red collapses legibility for ~no circadian gain. **(Q2)** Practical
  maximally-protective target = deep amber **~1900K** (blue gain = 0), expressed properly as melanopic
  EDI ≤10 lux evening (Brown 2022) — CCT is not a valid circadian proxy (Esposito & Houser 2022).
- **Decision: HYBRID (Option A core + opt-in B).** Implemented & verified (91/21 tests, app BUILD
  SUCCEEDED, adversarial code-review pass applied):
  - `Kelvin.everydayWarmest = 1900` (new); `EngineConfiguration.defaultWarmestPoint` 500 → **1900K**
    (everyday slider max = blue-free). `Kelvin.warmestSupported = 500` stays as the absolute floor.
  - Default warmth strength **0.15 → 0.7** (out-of-box ~2412K; matches onboarding preview). Fixes the
    range-compression *and* a latent "default resolves to ~691K near-pure-red" bug.
  - **Opt-in "Expanded range"** control (Settings → Advanced): unlocks 1900K → 500K (pure red) for power
    users, with a hedged cited note. Pure-red is no longer on the everyday slider.
  - Fixed a **readout bug**: `AppModel.globalKelvin` hardcoded 2700K (disagreed with applied warmth) →
    now uses `state.warmestPoint`. Onboarding now sets nightly *strength*, not the ceiling. Warmest-point
    now **persists** across launches (focused slice of §25.B).
- **Marketing evidence base created** (founder directive — grounds launch/site/social/SEO/AEO):
  `docs/marketing/evidence-base.md` (verified claims + spectrum table + 24-paper citation library +
  DO-NOT-CLAIM + 4 binding guardrails) and `docs/marketing/messaging-and-campaigns.md` (positioning,
  taglines, web/social copy, SEO + AEO Q&A — §13/FTC-safe, all grounded in the evidence base).
- **Launch tracker created:** `LAUNCH.md` — living checklist of everything left to ship (engine/app,
  testing matrix, signing, public repo, site, marketing, SEO/AEO, social, launch day), founder-gates
  flagged. Keep it updated as items complete.
- **Critic's binding marketing guardrails:** couple "removes blue" with "lower brightness" (app doesn't
  dim; dose is intensity-driven); red = circadian-**sparing**, never photobiomodulation (imagery too);
  never juxtapose product claims with sleep-latency data; spectral/CCT numbers are illustrative, not
  measured product output.

---

## 26. Execution Log — Session 7 (2026-06-18): settings persistence + popover UX redesign

Founder-dogfooding session: one long iterative pass over the live app (23 build-repo commits,
`be62c78`→`d8c9ffa`). All steps verified **91/21 WarmthKit tests green + app BUILD SUCCEEDED**; the
persistence/naming/animation batches passed a separate-lane adversarial code-review (0 Critical/High).
The per-display redesign was designed via `/ask` (Codex gpt-5.5; Gemini CLI is dead — Google killed the
free tier). **Nothing pushed** — public repo is held on the founder gate until the look is signed off.

**Engine / WarmthKit:**
- **§25.B persistence COMPLETE** — `isEnabled` / `globalWarmth` / `scheduleMode` now persist to
  `UserDefaults` alongside `warmestPoint`, restored in `AppModel.start()` after `engine.start()` by
  replaying the setters. `object(forKey:)` guard preserves the 0.7 out-of-box default; `scheduleMode`
  is Codable JSON and self-heals a corrupt blob.
- **Per-display "Override" model (replaces the max-boost)** — new **`DisplayState.warmthOverridden`**.
  `reapply` applies a display's own `warmth` ONLY when overridden, else the global/schedule target → a
  TRUE override (softer *or* warmer). `setWarmth(_:for:)` implies override; new
  `setWarmthOverride(_:for:)` seeds the slider to the current global on enable. Carried across reconnect
  via `rememberedSettings`. Removed the now-unused `maxWarmth`. **Additive contract change — update
  `docs/engine/warmthkit-api-contract.md`.**
- **Reveal disabled when off** — `engine.beginReveal()` guards on `isEnabled`, so the ⌥⌘T hotkey is a
  no-op until warming is on.
- **Hotkey actually binds now** — `HotkeyService.installRevealHotkey()` was registering handlers but
  never assigning a shortcut (nothing fired). Sets **⌥⌘T** default on first launch (Carbon, no
  Accessibility permission). New public `RevealShortcutRecorder` (SwiftUI) for the Settings rebind.
- **OS-localized display names** — new `DisplayServices/DisplayNaming` maps `CGDirectDisplayID →
  NSScreen.localizedName` (main-actor hop, real-display path only via `injectedDisplays == nil`), so
  rows read "Built-in Display" / "LG UltraFine" instead of a generic "Display".

**App UI (the menu-bar popover, fully restyled):** real app icon + gear top-right in the header (status
text removed); the single **Kelvin readout moved inline onto the Warmth row** with an ⓘ tooltip; on-brand
**liquid-glass `WarmSlider`** (sunset-gradient track, springy glass thumb) + custom segmented
**`ModeControl`** (`Theme.Gradient.sunset`, dark-ink for contrast, sliding selection); **Mode moved to
the Advanced disclosure** ("Off" removed, "Follow sunset"→"Sunset"); the whole warmth block hides/reveals
with a `.smooth` no-blur animation when the master toggle flips; footer = `escape` quit (left) + reveal
hint (centre, hidden when off) + chevron advanced-disclosure (right). **Per-display control consolidated
to an "Override" toggle on the display rows** (slider hidden until on); the old "PER-DISPLAY OVERRIDE &
ENGINE" advanced section and ALL gamma/method jargon were removed from the popover. Tint-only honesty is
now plain-language ("Can only add a colour tint on this display").

**Still open (next session):** founder visual sign-off; de-jargon / relocate the gear **Settings** window
(still shows method badges + DDC/layer controls — move to a "Displays → Advanced" compatibility section);
contract-doc touch-up; §25.J app-level banner; §25.K hardware matrix; then the gated public push.

## 27. Execution Log — Session 8 (2026-06-18): settings de-jargon, popover swap, real Sunset

Founder-dogfooding wave on top of Session 7. **4 build-repo commits** (`d66265d`→`70c55fc`); all
verified **95/21 WarmthKit tests green + app BUILD SUCCEEDED**; one combined separate-lane code-review
(`APPROVE-WITH-NITS`, all findings applied). **Nothing pushed** — public gate held; founder visual
sign-off pending on the combined Session 7+8 Release build.

**Settings de-jargon (§26 #2 — DONE).** The gear Settings window dropped all engine jargon: removed
the per-display method badges + "Recommended: Gamma" and the raw "Enable private-API paths (DDC +
Night Shift follow)" toggle. **Settings → Displays** is now a plain-language compatibility view —
per-display status ("Truly warmed — removes blue light" / "Can only be tinted on this Mac…") + a
per-display **Advanced** disclosure with a warming-method picker using Codex's labels (**Automatic /
Standard / Screen tint / Hardware control** → engine `preferredMethod` nil/.gamma/.overlay/.hardware),
offering only the methods that display can use (so an incompatible display shows fewer options; the
option set itself tells the compatibility story). "Hardware control" is the explicit DDC opt-in
(enables `isHardwareDDCEnabled`). Settings → Advanced kill switch reworded to "Use advanced warming
methods". Removed the now-dead `MethodBadge`. `AppModel.setPreferredMethod` now updates
`preferredMethod` optimistically so the picker tracks taps. **Frozen contract doc** updated for the
additive `DisplayState.warmthOverridden` + `setWarmthOverride(_:for:)` (§26 #3 — DONE).

**Popover Mode↔Displays swap (founder).** The schedule **Mode** control moved OUT of the advanced
(chevron) expansion INTO the simple view (under the warmth slider, inside the master-toggle reveal
group); the per-display **Override** rows moved the other way, INTO the advanced expansion. The
tint-only test was hoisted from PopoverView to **`AppModel.isTintOnly`** as the single source of truth
shared by the app-level incompatibility banner (simple view) and the moved per-display rows.

**Sunset mode now warms at the user's REAL sunset + a ramp (founder ⭐).** A read-only architect
investigation found "Sunset" never computed a sunset: `ScheduleModeOption.followSunset` maps to
`.followSystemNightShift`, which follows Night Shift's on/off boolean and — when Night Shift is OFF
(the common case for an app that *replaces* it) — fell back to a **hardcoded 20:00→06:00 wall-clock
window**, not solar. A correct NOAA solar calculator already existed (`ScheduleResolver`) but was
unreachable from the UI and never fed coordinates (no CoreLocation, no timezone→coord logic). The fix:
- **`TimeZoneCoordinates`** (new, pure WarmthCore): ~100-zone IANA table → representative coords, with
  a UTC-offset-longitude fallback (DST-corrected to the standard meridian) for unlisted zones. **Zero
  permission, no network** — the founder's chosen approach over CoreLocation (keeps the no-permission
  positioning; ±~20 min vs the old fixed clock).
- **`ScheduleResolver.solarRampDecision` + `rampFactor`**: warmth eases in from solar elevation +6°,
  reaches full at the −0.833° sunset horizon, holds through the night, eases back at sunrise. The
  `.solar` case and the degrade path both use it.
- **`WarmthEngine`**: `reapply` feeds the live system-timezone coordinate (live mode only — hermetic
  tests pass nil so the fixed-window degrade stays deterministic); a **60s ramp ticker** (change-gated
  publish) advances the ramp over the evening, since Night Shift OFF emits no notifications.
- **Founder decision (review M1): Sunset ALWAYS uses the real-sunset ramp** when a coordinate is
  available (always, in production), **regardless of Night Shift** — Abendrot computes its own sunset
  rather than deferring to NS. The NS-follow / fixed-window path remains only as the no-coordinate
  fallback (hermetic tests, unresolvable zone), so all existing degrade tests are unchanged.

**"Schedule" (manual custom-time) mode dropped (founder).** It was an unbuilt stub (a hardcoded
provisional window, no editor). Mode is now **Sunset / Always on**. The engine's `.custom` case is
kept dormant (frozen-contract, still tested) so a real custom-schedule editor can return later with no
re-plumbing; `ScheduleModeOption.init` maps a persisted `.custom` → Sunset.

**Review (APPROVE-WITH-NITS) findings applied:** M1 above; M2 — the offset fallback now uses the
DST-corrected standard meridian; N1/N2/N3 — stale comments (4-mode list, removed-MethodBadge ref,
`.solar` dormancy note). Lows were by-design (mid-ramp Kelvin readout deliberately not surfaced,
defensive degenerate-window guard, two-Task hardware-control transition) — no change.

### Session 8 (cont., 2026-06-18) — §25.J notice, Settings polish, Sunset subtitle

A second founder-dogfooding pass the same day (4 commits `22de9ce`→`0eed892`; 95/21 tests green,
xcodebuild BUILD SUCCEEDED verified non-masked; separate-lane review `APPROVE-WITH-NITS`, §13 About
copy verified compliant, all 3 nits applied):
- **§25.J notice — working draft (founder-directed).** The app-level tint-only banner now names the
  real chip + macOS version (new permission-free `SystemInfo` sysctl helper, mirrors GammaBackend's
  brand-string read) + a tappable "Why?" plain-language, §13-safe explainer (notes an external monitor
  with its own controls can still be truly warmed). The About "Built for the newest Macs" bullet was
  softened so it doesn't overclaim against this notice. **Founder owns the final visual/copy.**
- **Settings slider-drag bug fixed:** `isMovableByWindowBackground = false` (was stealing the custom
  `WarmSlider`'s drag → the window moved instead of the slider; still draggable by the title-bar strip).
- **Shortcuts tab removed (founder):** the Reveal-True-Color `RevealShortcutRecorder` rebind moved
  under Settings → Advanced, below Maximum warmth.
- **About page rebuilt (founder):** real app icon via a new shared `AppIconView` (also used by the
  popover header) + mission + the every-display / free-OSS / private / newest-Macs angle + a §13-safe
  "The science" section grounded in `evidence-base.md` (review-verified: brightness-coupling guardrail
  satisfied; no banned claims).
- **Sunset rename (founder + dual-advisor `/ask`: analyst sub-agent + Codex).** Both converged: KEEP
  the "Sunset" label, fix descriptiveness with a one-line Mode subtitle ("Warms automatically around
  your local sunset." / "Warms continuously, day and night."). **"Circadian" rejected** on §13 grounds
  (implied physiological-effect claim + clinical voice); "Sunset Schedule" rejected (UI width / reads
  like setup, not a mode).
- **⚠️ Process lesson (durable):** the first §25.J build silently FAILED — `SystemInfo.swift` (a new
  app-target file) was not in the xcodegen-generated, **gitignored** `.xcodeproj`, and `xcodebuild |
  tail` masked the failure (the pipe's exit code was tail's, not xcodebuild's). FIX: new app files
  require **`xcodegen generate`** before `xcodebuild`; build commands now capture the real xcodebuild
  exit code and never pipe it into `tail`.

**Still open (next session):** founder visual sign-off on the combined build; §25.J final look
(founder-owned — working draft shipped); §25.K hardware matrix (now incl. Sunset-timing spot-checks);
wire the per-app-exclusions + reveal-during-captures stubs + the Hold/Toggle reveal-mode picker; then
the gated public push.

## 28. Execution Log — Session 9 (2026-06-19): fresh sign-off build + Hold/Toggle picker

Resume pass. Reconciled the repo against the docs first (evidence over assumptions): build repo on
`build`, HEAD `0861299`, tree clean except `.omc/state/*` orchestration churn; no remote; the umbrella's
`test-incompatibility-notice.rtf` is just the founder's saved §25.J preview command, not new direction.

- **⚠️ The Release build was STALE — rebuilt.** `build/Release/.../Abendrot.app` was dated **Jun 18
  02:17**, which *predates the entire Session-8 wave* (de-jargon, Mode↔Displays swap, real-Sunset ramp,
  §25.J notice, slider-drag fix, About rebuild, Sunset subtitle). So the founder's #1 "visual sign-off"
  would have been on a binary missing the very things to sign off on. Rebuilt fresh from HEAD: `xcodegen
  generate` → Release **BUILD SUCCEEDED** (verified non-masked; real `Ld` for both arm64 + x86_64), **95/21
  WarmthKit tests green**. The sign-off build now genuinely contains all of Session 7+8.
- **Wired the Hold/Toggle reveal-mode picker (§3 locked "ship both, default hold") — the one clean §4
  stub.** Backing behaviour already existed and is live: `HotkeyService.mode` drives hold vs toggle in
  `handleKeyDown/Up`. Added only the surface: a segmented picker in Settings → Advanced (under the reveal
  rebind), `AppModel.revealMode` + `setRevealMode`, and `UserDefaults` persistence restored in
  `applyPersistedState()` (fresh install keeps hold). Cleared the `SettingsView` + now-satisfied
  `HotkeyService` TODOs. Separate-lane code-review: **APPROVE-WITH-NITS** (0 blocking; both one-line nits
  applied). Commit `9adf15f`.
- **Per-app exclusions — BUILT this session (founder greenlit it as in-scope for 1.0).** Dispatched to a
  background executor (opus) against a precise spec, then reviewed + independently re-verified in a
  separate lane (**APPROVE-WITH-NITS**, all nits applied incl. a change-gate test). While an excluded app
  is frontmost the engine suspends warmth (true colour) across all displays, **composing with** (not
  clobbering) hold-to-reveal. The membership check is **engine-owned** (new `setFrontmostApp` + a
  change-gated `isExcludedAppFrontmost` folded into `engineOn`) → resolves contract **open-Q3**; the app
  layer is a thin `NSWorkspace→engine` bridge (`FrontmostAppMonitor`, mirrors `HotkeyService`). The set
  persists (§25.B) and drives a native "Add app…" `NSOpenPanel` picker in Settings → Advanced. Frozen
  `WarmthState` untouched. **101 tests / 22 suites** (6 new). Commit `7548e17`. Known minor edge (founder
  review): opening the popover over an excluded app leaves warmth suspended (arguably correct — that app
  is still the real foreground).
- **Reveal-during-captures — deferred (NOT built).** Overlay-only (gamma/DDC warm the real framebuffer,
  so a `sharingType` flip can't reveal those) **and** auto-suspend is **out of scope for v1.0 per frozen
  contract §10**. Founder call whether the narrow overlay-only manual toggle is worth shipping at all.
- **Nothing pushed** — public gate held.

**Still open (next session):** founder visual sign-off on the now-fresh combined build (incl. the new
Hold/Toggle picker **and** the exclusions picker); §25.J final look (founder-owned); §25.K hardware
matrix; reveal-during-captures is the last §4 stub (likely drop per §10); then the gated public push.

## 29. Execution Log — Session 9 (cont., 2026-06-19): founder dogfooding wave

A long live-dogfooding pass on top of §28. Every change executed, verified (Release **BUILD SUCCEEDED**
+ **102/22 WarmthKit tests** throughout, non-masked), and committed locally; **nothing pushed** (public
gate held). Heavy execution dispatched to **codex (gpt-5.5 xhigh)** per the founder's directive, with
design/engine judgment kept in the lead session and separate-lane reviews on the substantive batches
(APPROVE / APPROVE-WITH-NITS, all applied). Build-repo `7bff1f6`→`c7da422`.

**UI review batch.** Per-display **warming-method picker** de-cluttered: dropped "Automatic" (redundant)
→ **Standard / Screen tint** (+ Hardware control where DDC-capable), on the **brand liquid-glass segmented
switcher** (generalized `ModeControl` → reusable `BrandSegmentedControl`); Advanced disclosure centered;
the per-method description line removed (redundant with the subtitle). **Subtitle honesty:** per-display
status now reflects the chosen method (Screen tint no longer reads "Truly warmed"; text+colour
single-sourced). **Tint-slider fix:** overlay `veilAlpha` scales into the 0.5 cap instead of clamping
early, so the warm half of the slider is perceptually distinct (2625K ≠ 1900K). **§25.J / tint-only:**
concise summary + hover tooltip instead of truncated text + a warning glyph on the popover tint-only rows.

**Congruency + Settings.** Per-display **Override + custom-warmth** added to Settings → Displays → Advanced
(mirrors the popover; Settings = superset), then **Override moved below the warming method** (founder).
Settings **sidebar non-collapsible** + a **branding footer** (icon + Abendrot + "Built by Matthew Ball" →
matthewball.me, shared `BylineLink`: underline + hover + link cursor); same byline on **About** (replacing
the "Soften into the evening" tagline — kept as the onboarding CTA + brand-voice line, never a Top-3
marketing tagline). Popover **"Per-app exclusions"** row → **"Manage…"** deep-links to Settings → Advanced
(`AppModel.settingsTab` bound to the sidebar). **Restore** now disables Abendrot (`setEnabled(false)` +
neutral so the ramp can't re-warm) and was **relocated** from Displays to Advanced (declutter; keeps the
forceful DDC/emergency reset).

**Manual location override for Sunset (founder, no permission).** Settings → Schedule **"Location"** — Auto
(from time zone) by default, or a **96-city liquid-glass autocomplete** (glass search field + dropdown,
prefix-then-contains diacritic-insensitive filter, sunset-accent selection) — with a live **"Today's sunset
≈ X:XX PM"** readout. Engine: `setUserCoordinate` folds into the solar reapply (`box.userCoordinate ??
TimeZoneCoordinates.current()`), persisted; new public `ScheduleResolver.sunsetTime`. Motivated by the
timezone-coord error (LA representative coord = 27 min early for an SF user, validated by a standalone NOAA
probe vs the app); founder accepts the early-warming bias as desirable. The genuine going-forward gap is
huge single-time-zone countries (China = up to ~2h); a manual override covers it. Frozen `WarmthState`
untouched. (Autocomplete now has full ↑/↓/Enter/Esc keyboard nav + a compact 3-row dropdown sized so it
doesn't clip on a small Settings window; Settings also opens taller by default.)

**Two founder-reported bug fixes.**
- **Settings window wouldn't reopen** after close: the gear used SwiftUI `openSettings()`, routed through a
  hidden 1×1 Settings-scene window that LINGERED → a second open found it present, `onAppear` never re-fired
  → no window (+ popover flicker). Fix: the gear calls `SettingsWindowController.show()` directly; the ⌘,
  bridge closes its host window after launch.
- **Built-in warms late** (up to 60s): only the 60s ramp tick re-asserted, so a built-in macOS resets (True
  Tone / ambient settling after login/wake) or that enumerates late waited a full tick. Fix: a **catch-up
  re-assert burst** at ~1/3/6/12s after start / wake / reconfiguration (`reapply` re-writes the backend each
  pass — confirmed no skip-if-unchanged — so it overcomes an external reset; live-mode-guarded, cancelled on
  shutdown). *Founder to verify on hardware.*

**Still open:** founder visual sign-off on the combined build; **reveal-during-captures** options (overlay-
only — gamma/DDC can't be hidden from captures; pending founder steer); Kelvin-readout font (recommend keep
the New York serif — the deliberate brand accent, §5.1);
**§25.K hardware matrix** (binding before 1.0; now incl. the catch-up re-assert + Sunset-timing checks);
then the **gated public push**.

---

*Status: ✅ APPROVED for execution (2026-06-16). All decisions locked; §21.6 staged-beta strategy confirmed. **§25 warming overhaul + max-warmth ceiling: DONE (Session-6, hybrid).** Execution proceeds in `/Users/ball/Documents/abendrot` via `/team` across the §15 lanes, with heavy backend dispatched to Opus 4.8 `/goal` (max effort) and the hardest engine logic retained in the lead session. See `RESUME-PROMPT.md` to start the execution session.*
