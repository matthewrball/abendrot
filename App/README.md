# Abendrot — App (Lane B)

The SwiftUI + AppKit macOS **menu-bar app**. It is the structural first pass of the UI
(popover · advanced expansion · Settings · onboarding), wired to the engine **only**
through the FROZEN `WarmthKit` contract (`docs/engine/warmthkit-api-contract.md`).

> **Status:** STRUCTURAL pass. Final brand polish (real icon, motion polish, "wet
> glass" specular/lens treatment) is intentionally deferred to a later
> `/design-motion-principles` + brand-lock pass (plan §5.5 / §21.4). Hooks and
> `TODO(brand-lock)` / `TODO(settings)` / `TODO(milestone)` markers are left explicit,
> never faked.

## Generate the Xcode project

The app is built from `project.yml` (XcodeGen) at the repo root. The generated
`Abendrot.xcodeproj` is a **build artifact** (git-ignored) — `project.yml` is the
source of truth.

```sh
brew install xcodegen      # one-time
xcodegen generate          # run from the repo root; regenerate after editing project.yml
open Abendrot.xcodeproj     # then build/run the `Abendrot` scheme (Xcode 26 / macOS 26)
```

- Target: `Abendrot`, a macOS **application**, `LSUIElement` (agent app — no Dock icon,
  no Cmd-Tab), deployment **macOS 26 "Tahoe"**, Swift 6 **strict** concurrency.
- Links the local `./WarmthKit` package and depends on the umbrella **`WarmthKit`**
  product only (the app talks to `WarmthEngine`, never the backends).
- Builds **unsigned/local** — no Apple Developer account needed for development.
- The scheme name `Abendrot` matches `.github/workflows/ci.yml` (`ABENDROT_APP_SCHEME`).

## What compiles today vs. what's deferred

- **The app UI compiles against the FROZEN contract.** Verified by type-checking every
  `App/Sources` file against the contract's public value types + `WarmthEngine` /
  `HotkeyService` signatures under Swift 6 strict concurrency (macOS 26 toolchain).
- **The live `WarmthKit` engine does not build green yet** (Lane A in progress — a
  `DisplayServices` symbol resolution is outstanding). This is expected and the UI does
  **not** block on it: the app links the contract surface, and every SwiftUI `#Preview`
  renders from `MockWarmthState` (real, public, Sendable value types — no live engine).
  Once Lane A is green, `xcodegen generate` + build links the real engine with no app
  changes required.
- **Full app build** (the `.xcodeproj` archive) requires full **Xcode 26** + XcodeGen on
  the build machine; it was not runnable in the authoring environment (Command Line
  Tools only). CI (`build-app-unsigned`) compiles it on the `macos-26` runner once the
  project is generated.

## Architecture (one-way data flow)

```
WarmthEngine (actor, WarmthKit)
   │  stateUpdates() : AsyncStream<WarmthState>
   ▼
AppModel (@MainActor @Observable)  ──intents──►  await engine.set…()
   │  state : WarmthState
   ▼
SwiftUI views (PopoverView · AdvancedExpansion · SettingsView · OnboardingView)
```

- `ViewModel/AppModel.swift` — owns the `WarmthEngine` + `HotkeyService`, consumes
  `stateUpdates()`, turns view intents into `await engine.…` calls. Optimistic UI (no
  spinners). A `previewState:` initializer seeds a mock state without a live actor.
- `Theme/` — `Theme.swift` maps `brand/tokens.json` to Swift (colours via
  `Resources/Colors.xcassets`, **no hardcoded hex in views**); `GlassSurface.swift` is
  the Liquid-Glass material with the ember-tinted **SOLID** Reduce-Transparency fallback
  (never grey).
- `Views/` — popover, advanced "liquid expansion", shared components, mode control,
  provisional sunset-arc glyph.
- `Windows/` — programmatic `SettingsWindowController` (NOT a SwiftUI `Window` scene —
  glass chrome needs `.fullSizeContentView` at creation) hosting `SettingsView` (tabs
  General / Schedule / Displays / Shortcuts / Advanced / Privacy / About).
- `Onboarding/` — "3 clicks to warmth" (notifications → max warmth → confirm schedule).
- `Services/AppActivationPolicy.swift` — reference-counted `.accessory`↔`.regular`
  helper so the menu-bar-only app foregrounds windows correctly.

## Regenerating the colour asset catalog

`Resources/Colors.xcassets` is generated from `brand/tokens.json` (dark + light
variants). If the tokens change, regenerate the colorsets rather than hand-editing —
keep the asset catalog the single mapping point (see the brand-lock workstream).

## Contract gaps

The integration found **no missing public API** for the structural pass — every screen
maps onto an existing `WarmthEngine` method or `WarmthState`/`DisplayState` field. Items
to confirm with Lane A (engine), none of which block this pass:

1. **Reveal veil ownership.** The reserved-white "lift the veil" surface is rendered by
   the engine's `OverlayBackend` going to true colour on `beginReveal()`. The app does
   **not** draw a competing veil window. If the product wants an app-side accent flourish
   layered over the engine reveal, that needs a new (additive) hook — not assumed here.
2. **Warmest-point readout.** `WarmthState` does not publish the current warmest point,
   so the popover/Settings derive the Kelvin readout against the contract default
   (`Kelvin(2700)`). If the UI should reflect a user-customised warmest point live, an
   additive `warmestPoint` field on `WarmthState` would let the readout track it.
   (Listed as open question §11.1 in the contract.)
3. **Per-display method override readback.** `setPreferredMethod(_:for:)` accepts `nil`
   for "automatic", but `DisplayState` exposes only `appliedMethod` — there is no flag
   distinguishing "user forced this layer" from "engine chose it automatically". The
   advanced menu therefore always offers "Automatic" plus the supported layers; it can't
   show a checkmark on the *current override*. An additive `preferredMethod: DisplayMethod?`
   on `DisplayState` would let the menu reflect the override state.
4. **Schedule times for display.** The popover/onboarding would like to show the resolved
   "Begins 7:14 PM → 5:48 AM" line from the mockups; `WarmthState` exposes
   `isScheduleActiveNow` but not the resolved start/end instants. Additive resolved-times
   fields would let that copy be real instead of omitted. (Omitted for now, not faked.)

All four are **additive** (new optional fields/params) and explicitly allowed by the
contract freeze policy (§11). None require engine-internal access.
