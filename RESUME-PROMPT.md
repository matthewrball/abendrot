I'm resuming **Abendrot** — a free, open-source, native macOS menu-bar app that warms screen color temperature across **every** display (built-in + external) for circadian health, with a hold-to-"Reveal True Color" hotkey and a Liquid Glass UI. MIT, auditable, zero-telemetry-by-default. Canonical home: **`/Users/ball/Documents/abendrot`** — the **PRIVATE build repo** (branch `build`), which holds the full plan + research and is **never pushed**.

## Read these first, in full, before continuing the build
1. `HANDOFF.md` — full context, locked decisions, gotchas, the "Session continuity" + "Session 3 state" notes.
2. `docs/abendrot-plan.md` — the master plan. Read it, especially the **§22 Execution Log** (latest state at the bottom), §6 + §21.1 (engine), §8 (QA), §9 + §21.2 (release).
3. `docs/engine/warmthkit-api-contract.md` — the FROZEN engine API contract the app builds against.
4. Skim: `brand/tokens.css` (the current icon-derived **sunset** palette), `docs/qa/` (failure-injection + hardware matrix + acceptance gates), `docs/engine/system-layers-notes.md`, `docs/research/` (sweeps, CCG audit, reference-macos-app-skills).

**The plan is APPROVED and execution is well underway.** This handoff captures a long, productive session; pick up from the plan + the status below.

---

## STATUS — what's built and verified (as of 2026-06-17)

**Engine — `WarmthKit/` (SPM package, Swift 6 strict concurrency, builds on Xcode 26.5; `swift test` → 81 tests in 20 suites pass):**
- Frozen public API contract; module split `WarmthCore` (pure) / `DisplayServices` / `HardwareDDC` / `OverlayRenderer` / `NightShiftBridge` / `CInterop` / `WarmthKit` umbrella.
- **Real (implemented + tested):** `WarmthCore` value types, Kelvin↔RGB-gain blackbody math (golden-anchor tested), schedule resolver (custom/solar/follow), `DisplayIdentity` keying, `LayerResolver` (overlay-default / DDC-opt-in / kill-switch enforcement), schedule-degrade policy (follow→evening fallback so the default actually warms), the `WarmthEngine` actor (coordination + `AsyncStream` state, correct actor isolation).
- **M0 OverlayRenderer (real):** per-`NSScreen` borderless click-through veil from `rgbGain`. NOTE: uses an **alpha-blended warm tint**; a true per-channel multiply (blacks-stay-black, needs a Metal layer reading the framebuffer) is the plan §18 follow-up. On-screen visual confirmation still pending (run the app).
- **M7 (real):** `DisplayReconfigurationObserver` (CG reconfiguration) + `SystemWakeObserver` (NSWorkspace) → debounced re-baseline in `WarmthEngine.start()`.
- **Night Shift follower (real):** read-only `CBBlueLightClient` via runtime symbol resolution (CInterop ABI fixed); degrades cleanly when unavailable / kill-switch engaged.
- **Gamma (classification + real apply/reset):** `.unsupported(.gammaBrokenOnThisOS)` on Apple-Silicon+macOS26; real `CGSetDisplayTransferByTable`/restore reachable only via explicit override.
- **M2 DDC (real — the last engine layer):** `HardwareDDC` is no longer a stub. Real dlsym-resolved IOAVService DDC/CI write path: `DDCProtocol` (pure VCP packet/checksum/reply layer, golden-vector tested), `IOAVServiceBus`/`Provider` (IORegistry→`DCPAVServiceProxy` resolution, `Location=="External"` + `transport != .builtIn` gates so built-in panels are NEVER DDC'd), `IOAVServiceDDCTransport` actor (serialized per-service transactions, native-gain snapshot, relative warming `native×gain`, write-then-read verify + retry/backoff, restore with aggregate verify), `DDCSnapshotStore` (file + in-memory). Engine: launch-time stale-state recovery (reset-to-native before any apply), write-ahead dirty flag, honest DDC→overlay fallback (no false Hardware badge), settings retained across hotplug. Opt-in per display; overlay stays the floor. **The wire protocol is reconciled byte-for-byte from m1ddc + MonitorControl (see `docs/engine/ddc-protocol-spec.md`) and is certain; but DDC CANNOT be verified headlessly → a founder real-external-monitor pass is the one remaining gate before claiming it works.** Adversarially reviewed (separate lane): protocol clean, fixed a critical actor-reentrancy bug + a medium restore-verify bug.
- **NightShiftBridge crash fixed (critical, surfaced by M2 tests):** the `setStatusNotificationBlock:` block was non-escaping but CoreBrightness retains it → the app would have **crashed at launch** the first time `start()` ran with a live `CBBlueLightClient`. Now `@escaping`. (The app was built but never run, so it was latent.)
- **No engine layer is stubbed anymore.** Remaining engine follow-ups: the true per-channel-multiply overlay shader (§18) and the live real-hardware DDC pass.

**App — `App/` (SwiftUI + AppKit menu-bar agent, LSUIElement; builds via `xcodegen generate && xcodebuild`):**
- `MenuBarExtra`, simple popover, advanced "liquid expansion", programmatic Liquid Glass Settings, "3 clicks to warmth" onboarding, hide-from-bar, reveal wiring, `.terminateLater` quit reset, `SMAppService` login, Sparkle Info.plist keys.
- **AppIcon wired + verified baked into the built `.app`** (the sunset-glass icon). Talks to the engine only via the frozen contract; `WarmthKit` re-exports `WarmthCore` (`@_exported`); colors come from `App/Resources/Colors.xcassets` (no hardcoded hex).

**Icon + brand (NEW direction this session):**
- Founder supplied `assets/abendrot-iteration3.png` → masked transparent corners → **`assets/abendrot.png`** (1024 master) → full retina iconset → **`assets/abendrot.icns`** → `App/Resources/Colors.xcassets/AppIcon.appiconset`. Re-runnable: **`python3 scripts/icon/build-icons.py`** (swap the master + re-run to refresh everything).
- **Brand pivoted to an icon-derived SUNSET palette** (founder calls it "maybe temporary"): warm near-black grounds `#160A12`/`#221019`/`#341320`, accent ramp golden-sun `#FD9228` / highlight `#FFC061` / orange `#FB7C0E` / deep ember `#C2310A`, plus a signature `--sunset-sky` gradient. Applied + build-verified across: `brand/tokens.{css,json}`, the app's 19 `Colors.xcassets` colorsets (dark+light, `RevealTrueWhite` reserved), the landing page (which now leads with a full cinematic **sunset hero** — the icon's sky + a golden sun cresting a lit horizon + the app-icon glyph; build-verified, AAA text contrast, the cool↔warm demo's cool side preserved), and the coming-soon site.

**Release / CI — `scripts/`, `.github/workflows/ci.yml`:** two-mode pipeline (unsigned-local default / signed-notarized gated on later creds), CI **GREEN** on the public repo (after fixing the runner Xcode path + advisory lint + the `Bundle.module`/`@_exported` app-build bugs).

**Content/QA — `docs/marketing/`, `PRIVACY.md`, `docs/qa/`:** conversion README draft, privacy policy, cited non-medical science, launch copy; failure-injection suite + hardware matrix + acceptance gates (design; live runs pending real backends + hardware).

**Public repo — github.com/matthewrball/abendrot (PUBLIC, MIT, clean single-commit history, planning fully scrubbed/hidden):** contains WarmthKit + App + project.yml + ci.yml + scripts + PRIVACY + LICENSE/README/CONTRIBUTING/SECURITY. **It is BEHIND the private repo** — it does NOT yet have the icon, the new sunset palette, or the M7/Night Shift/gamma engine work. A **re-publish** is needed (founder's push gate).

---

## Locked decisions (this session)
- **Signing DEFERRED** — no $99 Apple Developer account yet. Build/test/hardware-matrix run **unsigned/local**; the mode-A signed+notarized pipeline is ready, gated behind later-supplied creds. Don't hard-claim "notarized" in pre-release copy.
- **Binaries → GitHub Releases**; landing → **abendrot.app**.
- **Two-repo model:** this dir = private build repo (full planning, never pushed); **github.com/matthewrball/abendrot** = clean public repo (no planning in history). Any public push MUST be re-scrubbed of planning "tells" (§/plan/Lane/CCG/brand-lock/[FLAG]/internal-doc refs) — a clean export was built at `/Users/ball/Documents/abendrot-public`.
- **Brand = the icon-derived sunset** (maybe temporary; revisit if the icon changes).
- **Xcode MCP** (`xcrun mcpbridge`) registered at **user scope** + the Xcode Intelligence toggle is ON. Its tools load at session START — a fresh session can build/launch/diagnose the app via the MCP.

## Environment / how to build
- **Full Xcode 26.5 installed, license agreed.** `swift build`/`swift test` work end-to-end.
- Engine: `cd WarmthKit && swift test` (53 tests).
- App: `export PATH=/opt/homebrew/bin:$PATH && xcodegen generate && xcodebuild -project Abendrot.xcodeproj -scheme Abendrot -configuration Debug -derivedDataPath build/DD CODE_SIGNING_ALLOWED=NO build` → `** BUILD SUCCEEDED **`.
- Tools present: `xcodegen` (brew, /opt/homebrew/bin), `Pillow` (pip --user), `sips`, `iconutil`.
- The generated `Abendrot.xcodeproj`, `build/`, `.build/`, `node_modules/`, `dist/` are git-ignored build artifacts.

## NEXT — continue the build (in priority order)
0. **⭐ #1 — WARMING-MECHANISM OVERHAUL (do this first, fresh session). See plan §25 + `docs/engine/overlay-multiply-decision.md`.** Founder's first-run verdict: enabling warmth "just adds a white tint, doesn't truly warm like BetterDisplay Pro." Root cause is understood: the engine defaults to the **overlay**, which can only wash amber on top (source-over alpha) — it can't remove blue. **True warming = gamma LUT (built-in) / DDC gain (external).** First settle the pivotal unknown: gamma is hard-classified broken on Apple-Silicon+macOS26 *by assumption* and never tested on this Mac — bypass `GammaClassifier` and **visually test gamma on the founder's hardware**. Then research **how BetterDisplay/f.lux truly warm the built-in display on Tahoe** (study like m1ddc; likely CoreDisplay private APIs → kill-switchable), research the **blue-light/melanopic benefit** (value prop + §13/§14.1 content), and make `recommend()`/`LayerResolver` prefer **gamma/DDC** as the active warm path with overlay demoted to the floor.
1. **M2 DDC real-external-monitor pass with the founder** (headless can't prove it; also part of #0's external-display warming). Opt into Hardware DDC on a real DDC monitor and verify: capability probe, warm gain visibly applies, write-then-read verify, restore-to-native on toggle-off/quit, crash/SIGKILL → relaunch restores native (the §21‑E14 `HW` variants). Protocol math is locked (`docs/engine/ddc-protocol-spec.md`); confirm read-offset `0` and tune timing if needed.
2. **Re-publish the public repo** (icon + sunset palette + M7/NightShift/gamma + **M2 DDC + the night-shift launch-crash fix**) — re-scrub planning tells, then push. **Founder's gate.**
3. Live failure-injection + the self-hosted hardware matrix runs (docs/qa) — the `UNIT+FAKE` halves now pass headlessly; the `HW` halves need the real-monitor pass.
4. Full in-app motion/polish pass via `/design-motion-principles`. (§18 overlay multiply is RESOLVED: not achievable permissionlessly — the overlay stays an alpha tint; multiply = gamma/DDC.)
5. Cosmetic public-repo polish (social-preview image + website link) once assets exist.
6. Landing deploy to abendrot.app (Vercel) — **founder's gate**. (Integrate the §14.1 SEO/AEO engine before 1.0.)

## Open tasks (the in-session task tracker does NOT survive /clear — these are the live ones)
- **⭐ #1 — Warming-mechanism overhaul (plan §25): make warmth truly remove blue (gamma/DDC), not just an overlay tint. Founder's top issue. Fresh session.**
- Engine: M2 DDC real-hardware verification with the founder (also feeds #1's external-display warming).
- Lane G / QA (cross-cutting, never self-approve): the `HW` halves of failure-injection + the hardware matrix (need a real external DDC monitor).
- Re-publish the public repo (now also carries M2 + the night-shift crash fix); cosmetic repo polish; landing deploy — all founder-gated.
- Future (tabled): the §14.1 SEO/AEO content & AI-visibility engine — integrate with the site before 1.0.

## Founder gates — ASK before doing any of these
Re-publishing / pushing to the public repo; deploying the landing live to abendrot.app; posting anything externally (Product Hunt / HN / Reddit / social / awesome-list PRs).

## Gotchas / continuity
- **Localhost preview servers are ephemeral.** Re-serve: brand `python3 -m http.server 8733 --directory brand`; coming-soon `... --directory /Users/ball/Documents/abendrot-site`; landing `cd landing && npm run build && python3 -m http.server 8752 --directory dist`.
- **Browser cache** bit us once — to verify a re-skin, check the served bytes (`curl`) and/or use a fresh port.
- The icon reference + master + the reproducible pipeline: `assets/abendrot-iteration3.png` (source), `assets/abendrot.png` (master), `scripts/icon/build-icons.py`.
- macOS 26 auto-applies the squircle mask at compile; we ship the pre-rounded icon with transparent corners (it renders as-is).
- Private-API paths (IOAVService, CBBlueLightClient) can't be runtime-verified headlessly — they degrade cleanly; verify on real hardware.

## First action in the new session
Read `HANDOFF.md` + `docs/abendrot-plan.md` (§24 is the latest log) + the engine contract + `docs/engine/ddc-protocol-spec.md`, confirm the build is green (`cd WarmthKit && swift test` → 81 in 20 suites; then `xcodegen generate && xcodebuild ... build` → BUILD SUCCEEDED). **All five engine layers are now real (overlay/gamma/Night Shift/M7/M2 DDC).** The next big step needs the founder + a real external DDC monitor (the M2 hardware pass — DDC can't be verified headlessly). Otherwise: the §18 true-multiply overlay shader, then the founder-gated re-publish/deploy. Keep design taste + hardest engine logic in the lead session; dispatch heavy/parallel work to Opus subagents; verify in a separate lane (never self-approve); commit per protocol (private repo only — public pushes are founder-gated).
