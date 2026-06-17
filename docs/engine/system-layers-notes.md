# Engine system layers — implementation notes

Scope: the three "make the default real" system layers added on top of the M0 scaffold —
(1) hotplug/wake re-baseline, (2) the real read-only Night Shift follower, (3) gamma capability
classification + real apply/reset. All of this runs against **private / system APIs**, so this
note records exactly what is verified-by-build vs. only verifiable on real hardware at runtime,
plus the ABI facts the code depends on.

> Edits in this milestone are confined to `WarmthKit/` (`DisplayServices`, `NightShiftBridge`,
> `WarmthKit` umbrella, `WarmthCore`, `CInterop`) plus this single notes file. The public engine
> contract (`docs/engine/warmthkit-api-contract.md`) is honored unchanged — the additions are
> internal (`DisplayReconfigurationObserver`, `SystemWakeObserver`, `GammaClassifier`,
> `ReconfigurationDebounce`, `NightShiftPrivateAPI`) and additive.

---

## 1. M7 — hotplug / wake re-baseline

**Files:**
- `DisplayServices/DisplayReconfigurationObserver.swift` — wraps
  `CGDisplayRegisterReconfigurationCallback`. The C callback is a bare top-level
  `@convention(c)` function; its `userInfo` pointer is bridged to a `Sendable` `CallbackBox`
  that owns an `AsyncStream<Void>.Continuation`. It reacts **only to settled flags**
  (`add`/`remove`/`enabled`/`disabled`/`desktopShapeChanged`) and ignores
  `beginConfigurationFlag` and pure movement/mirroring noise.
- `WarmthKit/SystemWakeObserver.swift` — `@MainActor` observer of
  `NSWorkspace.shared.notificationCenter` `didWakeNotification`. Lives in the umbrella because
  `DisplayServices` is CoreGraphics-only (no AppKit). `init` is `nonisolated` (builds only the
  `AsyncStream`) so the actor can construct it without a main-actor hop; AppKit is touched only
  in `start()`.
- `WarmthCore/ReconfigurationDebounce.swift` — **pure** coalescing-timing policy (the
  300–500 ms quiet-window arithmetic), unit-tested headlessly.
- `WarmthKit/WarmthEngine.swift` — `startSystemObservers()` starts both observers and spawns one
  long-lived `rebaselineTask` (a `withTaskGroup` draining both streams) that funnels every event
  into the actor-isolated `coalesceRebaseline(window:)`. That method drives the pure
  `ReconfigurationDebounce` so a burst (a hotplug fires many callbacks; a wake may interleave)
  collapses to a **single** `rebaselineDisplays()` + re-apply after the window goes quiet.
  `shutdown()` cancels the task and stops both observers.

**Verified by build/test:** debounce/coalesce math (6 tests), Swift-6 actor isolation +
`Sendable` correctness of the C-callback bridge and the cross-actor wake stream, clean teardown
wiring.

**Runtime-only (needs real hardware):** that CoreGraphics actually delivers the settled flags we
filter on for a given monitor, that a real sleep/wake re-fires either the reconfiguration
callback or the wake notification, and that 400 ms is the right window on real hotplug storms.
The debounce window is a single constant (`rebaselineDebounceWindow`) if it needs tuning.

---

## 2. Real Night Shift follower (read-only)

**Files:**
- `NightShiftBridge/NightShiftPrivateAPI.swift` — defensive runtime resolution of the private
  `CBBlueLightClient` (CoreBrightness). Class via `NSClassFromString`; selectors
  (`getBlueLightStatus:`, `setStatusNotificationBlock:`) checked with `responds(to:)`;
  `getBlueLightStatus:` invoked through its method `IMP` cast to a typed `@convention(c)` pointer
  that writes a `WK_CBBlueLightStatus` out-parameter. OS-build version gate
  (`minSupportedOSMajor…maxSupportedOSMajor`). **Read-only by construction:** only the two
  read/observe selectors are ever referenced — no `setEnabled:`/`setStrength:`/`setMode:`.
- `NightShiftBridge/SystemNightShiftStateFollower.swift` — `Sendable` follower. All mutable state
  (resolved client, cached `active`, observer hook) lives behind an `NSLock` in a private
  `LockedState` (`@unchecked Sendable`). `start(onChange:)` seeds the value with a direct read
  and registers `setStatusNotificationBlock:`; the block uses `[weak self]` so there is **no
  retain cycle** (client → block → self → client). `currentlyActive` returns
  `.supported(active)` when read, else `.unknown(.privateSymbolUnavailable)` so the engine
  degrades to the evening fallback (unchanged behavior).
- `WarmthEngine.start()` calls `nightShiftFollower.start { … }`; the hook hops onto the actor and
  re-applies the schedule so following is **live**, not just sampled at launch.
  `shutdown()` calls `stop()`.

**ABI facts the code depends on** (confirmed against public CoreBrightness runtime headers —
LeoNatan/Apple-Runtime-Headers, srirangav/displayutil):
- `getBlueLightStatus:` returns `BOOL` → IMP modeled as returning `ObjCBool`.
- `Status` layout: `BOOL active; BOOL enabled; BOOL sunSchedulePermitted; int mode;
  Schedule schedule; unsigned long long disableFlags; BOOL available;`
  - **`BOOL` is `signed char` (1 byte)** on modern macOS — declaring it `int` (as the scaffold
    stub did) would mis-offset `active`/`enabled`. Fixed in `CInterop.h`.
  - **`Time` = `{ int hour; int minute; }` (4-byte ints) on macOS** (it is `char` on iOS). The
    follower only reads `active` (offset 0), but `getBlueLightStatus:` writes the **whole**
    struct into the out-parameter, so the buffer must be full-size or it is a stack overflow.
    `WK_CBBlueLightStatus` is modeled at true field widths (total 40 bytes) for this reason.

**Runtime-only (needs a signed/local run on real macOS):** that `CBBlueLightClient` resolves and
`getBlueLightStatus:` returns the live state, and that `setStatusNotificationBlock:` fires on
real Night Shift transitions. Headless CI cannot load/exercise the private class; the contract's
"smoke test" (loads the symbol OR cleanly reports `.unknown(privateSymbolUnavailable)`) is the
bar, and the degrade path is what the existing schedule-degrade tests already cover.

---

## 3. Gamma capability classification + real apply/reset

**Files:**
- `WarmthCore/GammaClassifier.swift` — **pure** decision over (isAppleSilicon, osMajorVersion,
  privateAPIsEnabled). Apple Silicon + macOS ≥ 26 → `.unsupported(.gammaBrokenOnThisOS)` (the
  transfer table is a silent no-op there); kill switch → `.unsupported(.osDenylisted)`;
  otherwise `.supported`. **No screen-capture measurement** (would need Screen Recording
  permission). Unit-tested (6 tests).
- `DisplayServices/GammaBackend.swift` — gathers the runtime facts (`#if arch(arm64)` +
  `ProcessInfo` OS major) and delegates the decision to `GammaClassifier`. Real `apply` builds
  three 256-entry per-channel ramps from `rgbGain(for:)` and pushes them via
  `CGSetDisplayTransferByTable`; `reset` via `CGDisplayRestoreColorSyncSettings`. `apply` is
  defended in depth — it refuses to write where classification is not `.supported`.
- Policy unchanged: gamma is reachable **only via an explicit per-display override**, never the
  automatic default. `LayerResolver` enforces that, and I extended `LayerResolver.isUsable` so the
  **kill switch also denylists gamma** (it is a best-effort path) — overlay stays the floor.

**Verified by build/test:** classification decision table, the `LayerResolver` kill-switch
extension (existing override tests still green), ramp construction is a pure function.

**Runtime-only (needs real hardware):** that `CGSetDisplayTransferByTable` actually warms the
panel on Intel / pre-26 Apple Silicon and is the confirmed silent no-op on macOS 26 Apple
Silicon (the reason it is default-OFF there). No headless way to observe pixels without the
capture permission we refuse to take.

---

## Contract deviations

None that change the frozen public surface. Two internal/additive policy points worth flagging:
- `LayerResolver.isUsable(.gamma…)` now also requires `privateAPIsEnabled` (kill switch
  denylists the best-effort gamma path). This tightens the safety floor; it does not change any
  public signature.
- `GammaBackend.init()` no longer takes a parameter (the scaffold stub took none either at the
  call site — `WarmthEngine` constructs `GammaBackend()`), and reports *device* capability; the
  kill switch is applied by `LayerResolver`, keeping a single source of truth for the toggle.

## Verification

- `swift build` (clean, `-warnings-as-errors`): passes, zero warnings, Swift 6 strict
  concurrency.
- `swift test`: 53 tests pass (41 baseline + 12 new: 6 `GammaClassifier`, 6
  `ReconfigurationDebounce`).
