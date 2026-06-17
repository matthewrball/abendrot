# WarmthKit Scaffold — Build Notes (Lane G)

Date: 2026-06-16. Scaffolds the FROZEN engine API contract
(`docs/engine/warmthkit-api-contract.md`) into a compilable Swift package. The pure
`WarmthCore` is implemented for real; the system/private layers are stubs that match the
contract's public API exactly.

## Environment

- `swift --version`: Apple Swift 6.3.2 (swiftlang-6.3.2.1.108), target `arm64-apple-macosx26.0`.
- macOS 26.5 (build 25F71).
- **No full Xcode is installed** — only the Command Line Tools. `xcode-select -p` →
  `/Library/Developer/CommandLineTools`; `xcodebuild` is unavailable; the active SDK is the
  CLT `MacOSX.sdk`.
- `.macOS("26.0")` platform and Swift 6 language mode are accepted as-is — **no change to the
  Package.swift platform or language mode was needed.**

## Build results

| Target | Result |
|---|---|
| `WarmthCore` (pure core) | **Builds clean** under Swift 6 strict concurrency |
| `CInterop` (C shim) | **Builds clean** |
| `DisplayServices` | **Builds clean** |
| `HardwareDDC` | **Builds clean** |
| `OverlayRenderer` | **Builds clean** |
| `NightShiftBridge` | **Builds clean** |
| `WarmthKit` (umbrella) | Source **type-checks clean** in isolation (see below); the full
  package build of this target fails **only** inside the third-party `KeyboardShortcuts`
  dependency, not in our code |
| `WarmthCoreTests` | **26 tests / 7 suites — all pass** (see below) |

### The one thing that can't be verified here: `swift build` / `swift test` end-to-end

`swift build` and `swift test` both build the *entire* package graph, which includes the
`KeyboardShortcuts` 2.4.0 dependency. That dependency's `Sources/KeyboardShortcuts/Recorder.swift`
(lines 172/177/182) uses the SwiftUI `#Preview` macro, which expands via the Xcode-only
`PreviewsMacros` compiler plugin. The Command Line Tools SDK **does not ship that plugin**, so:

```
error: external macro implementation type 'PreviewsMacros.SwiftUIView' could not be found
       for macro 'Preview(_:body:)'; plugin for module 'PreviewsMacros' not found
```

This is purely an **environment gap** (CLT SDK vs full Xcode), not a contract or code defect,
and it sits **downstream of our code** in the dependency graph. No in-range KeyboardShortcuts
version (2.2.0–2.4.0) avoids the `#Preview` usage. The contract's compile gate explicitly
targets **Xcode 26 / macOS 26**; on a machine with full Xcode 26 installed, `swift build`
and `swift test` are expected to pass for the whole package. We did **not** vendor, patch, or
downgrade the dependency, and did **not** weaken the contract to work around it.

### How the umbrella and core were verified despite the gap

1. **Per-target builds** — every target that does not depend on KeyboardShortcuts was built
   directly with `swift build --target <T>` and all compiled clean (table above).
2. **Umbrella type-check** — `WarmthKit`'s three sources (`WarmthEngine`, `HotkeyService`,
   `EngineTypes`) were `swiftc -typecheck`'d (Swift 6, `-package-name warmthkit`) against the
   real built `WarmthCore`/`DisplayServices`/`HardwareDDC`/`OverlayRenderer`/`NightShiftBridge`
   modules plus a minimal stand-in for the *exact* subset of the KeyboardShortcuts public API
   that `HotkeyService` uses (`KeyboardShortcuts.Name(_:)`, `onKeyDown(for:)`, `onKeyUp(for:)`,
   matching the real signatures). Result: **clean, zero errors.** This isolates our umbrella
   from the dependency's macro problem and proves the §6/§8 surface compiles under strict
   concurrency.
3. **Tests** — `WarmthCore` + `WarmthCoreTests` were compiled into a standalone Swift Testing
   runner (the CLT ships `Testing.framework` + `libTestingMacros.dylib`, just not on the
   default search path) and executed:

   ```
   Test run with 26 tests in 7 suites passed after 0.004 seconds.
   ```

   This bypasses the package's KeyboardShortcuts dependency for the test target (the test
   target depends only on `WarmthCore`).

## Two real bugs found and fixed during the umbrella type-check

Both were in our own umbrella code, surfaced by the strict-concurrency type-check:

1. `WarmthEngine.init` (a nonisolated actor init) constructed `OverlayBackend()`, whose init
   was `@MainActor`-isolated → "call to main actor-isolated initializer in a synchronous
   nonisolated context." Fix: made `OverlayBackend.init()` `nonisolated` (it only initializes a
   dictionary literal; AppKit windows are still created later on the main actor in
   `apply`/`reset`). The type stays `@MainActor` for all window-owning behavior.
2. `WarmthEngine.recommend(...)` declared its `hardware` parameter as `Capability<DDCColorCaps>`
   but was called with the `Capability<Void>` returned by `WarmthBackend.classify`. Fix: the
   parameter is `Capability<Void>` (the recommender only inspects the overlay capability anyway).

## Contract deviations (all additive — no public signature changed)

The contract's PUBLIC signatures are matched exactly. The following are **additive** changes
required to make the contract-as-written compile under Swift 6; none remove or rename anything
in the frozen surface, so they are within the "additive changes are allowed" freeze policy.

1. **Public initializers added to public structs.** The contract shows several public structs
   with public stored properties but no explicit `init` (e.g. `CustomSchedule`,
   `EDIDFingerprint`, `DDCColorCaps`, `DisplayCapabilities`, `DisplayIdentity`). A struct's
   memberwise init is `internal` by default, so cross-module construction (Lanes B/D) requires
   an explicit `public init`. Added public inits matching the stored properties. No property
   names/types changed.

2. **`DisplayIdentity` custom `Equatable`/`Hashable`.** The contract requires equality/hashing
   keyed on `cgUUID` (+ `edid`) with the transient fields excluded. Swift's synthesized
   conformance would include every stored property, so `==` and `hash(into:)` are hand-written
   to use only `cgUUID` and `edid`, exactly as the contract's prose mandates.

3. **`DisplayState.==` hand-written.** `DisplayState` is declared `Equatable` and contains a
   `DisplayCapabilities`, which contains `Capability<Void>` values. `Void` is not `Equatable`,
   so `Capability<Void>` cannot be `Equatable` and `DisplayState` cannot synthesize `==`. The
   hand-written `==` compares the public scalar fields plus the capabilities' identity and
   `recommendedMethod` (the equatable projection). This preserves the contract's
   `DisplayState: Equatable` requirement without forcing an `Equatable` `Capability`.

4. **`WarmthBackend` placed in `WarmthCore`.** The §5 `package protocol WarmthBackend` lives in
   `WarmthCore` so all backend modules can conform to it and the umbrella can store the three
   backends behind it (the protocol's `package` access makes it visible across the package,
   invisible to the app). The contract doesn't pin which module owns it; `WarmthCore` is the
   natural home (it already owns the value types the protocol references). The `package`
   access level from the contract is preserved verbatim.

5. **`import ColorSync` and `import CoreGraphics` in `WarmthCore`/`DisplayServices`.** The §3
   `DisplayIdentity` type (which must live in `WarmthCore`) uses CoreGraphics types
   (`CGDirectDisplayID`, `CGRect`, `CGFloat`) directly per the contract, so `WarmthCore`
   imports `CoreGraphics`. `DisplayServices` additionally imports `ColorSync` because
   `CGDisplayCreateUUIDFromDisplayID` is declared in the ColorSync framework on modern macOS
   SDKs (the contract already lists ColorSync as a `DisplayServices` dependency). The contract's
   "WarmthCore knows Foundation + Logging only" note is honored in spirit — no AppKit/IOKit —
   but CoreGraphics is unavoidable because the frozen `DisplayIdentity` fields are CoreGraphics
   types.

## What is real vs stubbed

- **Real (pure, Sendable, no AppKit/IOKit):** all §2 value types; §3 identity types with the
  correct equality/hashing; §4 capability types; Kelvin→RGB-gain blackbody math
  (`rgbGain(for:)`, 6500K→~identity, warmer dims blue<green<red, clamped 0...1); the schedule
  resolver (`.custom` midnight-wrap, `.alwaysOn`, `.off`, NOAA-style `.solar`,
  `.followSystemNightShift` deferring to injected state); and a pure per-display state reducer.
- **Stubbed (compiles, matches the public API, real impl is a later milestone, marked
  `TODO(milestone)`):** `CInterop` (typedef/shape-only header + module map + anchor `.c`;
  header comment states symbols are resolved at runtime via dlopen/dlsym); `DisplayRegistry`
  (CoreGraphics identity build; EDID parsing stubbed); `GammaBackend`
  (`.unsupported(.gammaBrokenOnThisOS)`); `DDCBackend` behind a swappable `DDCTransport`
  protocol (`.unknown(.notYetProbed)`; apply/reset throw `notYetImplemented`); `OverlayBackend`
  (`@MainActor`, `.supported(())`, per-NSScreen panel stubbed); `SystemNightShiftStateFollower`
  (read-only `currentlyActive` → `.unknown(.privateSymbolUnavailable)`, never writes Night
  Shift); and the `WarmthEngine` actor + `HotkeyService` with the complete §6/§8 public surface
  and minimal internals.
