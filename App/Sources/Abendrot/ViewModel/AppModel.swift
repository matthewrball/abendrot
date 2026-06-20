import Foundation
import Observation
import WarmthKit

// MARK: - AppModel
//
// The `@Observable`, `@MainActor` view-model that sits between SwiftUI and the
// FROZEN `WarmthEngine` actor. It:
//   - owns the `WarmthEngine` and `HotkeyService`,
//   - consumes `engine.stateUpdates()` and republishes the latest `WarmthState`
//     for the views to render,
//   - turns view intents (toggle, slider, mode, per-display overrides, reveal)
//     into `await engine.…` calls.
//
// Integration is ONLY via the contract (`import WarmthKit`). No engine internals.
//
// Previews and engine-not-green builds construct `AppModel(previewState:)`, which
// seeds `state` from `MockWarmthState` and does NOT start the actor — so the UI
// renders without a live engine.
@MainActor
@Observable
final class AppModel {

    // MARK: Observed surface (what the views render)

    /// Latest snapshot from the engine (or a seeded mock in previews).
    private(set) var state: WarmthState

    /// UI mode for the menu-bar popover (left-click = simple, ⌥/right = advanced).
    var isAdvancedExpanded: Bool = false

    /// Whether the onboarding "3 clicks to warmth" flow should be shown.
    var showOnboarding: Bool = false

    /// Whether the menu-bar icon is shown (Settings → General). When false the app
    /// keeps running and is reachable via the global hotkey + relaunch (plan §4.3).
    var showInMenuBar: Bool = true

    /// Reveal-True-Color behaviour: hold (default) vs toggle (§3 locked — ship both). Mirrors
    /// `HotkeyService.mode`; surfaced here so the Settings picker can bind and previews (no live
    /// service) still render. Persisted; restored in `applyPersistedState()`.
    var revealMode: RevealMode = .hold

    /// Bundle ids the user has excluded — while one is frontmost the engine suspends warmth (true
    /// colour) across all displays. The UI source of truth for the Advanced → Excluded apps picker;
    /// mirrored into the engine via `setExcludedApps`. Persisted; restored in `applyPersistedState()`.
    var excludedApps: Set<String> = []

    // MARK: Engine wiring (nil in previews)

    private let engine: WarmthEngine?
    private var hotkeyService: HotkeyService?
    private var frontmostMonitor: FrontmostAppMonitor?
    private var observationTask: Task<Void, Never>?

    // MARK: Init

    /// Live initializer — owns a real engine. Call `start()` from the App entry.
    init(configuration: EngineConfiguration = EngineConfiguration()) {
        let engine = WarmthEngine(configuration: configuration)
        self.engine = engine
        self.state = WarmthState(scheduleMode: configuration.defaultScheduleMode)
        self.hotkeyService = HotkeyService(engine: engine)
        self.frontmostMonitor = FrontmostAppMonitor(engine: engine)
    }

    /// Preview / scaffold initializer — seeds a mock state, no live actor.
    init(previewState: WarmthState) {
        self.engine = nil
        self.hotkeyService = nil
        self.frontmostMonitor = nil
        self.state = previewState
    }

    // MARK: Lifecycle

    /// Start the engine, install the reveal hotkey, and begin streaming state.
    /// No-ops in preview mode (no engine).
    func start() {
        guard let engine else { return }
        hotkeyService?.installRevealHotkey()
        // Seeds the current frontmost app immediately. If that `setFrontmostApp` lands before the
        // `engine.start()` Task below, it's harmless — the engine recomputes suspend wholesale each pass.
        frontmostMonitor?.start()
        observationTask = Task { [weak self] in
            for await snapshot in await engine.stateUpdates() {
                self?.state = snapshot
            }
        }
        // Start the engine, THEN replay persisted user state (§25.B) in the same task so the
        // restore is ordered strictly after start() — avoiding a reentrancy race where it could
        // land before the engine finishes booting.
        Task { [weak self] in
            await engine.start()
            self?.applyPersistedState()
        }
    }

    /// Replay persisted user state through the normal setters so the engine and the published
    /// `state` converge exactly as a live interaction would. Called once from `start()`, strictly
    /// after `engine.start()`. Only keys explicitly written before are restored — a fresh install
    /// keeps the engine's defaults. (§25.B persistence.)
    private func applyPersistedState() {
        let defaults = UserDefaults.standard

        // Warmest point (the slider's warmest end / hybrid expanded-range pick). Clamp on read:
        // only restore a sane, warm ceiling (500…3400K). `Kelvin.init` already floors at 500; the
        // upper clamp guards against any future writer persisting a non-warm value that would
        // neuter warming. The only writer today is the Maximum-warmth control.
        if let saved = defaults.object(forKey: Self.warmestPointKey) as? Int,
           saved <= Kelvin.ceilingCoolBound.value {
            setWarmestPoint(Kelvin(saved))
        }

        // Schedule mode (Codable JSON — carries associated values). If the blob is ever malformed
        // (schema drift, a renamed case, a partial write), drop the key so it re-derives cleanly
        // rather than silently stranding the user on the default — the "it worked then broke" class
        // §25.B exists to kill.
        if let data = defaults.data(forKey: Self.scheduleModeKey) {
            if let mode = try? JSONDecoder().decode(ScheduleMode.self, from: data) {
                setScheduleMode(mode)
            } else {
                defaults.removeObject(forKey: Self.scheduleModeKey)
            }
        }

        // Nightly warmth strength. `object(forKey:)` (not `double`) so an *unset* key stays the
        // engine's 0.7 out-of-box default instead of being clobbered to 0.0. A *persisted* 0.0 is a
        // real user choice (slider dragged to off) and is intentionally honored — distinct from unset.
        if let strength = defaults.object(forKey: Self.globalWarmthStrengthKey) as? Double {
            setGlobalWarmth(strength)
        }

        // Master toggle last. The final converged engine state is order-independent — each setter
        // sets one box field and the engine recomputes from the whole box — so this is a mild nicety,
        // not a correctness requirement. (Any brief default-state flash at launch comes from the
        // engine's initial state-stream snapshot landing before these restores publish; this ordering
        // doesn't affect that — the published state converges once the engine applies the restores.)
        if let enabled = defaults.object(forKey: Self.isEnabledKey) as? Bool {
            setEnabled(enabled)
        }

        // Reveal behaviour (hold vs toggle, §3). A fresh install keeps the default hold.
        if let raw = defaults.string(forKey: Self.revealModeKey),
           let mode = RevealMode(rawValue: raw) {
            setRevealMode(mode)
        }

        // Excluded apps (suspend warmth while one is frontmost). Fresh install = none.
        if let arr = defaults.array(forKey: Self.excludedAppsKey) as? [String] {
            setExcludedApps(Set(arr))
        }
    }

    /// Neutral-reset + tear down. Call on app quit.
    func shutdown() async {
        observationTask?.cancel()
        observationTask = nil
        frontmostMonitor?.stop()
        await engine?.shutdown()
    }

    // MARK: ── Global intents ────────────────────────────────────────────────

    func setEnabled(_ enabled: Bool) {
        // Optimistic UI (plan §5.2 — no spinners): reflect immediately, engine confirms.
        state.isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.isEnabledKey)
        Task { await engine?.setEnabled(enabled) }
    }

    func setGlobalWarmth(_ strength: Double) {
        let level = WarmthLevel(strength: strength)
        state.globalWarmth = level
        // Persist the clamped canonical value, not the raw arg (§25.B).
        UserDefaults.standard.set(level.strength, forKey: Self.globalWarmthStrengthKey)
        Task { await engine?.setWarmth(level) }
    }

    func setScheduleMode(_ mode: ScheduleMode) {
        state.scheduleMode = mode
        // ScheduleMode carries associated values (.solar/.custom) → encode as Codable JSON,
        // not a bare string (§25.B).
        if let data = try? JSONEncoder().encode(mode) {
            UserDefaults.standard.set(data, forKey: Self.scheduleModeKey)
        }
        Task { await engine?.setScheduleMode(mode) }
    }

    // MARK: ── Persistence (§25.B) ───────────────────────────────────────────
    //
    // User-facing engine state that must survive relaunch. `warmestPoint` already
    // persisted (the hybrid expanded-range pick); this extends the same pattern to the
    // master toggle, the nightly warmth, and the schedule mode so the app reopens exactly
    // as the user left it instead of resetting to disabled / off / follow-Night-Shift every
    // launch (a major "it worked then broke" contributor — §25 Session-5 RESULTS).
    //
    // Each value is written in its setter and restored once in `start()` *after*
    // `engine.start()` by replaying that same setter, so the engine and the published
    // `state` converge through the path a live interaction would take. Reads use
    // `object(forKey:)` (NOT `bool`/`double`, which collapse "never saved" into false/0.0)
    // so a fresh install keeps the engine's defaults — notably the 0.7 out-of-box warmth,
    // which a `double(forKey:)` miss would silently clobber to 0.0.
    static let warmestPointKey = "warmestPointKelvin"
    static let isEnabledKey = "isEnabled"
    static let globalWarmthStrengthKey = "globalWarmthStrength"
    static let scheduleModeKey = "scheduleMode"
    static let revealModeKey = "revealMode"
    static let excludedAppsKey = "excludedApps"

    func setWarmestPoint(_ kelvin: Kelvin) {
        // Optimistic UI so the Kelvin readout updates immediately, then persist + tell the engine.
        state.warmestPoint = kelvin
        UserDefaults.standard.set(kelvin.value, forKey: Self.warmestPointKey)
        Task { await engine?.setWarmestPoint(kelvin) }
    }

    // MARK: ── Reveal True Color ─────────────────────────────────────────────

    func beginReveal() {
        state.isRevealing = true
        Task { await engine?.beginReveal() }
    }

    func endReveal() {
        state.isRevealing = false
        Task { await engine?.endReveal() }
    }

    /// Switch the reveal behaviour between hold and toggle (§3). `HotkeyService.mode` already honours
    /// this live in `handleKeyDown/Up`; this surfaces + persists the choice. The service call is a
    /// no-op in previews (no live hotkey), but the observed `revealMode` still updates so the picker
    /// tracks the selection.
    func setRevealMode(_ mode: RevealMode) {
        revealMode = mode
        hotkeyService?.mode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: Self.revealModeKey)
    }

    // MARK: ── Per-display intents ───────────────────────────────────────────

    func setWarmth(_ strength: Double, for id: DisplayIdentity) {
        let level = WarmthLevel(strength: strength)
        if let i = state.displays.firstIndex(where: { $0.id == id }) {
            state.displays[i].warmth = level
            state.displays[i].warmthOverridden = true   // setting a per-display value IS the override
        }
        Task { await engine?.setWarmth(level, for: id) }
    }

    /// Enable/disable a display's "Custom warmth" override. Off → the display follows the global
    /// warmth; on → it keeps its own value (seeded to the current global by the engine).
    func setWarmthOverride(_ enabled: Bool, for id: DisplayIdentity) {
        if let i = state.displays.firstIndex(where: { $0.id == id }) {
            state.displays[i].warmthOverridden = enabled
            if enabled {
                state.displays[i].warmth = state.globalWarmth
            }
        }
        Task { await engine?.setWarmthOverride(enabled, for: id) }
    }

    func setPreferredMethod(_ method: DisplayMethod?, for id: DisplayIdentity) {
        if let i = state.displays.firstIndex(where: { $0.id == id }) {
            // Reflect the user's *choice* immediately so the method picker tracks taps without lag.
            // The engine re-resolves and republishes the actually-applied method (which can differ
            // if the chosen layer isn't usable). nil = automatic best-available.
            state.displays[i].preferredMethod = method
            if let method { state.displays[i].appliedMethod = method }
        }
        Task { await engine?.setPreferredMethod(method, for: id) }
    }

    func setHardwareDDCEnabled(_ enabled: Bool, for id: DisplayIdentity) {
        if let i = state.displays.firstIndex(where: { $0.id == id }) {
            state.displays[i].isHardwareDDCEnabled = enabled
        }
        Task { await engine?.setHardwareDDCEnabled(enabled, for: id) }
    }

    func setExcludedApps(_ bundleIDs: Set<String>) {
        excludedApps = bundleIDs
        // Persist a sorted [String] (stable, plist-native) so the set survives relaunch (§25.B).
        UserDefaults.standard.set(bundleIDs.sorted(), forKey: Self.excludedAppsKey)
        Task { await engine?.setExcludedApps(bundleIDs) }
    }

    /// Add one bundle id to the exclusion set (Advanced → Excluded apps "Add app…").
    func addExcludedApp(_ id: String) { setExcludedApps(excludedApps.union([id])) }

    /// Remove one bundle id from the exclusion set (the row's ✕ button).
    func removeExcludedApp(_ id: String) { setExcludedApps(excludedApps.subtracting([id])) }

    // MARK: ── Safety ────────────────────────────────────────────────────────

    func restoreAllDisplays() {
        Task { await engine?.restoreAllDisplays() }
    }

    func setPrivateAPIsEnabled(_ enabled: Bool) {
        state.privateAPIsEnabled = enabled
        Task { await engine?.setPrivateAPIsEnabled(enabled) }
    }

    // MARK: ── Derived display helpers ───────────────────────────────────────

    /// The current global Kelvin readout, derived from strength + the *actual* warmest point the
    /// engine is using (published in `state`). Previously hardcoded 2700K, which made the readout
    /// disagree with the applied warmth — fixed so the number never lies. (§25 max-warmth.)
    var globalKelvin: Kelvin {
        state.globalWarmth.kelvin(warmestPoint: state.warmestPoint)
    }

    /// The phase the status readout is in. Lets the popover header render the Kelvin number as its
    /// own `Text` (so it can animate with a sliding-digit transition) while the non-warming phases
    /// stay plain text.
    enum StatusPhase: Equatable { case off, revealing, idle, warming }

    var statusPhase: StatusPhase {
        guard state.isEnabled else { return .off }
        if state.isRevealing { return .revealing }
        guard state.isScheduleActiveNow || state.globalWarmth.strength > 0 else { return .idle }
        return .warming
    }

    /// A short, glanceable status string for the popover title ("Warming · 2700K").
    var statusSummary: String {
        switch statusPhase {
        case .off:       return "Off"
        case .revealing: return "True color"
        case .idle:      return "Idle"
        case .warming:   return "Warming · \(globalKelvin.value)K"
        }
    }

    // MARK: ── Incompatibility ("can only be tinted") detection — §25.J ──────────

    /// A display can only be TINTED when no true-warm path is available to it: gamma is not
    /// supported on this chip/OS (or private APIs are off) AND it is not DDC-capable. Capability-
    /// based, so it reads honestly even before warming is enabled. Lives here (not in a view) so the
    /// app-level banner in PopoverView and the per-display rows in AdvancedExpansion share one
    /// source of truth.
    func isTintOnly(_ display: DisplayState) -> Bool {
        let priv = state.privateAPIsEnabled
        let gammaPossible = priv && Self.isSupported(display.capabilities.gamma)
        let ddcPossible = priv && Self.isSupported(display.capabilities.hardware)
        return !(gammaPossible || ddcPossible)
    }

    private static func isSupported<T>(_ cap: Capability<T>) -> Bool {
        if case .supported = cap { return true }
        return false
    }
}
