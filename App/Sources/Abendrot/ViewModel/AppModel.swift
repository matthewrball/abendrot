import Foundation
import Observation
import AppKit
import AVFoundation
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

    /// Which Settings tab is selected — bound to the sidebar so the popover can deep-link (e.g. the
    /// "Per-app exclusions" row opens Settings → Advanced).
    var settingsTab: SettingsTab = .general

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

    /// Manual Sunset location override. nil = Auto from system time zone; no permission or network.
    var userCoordinate: TimeZoneCoordinates.Coordinate? = nil

    // MARK: Statistics (local-only — never leaves this Mac, "Private by default")

    /// Total seconds Abendrot has actively warmed, EXCLUDING any in-flight period (the live total
    /// adds the open period via `totalWarmedSeconds`). Persisted.
    private(set) var warmedSecondsBase: Double = 0
    /// Sunsets that occurred while in Sunset mode + enabled — counted once per local day. Persisted.
    private(set) var warmSunsetCount: Int = 0
    /// Whether to accumulate the local stats at all (default on; nothing leaves the Mac either way).
    private(set) var statsEnabled: Bool = true
    /// Start of the current warming period, or nil when not warming. In-memory bookkeeping only.
    @ObservationIgnored private var warmingStartedAt: Date?
    /// Start-of-day (timeIntervalSince1970) of the last counted warm sunset — de-dupes per day.
    @ObservationIgnored private var lastWarmSunsetDay: Double = 0
    /// Reusable chime graph: the system "Glass" sound, played bright on warming-ON and PITCHED-DOWN
    /// (deeper, dampened) on warming-OFF. Built lazily on first toggle; nil if the sound file is missing.
    @ObservationIgnored private lazy var confirmationChime: ConfirmationChime? = ConfirmationChime()

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
                self?.updateWarmingStats()
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
            setEnabled(enabled, userInitiated: false)   // restore must not play the confirmation tone
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

        if let lat = defaults.object(forKey: Self.userLatitudeKey) as? Double,
           let lon = defaults.object(forKey: Self.userLongitudeKey) as? Double {
            setUserCoordinate(.init(latitude: lat, longitude: lon))
        }

        // Statistics (local-only). `double`/`integer` return 0 for an unset key — the right
        // fresh-install default; the collect flag defaults ON. Then start counting immediately if
        // we're already warming / past today's sunset.
        warmedSecondsBase = defaults.double(forKey: Self.warmedSecondsKey)
        warmSunsetCount = defaults.integer(forKey: Self.warmSunsetCountKey)
        lastWarmSunsetDay = defaults.double(forKey: Self.lastWarmSunsetDayKey)
        statsEnabled = (defaults.object(forKey: Self.statsEnabledKey) as? Bool) ?? true
        updateWarmingStats()

        // First run: no completion flag yet → present onboarding once, here on the main actor (this runs
        // after `engine.start()`). Presented imperatively rather than via a Scene `.onChange`, which has
        // no prior art on `MenuBarExtra` and isn't guaranteed to fire on a cold launch where the menu is
        // never clicked. The completion key is written when the window closes (finished OR dismissed —
        // see OnboardingWindowController), so onboarding never shows twice.
        if defaults.object(forKey: Self.hasCompletedOnboardingKey) == nil {
            OnboardingWindowController.show(model: self)
        }
    }

    /// Neutral-reset + tear down. Call on app quit.
    func shutdown() async {
        flushWarmingSession()   // capture the in-flight warming time before quitting
        observationTask?.cancel()
        observationTask = nil
        frontmostMonitor?.stop()
        await engine?.shutdown()
    }

    // MARK: ── Global intents ────────────────────────────────────────────────

    func setEnabled(_ enabled: Bool, userInitiated: Bool = true) {
        // Optimistic UI (plan §5.2 — no spinners): reflect immediately, engine confirms.
        let changed = enabled != state.isEnabled
        state.isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.isEnabledKey)
        Task { await engine?.setEnabled(enabled) }
        // Tone only on a real user toggle (not the launch-time restore, which passes userInitiated: false).
        if userInitiated, changed { playSoftConfirmationTone(warming: enabled) }
    }

    /// A pleasant chime when the user toggles warming, if "Soft confirmation tone" is on (General tab;
    /// key owned by that tab's `@AppStorage("softConfirmationTone")`). ON plays the bright system "Glass"
    /// chime; OFF plays the SAME chime at a lower playback rate — a deeper, muted/dampened version of it
    /// (founder: muted timbre, not quieter). Fresh, retained player each time so overlapping toggles each
    /// finish (a local player would deallocate before its async playback ends).
    private func playSoftConfirmationTone(warming: Bool) {
        guard UserDefaults.standard.bool(forKey: "softConfirmationTone") else { return }
        // ON = the bright Glass chime; OFF = the SAME chime pitched DOWN ~5 semitones — a deeper,
        // dampened version (founder). (AVAudioPlayer.rate only time-stretches — it PRESERVES pitch — so
        // it was imperceptible; a real pitch shift needs the AVAudioUnitTimePitch graph below.)
        confirmationChime?.play(pitchCents: warming ? 0 : -500)
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
    static let userLatitudeKey = "userLatitude"
    static let userLongitudeKey = "userLongitude"
    static let warmedSecondsKey = "stats.warmedSeconds"
    static let warmSunsetCountKey = "stats.warmSunsetCount"
    static let lastWarmSunsetDayKey = "stats.lastWarmSunsetDay"
    static let statsEnabledKey = "stats.enabled"
    static let hasCompletedOnboardingKey = "hasCompletedOnboarding"

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

    func setUserCoordinate(_ coordinate: TimeZoneCoordinates.Coordinate?) {
        userCoordinate = coordinate
        let defaults = UserDefaults.standard
        if let c = coordinate {
            defaults.set(c.latitude, forKey: Self.userLatitudeKey)
            defaults.set(c.longitude, forKey: Self.userLongitudeKey)
        } else {
            defaults.removeObject(forKey: Self.userLatitudeKey)
            defaults.removeObject(forKey: Self.userLongitudeKey)
        }
        Task { await engine?.setUserCoordinate(coordinate) }
    }

    /// Add one bundle id to the exclusion set (Advanced → Excluded apps "Add app…").
    func addExcludedApp(_ id: String) { setExcludedApps(excludedApps.union([id])) }

    /// Remove one bundle id from the exclusion set (the row's ✕ button).
    func removeExcludedApp(_ id: String) { setExcludedApps(excludedApps.subtracting([id])) }

    // MARK: ── Safety ────────────────────────────────────────────────────────

    func restoreAllDisplays() {
        Task { await engine?.restoreAllDisplays() }
    }

    // MARK: ── Statistics (local-only) ───────────────────────────────────────

    /// Live total warmed time = the persisted base + any in-flight period's elapsed.
    var totalWarmedSeconds: Double {
        warmedSecondsBase + (warmingStartedAt.map { max(0, Date().timeIntervalSince($0)) } ?? 0)
    }

    func setStatsEnabled(_ on: Bool) {
        statsEnabled = on
        UserDefaults.standard.set(on, forKey: Self.statsEnabledKey)
        updateWarmingStats()   // off → closes any open session; on → resumes if currently warming
    }

    func resetStatistics() {
        flushWarmingSession()  // close the open warming run cleanly first
        warmedSecondsBase = 0
        warmSunsetCount = 0
        // Mark today's sunset as already accounted-for so a reset done in the EVENING reads 0, not 1:
        // updateWarmingStats() below would otherwise immediately re-count today. Next count = tomorrow.
        lastWarmSunsetDay = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        warmingStartedAt = nil
        persistStats()
        updateWarmingStats()   // re-open the warming run immediately if still warming
    }

    /// Edge-detect actual warming on each state tick and accrue time (only while `statsEnabled`).
    /// Accrues incrementally each tick so an unclean exit loses at most the un-flushed tail.
    // ponytail: best-effort local stats — steady warming emits no state ticks, so a crash can lose the
    // current run's un-flushed time; add a periodic flush timer only if that ever matters.
    private func updateWarmingStats() {
        updateWarmSunsetCount()
        // "Actively warming" = enabled, the schedule says warm NOW, and not mid-reveal. NOT
        // `statusPhase == .warming`, which is also true in daytime Sunset mode (strength > 0 while the
        // solar ramp applies 0) and would over-count the daylight hours.
        let warmingNow = statsEnabled && state.isEnabled && state.isScheduleActiveNow && !state.isRevealing
        let now = Date()
        if warmingNow {
            if let start = warmingStartedAt {
                warmedSecondsBase += max(0, now.timeIntervalSince(start))   // accrue since last tick
                warmingStartedAt = now
            } else {
                warmingStartedAt = now                                      // begin a new warming run
            }
            persistStats()
        } else if let start = warmingStartedAt {
            warmedSecondsBase += max(0, now.timeIntervalSince(start))       // close the run
            warmingStartedAt = nil
            persistStats()
        }
    }

    /// Count one "warm sunset" per local day: the user is in Sunset mode + enabled and today's real
    /// sunset has passed. The dayKey guard makes the (1440-sample) sunset scan run ~once/day.
    private func updateWarmSunsetCount() {
        guard statsEnabled, state.isEnabled,
              ScheduleModeOption(state.scheduleMode) == .followSunset else { return }
        let cal = Calendar.current
        let dayKey = cal.startOfDay(for: Date()).timeIntervalSince1970
        guard lastWarmSunsetDay != dayKey else { return }
        let coord = userCoordinate ?? TimeZoneCoordinates.current()
        guard let sunset = ScheduleResolver.sunsetTime(forCoordinate: coord, on: Date()),
              Date() >= sunset else { return }
        warmSunsetCount += 1
        lastWarmSunsetDay = dayKey
        persistStats()
    }

    private func flushWarmingSession() {
        guard let start = warmingStartedAt else { return }
        warmedSecondsBase += max(0, Date().timeIntervalSince(start))
        warmingStartedAt = nil
        persistStats()
    }

    private func persistStats() {
        let d = UserDefaults.standard
        d.set(warmedSecondsBase, forKey: Self.warmedSecondsKey)
        d.set(warmSunsetCount, forKey: Self.warmSunsetCountKey)
        d.set(lastWarmSunsetDay, forKey: Self.lastWarmSunsetDayKey)
    }

    // MARK: ── Derived display helpers ───────────────────────────────────────

    /// The current global Kelvin readout, derived from strength + the *actual* warmest point the
    /// engine is using (published in `state`). Previously hardcoded 2700K, which made the readout
    /// disagree with the applied warmth — fixed so the number never lies. (§25 max-warmth.)
    var globalKelvin: Kelvin {
        state.globalWarmth.kelvin(warmestPoint: state.warmestPoint)
    }

    /// True when the screen is actually being warmed right now — drives the menu-bar icon's amber
    /// "active" state. Mirrors the `warmingNow` stats signal (minus the analytics-only `statsEnabled`
    /// gate): enabled, the schedule says warm now, and not mid-reveal.
    var isWarmingActive: Bool {
        state.isEnabled && state.isScheduleActiveNow && !state.isRevealing
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
        case .warming:   return "Warming · \(globalKelvin.displayValue)K"
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

// MARK: - Kelvin display rounding

extension Kelvin {
    /// Display-only: rounded to the nearest 10K so readouts read cleanly (e.g. 2826K → 2830K). The engine
    /// keeps the exact `value` (persistence, schedule, gamma math all use it); this only changes what the
    /// UI shows — and it stops the readout jittering by 1s as the slider drags. (Founder.)
    var displayValue: Int { ((value + 5) / 10) * 10 }
}

// MARK: - ConfirmationChime

/// A tiny reusable AVAudioEngine graph that plays the system "Glass" chime, optionally pitch-shifted.
/// Built once; `play(pitchCents:)` re-triggers it. 0 cents = the bright Glass (warming ON); a negative
/// value plays it deeper + dampened (warming OFF). Real pitch shifting (not `AVAudioPlayer.rate`, which
/// only time-stretches and preserves pitch). Main-actor; the engine idles itself a few seconds after the
/// (short) chime so its render thread doesn't run forever.
@MainActor
private final class ConfirmationChime {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let pitch = AVAudioUnitTimePitch()
    private let file: AVAudioFile
    private var idleTask: Task<Void, Never>?

    init?() {
        guard let f = try? AVAudioFile(forReading: URL(fileURLWithPath: "/System/Library/Sounds/Glass.aiff")) else {
            return nil
        }
        file = f
        engine.attach(player)
        engine.attach(pitch)
        engine.connect(player, to: pitch, format: file.processingFormat)
        engine.connect(pitch, to: engine.mainMixerNode, format: file.processingFormat)
        engine.mainMixerNode.outputVolume = 0.5
    }

    func play(pitchCents: Float) {
        pitch.pitch = pitchCents
        if !engine.isRunning { try? engine.start() }
        guard engine.isRunning else { return }
        player.stop()                       // reset if a prior chime is still scheduled (rapid re-toggle)
        player.scheduleFile(file, at: nil)
        player.play()
        // Stop the engine shortly after the (sub-2s) chime so the render thread doesn't run indefinitely.
        idleTask?.cancel()
        idleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, !self.player.isPlaying else { return }
            self.engine.stop()
        }
    }
}
