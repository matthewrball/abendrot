# WarmthKit — Engine API Contract (v0, FROZEN-draft)

> **Status:** v0 frozen-draft, 2026-06-16. This is the interface Lane B (app UI) and Lane D
> (landing "audit the engine" snippet) build against. Signatures here are the **contract**;
> internal implementation may change freely, the public surface may not without a version bump.
>
> **Compile gate (Lane G):** the Swift in this document is the design surface. It must compile
> against the **Xcode 26 / macOS 26 "Tahoe" SDK** with **Swift 6 strict concurrency** before any
> lane depends on it as fact. Treat anything not yet compiled as provisional. Builds run
> **unsigned/local** — no Apple Developer account needed for development.
>
> Source of truth: plan `docs/abendrot-plan.md` §6 (architecture) + §21.1 (audit refinements).
> Where this contract and older plan prose disagree, **§21.1 and this document win.**

---

## 0. Design invariants (the non-negotiables)

These hold across every API below:

1. **Overlay is always the safe default.** Every display gets warmth via the Metal overlay
   unless a better layer is *proven* working for it. The engine never silently no-ops.
2. **DDC is opt-in per display.** Hardware DDC is OFF until the user enables it for a specific
   display, and only offered where capability-probed. Restore tooling must exist before it can
   ever become a default (it is not a default in v1.0). (§21‑E3)
3. **Gamma is capability-classified, not measured by default.** No runtime screen-capture probe
   (that needs Screen Recording permission and breaks the no-permission promise). Gamma is
   classified by device/OS and is default-OFF on M5 Tahoe. (§21‑E1)
4. **No permission is required for core function.** No Accessibility (hotkey via Carbon), no
   Screen Recording, no Sandbox. Location is requested *only* as a late fallback, after a manual
   one. (§21‑E6)
5. **Stable identity, never raw displayID.** All per-display state is keyed by `DisplayIdentity`,
   not the reassignable `CGDirectDisplayID`. (§21‑E4)
6. **Private APIs are kill-switchable.** A runtime flag / OS-build denylist can disable all
   private-API paths and fall back to overlay-only. (§21‑E5)
7. **Displays are always recoverable.** Neutral-reset on launch/quit; launch-time stale-state
   recovery (crash handlers can't reliably do async DDC); an emergency `restoreAllDisplays()`.
8. **The engine reports the method per display.** `Hardware` / `Gamma` / `Overlay` badges are a
   product differentiator, surfaced through `WarmthState`. (§4.1, §21.7)

---

## 1. Module map

Dependency direction is strictly downward (no cycles). `WarmthCore` is pure and knows nothing
of AppKit/IOKit.

| Module | Layer | Knows about | Owns |
|---|---|---|---|
| **WarmthCore** | pure domain | Foundation, Logging only | value types, Kelvin↔gain math, schedule logic, state-machine reducer, capability/identity *types*, watchdog policy |
| **CInterop** | C shim | — | typedefs/shims for private symbols; resolved at runtime via dlopen/dlsym |
| **DisplayServices** | system | CoreGraphics, IOKit, ColorSync, CInterop | `DisplayIdentity` construction, hotplug/reconfiguration, `GammaBackend`, capability classification |
| **HardwareDDC** | system (private) | IOKit/IOAVService (via CInterop) | `DDCBackend` behind protocols, EDID snapshot, transaction queue, write-then-read verify, restore |
| **OverlayRenderer** | UI/Metal (main-actor) | AppKit, Metal, DisplayServices | `OverlayBackend` — per-`NSScreen` click-through multiply veil |
| **NightShiftBridge** | system (private) | CInterop | `SystemNightShiftStateFollower` (read-only) |
| **WarmthKit** | umbrella | all of the above + KeyboardShortcuts | `WarmthEngine` actor, `HotkeyService`, public façade |

The app target (`Abendrot.app`, Lane B) links **only `WarmthKit`** and talks to `WarmthEngine`.
It does not touch the backends directly.

---

## 2. WarmthCore — value types (the vocabulary)

```swift
import Foundation

/// Correlated colour temperature, clamped to a sane display range. Neutral = 6500K.
public struct Kelvin: Hashable, Sendable, Comparable, Codable {
    public static let neutral = Kelvin(6500)
    public static let warmestSupported = Kelvin(1900)   // floor we expose in UI
    public let value: Int
    public init(_ value: Int) { self.value = min(6500, max(1000, value)) }
    public static func < (l: Kelvin, r: Kelvin) -> Bool { l.value < r.value }
}

/// The canonical user-facing warmth control: a normalized "Softer ⟷ Warmer" strength.
/// Kelvin is *derived* for display, never the dominant control (plan §4.1).
public struct WarmthLevel: Hashable, Sendable, Codable {
    /// 0.0 = neutral/off, 1.0 = maximum configured warmth.
    public let strength: Double                  // clamped 0...1
    public init(strength: Double) { self.strength = min(1, max(0, strength)) }
    public static let off = WarmthLevel(strength: 0)

    /// Target CCT for a strength, given the user's configured warmest point.
    public func kelvin(warmestPoint: Kelvin) -> Kelvin {
        let k = Double(Kelvin.neutral.value) -
                strength * Double(Kelvin.neutral.value - warmestPoint.value)
        return Kelvin(Int(k.rounded()))
    }
}

/// Which physical layer is producing warmth for a display right now. Drives the UI badge.
public enum DisplayMethod: String, Sendable, Codable, CaseIterable {
    case hardware   // DDC RGB-gain — real hardware warmth (badge: "Hardware")
    case gamma      // CGSetDisplayTransferByTable — best-effort, classified (badge: "Gamma")
    case overlay    // Metal multiply veil — universal default (badge: "Overlay")
    case off        // no warmth applied
    public var badge: String {
        switch self {
        case .hardware: "Hardware"; case .gamma: "Gamma"
        case .overlay:  "Overlay";  case .off: "Off"
        }
    }
}

/// How warmth is scheduled. Default = follow the system Night Shift state *when available*.
public enum ScheduleMode: Sendable, Codable, Equatable {
    case followSystemNightShift          // read-only follow; degrades to .solar if unavailable
    case solar(latitude: Double, longitude: Double)   // built-in solar fallback (no private API)
    case custom(CustomSchedule)          // explicit from/to + target
    case alwaysOn
    case off
}

public struct CustomSchedule: Sendable, Codable, Equatable {
    public var start: DateComponents     // hour/minute, local
    public var end: DateComponents
    public var warmest: WarmthLevel
}
```

> **Kelvin↔gain math** (per-channel RGB multipliers for both the overlay shader and DDC gain)
> lives in `WarmthCore` as pure functions and is the most-tested unit (plan §8). The mapping
> table and the blackbody approximation are an internal detail, not part of this contract.

---

## 3. DisplayIdentity (stable keying) — §21‑E4

```swift
/// Stable, hotplug-survivable identity for a display. NEVER key state on CGDirectDisplayID.
public struct DisplayIdentity: Hashable, Sendable, Codable {
    public let cgUUID: UUID                 // CGDisplayCreateUUIDFromDisplayID — primary key
    public let edid: EDIDFingerprint?       // vendor/product/serial — disambiguates duplicates
    public let transport: DisplayTransport  // builtIn / displayPort / hdmi / thunderbolt / unknown
    public let ioRegistryPath: String?      // AppleCLCD2 / DCPAVServiceProxy path, if resolvable

    // Transient (NOT part of identity equality) — refreshed on every reconfiguration:
    public var currentDisplayID: CGDirectDisplayID  // changes across hotplug/sleep
    public var frame: CGRect                        // NSScreen frame
    public var backingScale: CGFloat
}

public struct EDIDFingerprint: Hashable, Sendable, Codable {
    public let vendorID: UInt16
    public let productID: UInt16
    public let serial: UInt32?              // may be absent; do NOT log/transmit (see redaction)
    public let displayName: String?         // human label for the UI
}

public enum DisplayTransport: String, Sendable, Codable {
    case builtIn, displayPort, hdmi, thunderbolt, usbC, unknown
}
```

- **Equality / hashing** use `cgUUID` (+ `edid` to disambiguate identical twin monitors); the
  transient fields are excluded.
- **Reconfiguration bursts** (`CGDisplayRegisterReconfigurationCallback` /
  `didChangeScreenParametersNotification`) are **debounced on the main actor** before the engine
  re-baselines. (§21‑E4)
- **Redaction:** `serial` and any precise identifier are stripped from logs and never enter
  analytics (plan §11). `displayName` is UI-only.

---

## 4. Capability classification — typed, not optionals-sprinkled (§21‑E5)

Every private/backend lookup returns a **typed capability result**, so "we don't know" is a
first-class value the UI can render — never a silent nil.

```swift
public enum Capability<Detail: Sendable>: Sendable {
    case supported(Detail)
    case unsupported(reason: CapabilityReason)
    case unknown(reason: CapabilityReason)      // e.g. private symbol missing on this OS build
}

public enum CapabilityReason: String, Sendable, Codable {
    case ok
    case buttonlessAppleDisplay     // exposes no DDC colour VCP → overlay
    case gammaBrokenOnThisOS        // M5 Tahoe silent no-op → overlay
    case privateSymbolUnavailable   // dlsym returned null on this OS build → kill-switch path
    case ddcProbeFailed             // VCP 0x16 read failed
    case osDenylisted               // OS build on the private-API denylist
    case notYetProbed
}

/// Per-display, per-method classification the engine computes at baseline.
public struct DisplayCapabilities: Sendable {
    public let identity: DisplayIdentity
    public let hardware: Capability<DDCColorCaps>    // DDC gain support
    public let gamma: Capability<Void>               // classified, NOT measured
    public let overlay: Capability<Void>             // ~always .supported
    /// Best layer the engine will use by default given current opt-ins.
    public var recommendedMethod: DisplayMethod
}

public struct DDCColorCaps: Sendable { public let supportsRGBGain: Bool /* VCP 0x16/0x18/0x1A */ }
```

---

## 5. Backend protocol + the three layers

All backends conform to one protocol; the engine selects best-available per display. Backends are
internal (`package`/`internal`) — the app never calls them.

```swift
package protocol WarmthBackend: Sendable {
    var method: DisplayMethod { get }
    /// Classify (no side effects, no permission, no measurement-by-capture).
    func classify(_ identity: DisplayIdentity) async -> Capability<Void>
    /// Apply a target. Idempotent; draw/write on change only.
    func apply(_ kelvin: Kelvin, to identity: DisplayIdentity) async throws
    /// Return this display to neutral via THIS layer.
    func reset(_ identity: DisplayIdentity) async throws
}
```

- **OverlayBackend** (`OverlayRenderer`, `@MainActor`): one borderless, click-through
  `NSPanel`/`CAMetalLayer` per `NSScreen` at `CGShieldingWindowLevel()`,
  `collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]`, `ignoresMouseEvents=true`,
  draw-on-change (~0% idle GPU). `sharingType` toggles screenshot-exemption.
  **Documented limits (§21‑E2):** native fullscreen Spaces, Mission Control, login/lock window,
  protected/HDR/EDR video, and multi-Space ordering may not be covered — the badge says
  `Overlay`, the UI never calls it "hardware".
- **DDCBackend** (`HardwareDDC`): `IOAVServiceWriteI2C` VCP gain. **Required before it may even be
  offered:** EDID native-state snapshot, per-display transaction queue, rate-limit/backoff,
  write-then-read verify, and launch-time stale-state recovery. Opt-in per display. (§21‑E3)
- **GammaBackend** (`DisplayServices`): `CGSetDisplayTransferByTable`, gated behind capability
  classification, default-OFF on M5 Tahoe, reset via `CGDisplayRestoreColorSyncSettings`. No
  default measurement. (§21‑E1)

---

## 6. WarmthEngine — the public actor (THE freeze)

This is the surface Lane B drives. It is the only WarmthKit type the app constructs.

```swift
public actor WarmthEngine {
    public init(configuration: EngineConfiguration)

    // ── Lifecycle ────────────────────────────────────────────────────────────
    /// Build the display registry, run launch-time stale-state recovery, baseline capabilities,
    /// then apply current settings. Safe to call once at app launch.
    public func start() async
    /// Neutral-reset every display via every active layer, then tear down. Called on quit.
    public func shutdown() async

    // ── Global controls ───────────────────────────────────────────────────────
    public func setEnabled(_ enabled: Bool) async
    public func setWarmth(_ level: WarmthLevel) async
    public func setScheduleMode(_ mode: ScheduleMode) async
    public func setWarmestPoint(_ kelvin: Kelvin) async        // the "maximum warmth" the slider maps to

    // ── Reveal True Color (signature feature) ─────────────────────────────────
    /// Suspend warmth across ALL displays (true colour). Idempotent.
    public func beginReveal() async
    /// Ease warmth back across all displays (~100–150ms). Idempotent.
    public func endReveal() async

    // ── Per-display ───────────────────────────────────────────────────────────
    /// Set a display's own "Custom warmth" value. Setting a per-display value implies the
    /// override (`warmthOverridden = true`) — see `DisplayState.warmthOverridden`. (Additive, Session 7.)
    public func setWarmth(_ level: WarmthLevel, for id: DisplayIdentity) async
    /// Toggle a display's "Custom warmth" override without changing its value. On → the display uses
    /// its own `warmth` (seeded to the current global on enable); off → it follows the global
    /// warmth/schedule. (Additive, Session 7 — replaces the old max(per-display, global) boost.)
    public func setWarmthOverride(_ enabled: Bool, for id: DisplayIdentity) async
    /// Force a specific layer for a display, or nil to return to automatic best-available.
    public func setPreferredMethod(_ method: DisplayMethod?, for id: DisplayIdentity) async
    /// DDC opt-in toggle. No-op (returns .unsupported in state) where DDC isn't capable.
    public func setHardwareDDCEnabled(_ enabled: Bool, for id: DisplayIdentity) async
    /// Per-app exclusions (v1.0 = per-app only; per-website is future, §21‑E8).
    public func setExcludedApps(_ bundleIDs: Set<String>) async

    // ── Safety ────────────────────────────────────────────────────────────────
    /// Emergency "Restore Displays": neutral gamma + overlay teardown + DDC native-state restore
    /// for every known display. Surfaced as a menu command. Always available.
    public func restoreAllDisplays() async
    /// Disable all private-API (DDC + Night Shift) paths and fall back to overlay-only.
    public func setPrivateAPIsEnabled(_ enabled: Bool) async      // kill switch (§21‑E5)

    // ── Observation ───────────────────────────────────────────────────────────
    public var state: WarmthState { get async }
    /// The UI renders from this stream. Emits on every meaningful state change.
    public func stateUpdates() -> AsyncStream<WarmthState>
}

public struct EngineConfiguration: Sendable {
    public var startWithPrivateAPIsEnabled: Bool   // false on denylisted OS builds
    public var defaultScheduleMode: ScheduleMode   // .followSystemNightShift
    public var defaultWarmestPoint: Kelvin
    public init(startWithPrivateAPIsEnabled: Bool = true,
                defaultScheduleMode: ScheduleMode = .followSystemNightShift,
                defaultWarmestPoint: Kelvin = Kelvin(2700))
}
```

### Observed state (what the UI renders)

```swift
public struct WarmthState: Sendable, Equatable {
    public var isEnabled: Bool
    public var scheduleMode: ScheduleMode
    public var isScheduleActiveNow: Bool          // resolved schedule decision
    public var isRevealing: Bool                  // hold-to-reveal active
    public var globalWarmth: WarmthLevel
    public var warmestPoint: Kelvin               // Kelvin that strength 1.0 maps to (UI readout)
    public var privateAPIsEnabled: Bool
    public var displays: [DisplayState]           // one per connected display
}

public struct DisplayState: Sendable, Equatable, Identifiable {
    public var id: DisplayIdentity
    public var name: String                       // human label for the row
    public var appliedMethod: DisplayMethod       // → the Hardware/Gamma/Overlay badge
    public var capabilities: DisplayCapabilities
    public var warmth: WarmthLevel                 // the display's own value, used when overridden
    /// When true, the display uses its OWN `warmth` (a user "Custom warmth" override — softer OR
    /// warmer than global); when false it follows the global warmth/schedule. (Additive, Session 7;
    /// replaces the old max(per-display, global) boost so an override can also be *softer*.)
    public var warmthOverridden: Bool
    public var isHardwareDDCEnabled: Bool          // opt-in flag
    public var preferredMethod: DisplayMethod?     // user's explicit layer override (nil = auto)
    public var lastError: EngineErrorSummary?      // non-fatal, surfaced quietly in advanced mode
}
```

---

## 7. Scheduling — `SystemNightShiftStateFollower` (best-effort) — §21‑E6

- Internally named `SystemNightShiftStateFollower`. The UI copy is **"follow system Night Shift
  *when available*."** It is a best-effort read of private state, not a contract.
- `NightShiftBridge` reads `CBBlueLightClient.getBlueLightStatus:` + observes
  `setStatusNotificationBlock:`; it **never writes** Night Shift.
- If the private symbol is unavailable (kill switch / OS denylist / dlsym null), the engine
  **degrades to `.solar`** using a built-in sunrise/sunset calc. The **manual / approximate-
  timezone** fallback is offered **before** Location Services is ever requested.

---

## 8. HotkeyService — hold-to-reveal — §4.2

```swift
@MainActor public final class HotkeyService {
    public init(engine: WarmthEngine)
    public func installRevealHotkey()        // default ⌥⌘T; configurable; supports HOLD and TOGGLE
    public var mode: RevealMode               // .hold (default) | .toggle
    /// Watchdog: if a key-up is lost (e.g. a Space switch eats it), auto-resume warmth after N s.
    public var watchdogTimeout: Duration      // default .seconds(8)
}
public enum RevealMode: String, Sendable, Codable { case hold, toggle }
```

- Wraps `KeyboardShortcuts` (Carbon `RegisterEventHotKey`): **no Accessibility permission**,
  keyDown→`beginReveal()`, keyUp→`endReveal()`. Carbon callback hops to the main actor.
- **Watchdog** guarantees warmth is never stuck-suspended; 100-cycle stuck-test is an acceptance
  criterion (plan §19).

---

## 9. Safety & lifecycle guarantees

- **Launch:** `start()` runs **stale-state recovery first** — if a prior run left DDC gain or
  gamma altered (crash/SIGKILL), restore native state from the persisted EDID snapshot before
  applying anything. Crash/exit handlers are **not** relied on for async DDC. (§21‑E3)
- **Quit:** `shutdown()` neutral-resets all layers.
- **Hotplug / wake:** debounced reconfiguration callback re-baselines identity + capabilities and
  re-applies per-display state. (§21‑E4)
- **Kill switch:** `setPrivateAPIsEnabled(false)` (or an OS-build denylist at construction) drops
  DDC + Night Shift and runs **overlay-only**; state reflects it. Signed/notarized private-API
  smoke tests run **from M0**, not just at release. (§21‑E5)
- **Persistence:** last-known native DDC gain + the EDID snapshot per `DisplayIdentity` survive
  relaunch.

---

## 10. Explicitly OUT of scope for v1.0 (so B/D don't design for them)

- **Auto screenshot/recording suspend** — no clean public API; v1.0 ships **manual** Reveal True
  Color + a "reveal during captures" shortcut. (§21‑E7)
- **Per-website exclusions** — needs browser integration/Accessibility; v1.0 is **per-app only**.
  (§21‑E8)
- **ColorSync ICC injection (Layer 1.5)** — future. (plan §18)
- **DDC as a default** — opt-in only in v1.0.

---

## 11. Freeze policy, open questions, and the verification gate

**Frozen for B/D to build against:** §2 value types, §3 `DisplayIdentity`, §4 capability types,
§6 `WarmthEngine` public methods + `WarmthState`/`DisplayState`, §7 schedule modes, §8 hotkey
surface. Additive changes (new optional params, new state fields) are allowed; removals/renames
need a contract version bump + a note to Lanes B and D.

**Additive changes since v0 (no version bump — purely additive, per the policy above):**
- **Session 7:** `DisplayState.warmthOverridden: Bool` + `WarmthEngine.setWarmthOverride(_:for:)`
  — a true per-display override (softer *or* warmer) that replaced the old max(per-display, global)
  boost. `setWarmth(_:for:)` now implies the override. No existing signature changed.

**Open questions to resolve during M0–M1 (won't change the public surface):**
1. Exact `warmestPoint` default and the slider's strength→Kelvin curve shape (perceptual vs linear).
2. Whether `OverlayBackend` uses one panel per screen or a shared `CAMetalLayer` host (perf).
3. Whether `setExcludedApps` belongs on the engine or a thin app-side coordinator.

**Verification gate (Lane G), before B/D treat this as fact:**
- [ ] `swift build` clean on Xcode 26 / macOS 26 with Swift 6 strict concurrency.
- [ ] `WarmthCore` unit tests: Kelvin↔gain math, schedule resolution, state reducer, watchdog.
- [ ] Signed/notarized-OR-local private-API **smoke test** loads IOAVService + CBBlueLightClient
      symbols (or cleanly reports `.unknown(privateSymbolUnavailable)` and stays overlay-only).
- [ ] `code-reviewer` pass on the public surface for Sendable/actor-isolation correctness.
