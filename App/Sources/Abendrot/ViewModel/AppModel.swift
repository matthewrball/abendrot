import Foundation
import Observation
import WarmthKit

// MARK: - AppModel
//
// The `@Observable`, `@MainActor` view-model that sits between SwiftUI and the
// FROZEN `WarmthEngine` actor. It:
// - owns the `WarmthEngine` and `HotkeyService`,
// - consumes `engine.stateUpdates` and republishes the latest `WarmthState`
// for the views to render,
// - turns view intents (toggle, slider, mode, per-display overrides, reveal)
// into `await engine.…` calls.
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
    /// keeps running and is reachable via the global hotkey + relaunch.
    var showInMenuBar: Bool = true

    // MARK: Engine wiring (nil in previews)

    private let engine: WarmthEngine?
    private var hotkeyService: HotkeyService?
    private var observationTask: Task<Void, Never>?

    // MARK: Init

    /// Live initializer — owns a real engine. Call `start` from the App entry.
    init(configuration: EngineConfiguration = EngineConfiguration()) {
        let engine = WarmthEngine(configuration: configuration)
        self.engine = engine
        self.state = WarmthState(scheduleMode: configuration.defaultScheduleMode)
        self.hotkeyService = HotkeyService(engine: engine)
    }

    /// Preview / scaffold initializer — seeds a mock state, no live actor.
    init(previewState: WarmthState) {
        self.engine = nil
        self.hotkeyService = nil
        self.state = previewState
    }

    // MARK: Lifecycle

    /// Start the engine, install the reveal hotkey, and begin streaming state.
    /// No-ops in preview mode (no engine).
    func start() {
        guard let engine else { return }
        hotkeyService?.installRevealHotkey()
        observationTask = Task { [weak self] in
            for await snapshot in await engine.stateUpdates() {
                self?.state = snapshot
            }
        }
        // Start the engine, THEN re-apply the persisted warmest point (the hybrid expanded-range
        // pick) in the same task so the restore is ordered strictly after start — avoiding a
        // reentrancy race where the restore could land before the engine finishes booting.
        Task { [weak self] in
            await engine.start()
            guard let self else { return }
            // Only restore a sane, warm ceiling (500…3400K). `Kelvin.init` already floors at 500;
            // the upper clamp guards against any future writer persisting a non-warm value that
            // would neuter warming. The only writer today is the Maximum-warmth control.
            if let saved = UserDefaults.standard.object(forKey: Self.warmestPointKey) as? Int,
               saved <= Kelvin.ceilingCoolBound.value {
                self.setWarmestPoint(Kelvin(saved))
            }
        }
    }

    /// Neutral-reset + tear down. Call on app quit.
    func shutdown() async {
        observationTask?.cancel()
        observationTask = nil
        await engine?.shutdown()
    }

    // MARK: ── Global intents ────────────────────────────────────────────────

    func setEnabled(_ enabled: Bool) {
        // Optimistic UI (no spinners): reflect immediately, engine confirms.
        state.isEnabled = enabled
        Task { await engine?.setEnabled(enabled) }
    }

    func setGlobalWarmth(_ strength: Double) {
        let level = WarmthLevel(strength: strength)
        state.globalWarmth = level
        Task { await engine?.setWarmth(level) }
    }

    func setScheduleMode(_ mode: ScheduleMode) {
        state.scheduleMode = mode
        Task { await engine?.setScheduleMode(mode) }
    }

    /// UserDefaults key for the persisted warmest point (the slider's warmest end). A focused
    /// slice of persistence: the hybrid expanded-range pick must survive relaunch to be useful.
    static let warmestPointKey = "warmestPointKelvin"

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

    // MARK: ── Per-display intents ───────────────────────────────────────────

    func setWarmth(_ strength: Double, for id: DisplayIdentity) {
        let level = WarmthLevel(strength: strength)
        if let i = state.displays.firstIndex(where: { $0.id == id }) {
            state.displays[i].warmth = level
        }
        Task { await engine?.setWarmth(level, for: id) }
    }

    func setPreferredMethod(_ method: DisplayMethod?, for id: DisplayIdentity) {
        if let method, let i = state.displays.firstIndex(where: { $0.id == id }) {
            state.displays[i].appliedMethod = method
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
        Task { await engine?.setExcludedApps(bundleIDs) }
    }

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
    /// disagree with the applied warmth — fixed so the number never lies.
    var globalKelvin: Kelvin {
        state.globalWarmth.kelvin(warmestPoint: state.warmestPoint)
    }

    /// A short, glanceable status string for the popover title ("Warming · 2700K").
    var statusSummary: String {
        guard state.isEnabled else { return "Off" }
        if state.isRevealing { return "True color" }
        guard state.isScheduleActiveNow || state.globalWarmth.strength > 0 else { return "Idle" }
        return "Warming · \(globalKelvin.value)K"
    }
}
