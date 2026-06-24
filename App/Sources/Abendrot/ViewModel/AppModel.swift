import Foundation
import Observation
import AppKit
import WarmthKit
import AbendrotControl

// MARK: - AppModel
//
// The `@Observable`, `@MainActor` view-model that sits between SwiftUI and the
// FROZEN `WarmthEngine` actor. It:
// - owns the `WarmthEngine` and `HotkeyService`,
// - consumes `engine.stateUpdates()` and republishes the latest `WarmthState`
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

    /// Which Settings tab is selected — bound to the sidebar so the popover can deep-link (e.g. the
    /// "Per-app exclusions" row opens Settings → Advanced).
    var settingsTab: SettingsTab = .general

    /// Whether the menu-bar icon is shown (Settings → General). When false the app
    /// keeps running and is reachable via the global hotkey + relaunch.
    var showInMenuBar: Bool = true

    /// Reveal-True-Color behaviour: hold (default) vs toggle. Mirrors
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

    /// Airy, synthesized "swoosh" for the advanced popover panel — rising on expand, falling on collapse.
    /// Built lazily on first toggle; nil only if the audio buffers can't be allocated. See `toggleAdvanced()`.
    @ObservationIgnored private lazy var expandSwoosh: SwooshSound? = SwooshSound()

    /// Soft native fire cues for Cozy mode — ignite on ON, snuff on OFF.
    @ObservationIgnored private lazy var cozyFireSound: CozyFireSound? = CozyFireSound()

    // MARK: Engine wiring (nil in previews)

    private let engine: WarmthEngine?
    private var hotkeyService: HotkeyService?
    private var frontmostMonitor: FrontmostAppMonitor?
    private var observationTask: Task<Void, Never>?

    // MARK: Control surface

    /// Regenerated once per app launch. Lets the CLI tell "this is the same running instance" apart
    /// from a relaunch even if the pid is reused. Written into every `ControlStateSnapshot`.
    @ObservationIgnored private let appLaunchID = UUID().uuidString

    /// The `requestID` of the last control message this app applied. The CLI polls
    /// `state.json.lastAppliedRequestID` to confirm its own command landed (the live ack).
    @ObservationIgnored private(set) var lastAppliedRequestID: String?

    /// Distributed-notification observer token for `settingsChanged` (CLI/AI control). Registered in
    /// `start()`, removed in `shutdown()`.
    @ObservationIgnored private var controlObserver: NSObjectProtocol?

    /// Pending reveal auto-end task from a `reveal` control action (cancelled if superseded).
    @ObservationIgnored private var controlRevealTask: Task<Void, Never>?

    // MARK: Init

    /// Live initializer — owns a real engine. Call `start()` from the App entry.
    init(configuration: EngineConfiguration = EngineConfiguration()) {
        UserDefaults.standard.register(defaults: ["softConfirmationTone": true])
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
                // Publish the live control snapshot every tick so `abendrot status` always reflects
                // current runtime truth (ponytail: small atomic write per tick; add a coalescing
                // throttle only if it ever measurably janks).
                self?.writeControlSnapshot()
            }
        }
        // Observe CLI/AI control messages. The CLI posts with `deliverImmediately: true`,
        // so a command applies even when the app is idle. Same login session only — never
        // postToAllSessions. Torn down in `shutdown()`. The block runs on `.main`; under Swift 6 the
        // block isn't statically MainActor-isolated, so hop with `assumeIsolated` (it really is main).
        controlObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(AbendrotControl.settingsChangedNotification),
            object: nil,
            queue: .main
        ) { [weak self] note in
            // Decode HERE, off-actor: `ControlMessage.from(userInfo:)` is pure value work and the
            // non-Sendable `Notification`/`userInfo` never crosses the actor hop — only the decoded
            // `ControlMessage` (a Sendable value, or nil for the raw-`defaults` fallback) does. This
            // satisfies Swift 6 strict concurrency without an `@unchecked` escape hatch.
            let decoded = ControlMessage.from(userInfo: note.userInfo)
            MainActor.assumeIsolated {
                self?.handleControlMessage(decoded)
            }
        }
        // Start the engine, THEN replay persisted user state in the same task so the
        // restore is ordered strictly after start() — avoiding a reentrancy race where it could
        // land before the engine finishes booting.
        Task { [weak self] in
            await engine.start()
            self?.applyPersistedState()
            // Write an initial snapshot so the CLI sees a live app immediately, before the first
            // engine state tick (a healthy idle app may not emit one for a while).
            self?.writeControlSnapshot()
        }
    }

    /// Replay persisted user state through the normal setters so the engine and the published
    /// `state` converge exactly as a live interaction would. Called once from `start()`, strictly
    /// after `engine.start()`. Only keys explicitly written before are restored — a fresh install
    /// keeps the engine's defaults.
    private func applyPersistedState() {
        // Restore the reloadable user settings (warmth, mode, enabled, …) through the shared path
        // the CLI/AI control surface also uses, so launch and a live reload converge identically.
        reloadUserSettingsFromDisk()

        // ── Launch-only tail (NEVER reload these) ────────────────────────────────────────────────
        // Everything below is a cold-launch-only side effect. It lives ONLY here, never in
        // `reloadUserSettingsFromDisk()`, so a settings reload triggered by a CLI notification can
        // never re-pop onboarding or double-count the stats.
        let defaults = UserDefaults.standard

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

    /// Re-read the reloadable user settings from the app's preference domain and replay them through
    /// the normal setters. Called once on launch (from `applyPersistedState()`) and again whenever a
    /// `settingsChanged` notification arrives with no decodable payload (the raw-`defaults`
    /// compatibility path, plan) — so this method holds ONLY settings, never the launch-only
    /// stats/onboarding side effects.
    ///
    /// Reads use **CFPreferences against the app domain**, not `UserDefaults.standard`: a sibling
    /// process (the `abendrot` CLI, or a bare `defaults write`) may have changed the on-disk plist,
    /// and the running app's `UserDefaults` cache is not guaranteed to reflect a cross-process write.
    /// `CFPreferencesAppSynchronize` drops the cache first so each read sees the latest persisted value.
    func reloadUserSettingsFromDisk() {
        let domain = AbendrotControl.preferenceDomain as CFString
        CFPreferencesAppSynchronize(domain)

        // Warmest point (the slider's warmest end / hybrid expanded-range pick). Clamp on read:
        // only restore a sane, warm ceiling (500…3400K). `Kelvin.init` already floors at 500; the
        // upper clamp guards against any future writer persisting a non-warm value that would
        // neuter warming. The only writer today is the Maximum-warmth control.
        if let saved = cfPrefInt(PreferenceKey.warmestPointKelvin),
           saved <= Kelvin.ceilingCoolBound.value {
            // One-time migration to the two-state ceiling (Cozy is now derived from
            // warmestPoint < 1900): the granular slider was removed, so any persisted value in the
            // band 1900 < wp ≤ 3400 is stale and makes the Cozy round-trip incoherent. Snap it up to
            // everydayWarmest (1900) so the persisted state matches the 2-state ceiling and
            // setCozy(false)→1900 is correct. setWarmestPoint re-persists, so this self-heals on load
            // and is idempotent on any later reload.
            let migrated = saved > Kelvin.everydayWarmest.value ? Kelvin.everydayWarmest.value : saved
            setWarmestPoint(Kelvin(migrated))
        }

        // Schedule mode (Codable JSON — carries associated values). If the blob is ever malformed
        // (schema drift, a renamed case, a partial write), drop the key so it re-derives cleanly
        // rather than silently stranding the user on the default — the "it worked then broke" class
        // exists to kill.
        if let data = cfPrefData(PreferenceKey.scheduleMode) {
            if let mode = try? JSONDecoder().decode(ScheduleMode.self, from: data) {
                setScheduleMode(mode, userInitiated: false)   // restore must not tick
            } else {
                CFPreferencesSetAppValue(PreferenceKey.scheduleMode as CFString, nil, domain)
                CFPreferencesAppSynchronize(domain)
            }
        }

        // Nightly warmth strength. A *missing* key stays the engine's 0.7 out-of-box default instead
        // of being clobbered to 0.0. A *persisted* 0.0 is a real user choice (slider dragged to off)
        // and is intentionally honored — distinct from unset.
        if let strength = cfPrefDouble(PreferenceKey.globalWarmthStrength) {
            setGlobalWarmth(strength)
        }

        // Master toggle last. The final converged engine state is order-independent — each setter
        // sets one box field and the engine recomputes from the whole box — so this is a mild nicety,
        // not a correctness requirement. (Any brief default-state flash at launch comes from the
        // engine's initial state-stream snapshot landing before these restores publish; this ordering
        // doesn't affect that — the published state converges once the engine applies the restores.)
        if let enabled = cfPrefBool(PreferenceKey.isEnabled) {
            setEnabled(enabled, userInitiated: false)   // restore must not play the confirmation tone
        }

        // Reveal behaviour. A fresh install keeps the default hold.
        if let raw = cfPrefString(PreferenceKey.revealMode),
           let mode = RevealMode(rawValue: raw) {
            setRevealMode(mode)
        }

        // Excluded apps (suspend warmth while one is frontmost). Fresh install = none.
        if let arr = cfPrefStringArray(PreferenceKey.excludedApps) {
            setExcludedApps(Set(arr))
        }

        if let lat = cfPrefDouble(PreferenceKey.userLatitude),
           let lon = cfPrefDouble(PreferenceKey.userLongitude) {
            setUserCoordinate(.init(latitude: lat, longitude: lon))
        }
    }

    // MARK: ── CFPreferences typed reads (app domain — cross-process safe) ─────
    //
    // Read the app's own preference domain via CFPreferences (not `UserDefaults.standard`) so a
    // value written by a sibling process — the `abendrot` CLI or a `defaults write` — is observed
    // even though the running app's UserDefaults cache may be stale. Each helper bridges the
    // CFPropertyList to the expected Swift type and returns nil for "key unset / wrong type" so the
    // caller keeps the engine default. Callers `CFPreferencesAppSynchronize` once before reading.

    private func cfPrefValue(_ key: String) -> CFPropertyList? {
        CFPreferencesCopyAppValue(key as CFString, AbendrotControl.preferenceDomain as CFString)
    }
    private func cfPrefBool(_ key: String) -> Bool? {
        // CFBoolean and NSNumber both bridge to NSNumber here; `defaults write -bool` and the CLI's
        // CFBoolean write both round-trip through this.
        (cfPrefValue(key) as? NSNumber)?.boolValue
    }
    private func cfPrefInt(_ key: String) -> Int? {
        (cfPrefValue(key) as? NSNumber)?.intValue
    }
    private func cfPrefDouble(_ key: String) -> Double? {
        (cfPrefValue(key) as? NSNumber)?.doubleValue
    }
    private func cfPrefString(_ key: String) -> String? {
        cfPrefValue(key) as? String
    }
    private func cfPrefData(_ key: String) -> Data? {
        cfPrefValue(key) as? Data
    }
    private func cfPrefStringArray(_ key: String) -> [String]? {
        cfPrefValue(key) as? [String]
    }

    // MARK: ── Control surface: apply messages + write snapshot ─

    /// Entry point for a received `settingsChanged` notification, taking the already-decoded message
    /// (decoded off-actor in the observer block). A nil message means no decodable payload was
    /// present — the sender used a raw `defaults write` — so fall back to re-reading the domain.
    /// Factored from the observer so it can be exercised without a live engine.
    func handleControlMessage(_ message: ControlMessage?) {
        if let message {
            applyControlMessage(message)
        } else {
            // No decodable payload → the sender used raw `defaults`. Re-read the domain and
            // converge. This NEVER touches the launch-only stats/onboarding (those stay in
            // `applyPersistedState`'s tail), so a reload can't re-pop onboarding or double-count.
            reloadUserSettingsFromDisk()
            writeControlSnapshot()
        }
    }

    /// Convenience for tests/callers that hold a raw `userInfo` (decodes then dispatches).
    func applyControlMessage(from userInfo: [AnyHashable: Any]?) {
        handleControlMessage(ControlMessage.from(userInfo: userInfo))
    }

    /// Apply a decoded control message through the SAME setters the UI uses (so the engine and the
    /// published `state` converge exactly as a live interaction would), record the ack requestID,
    /// and write a fresh snapshot. Pure model mutation — works in preview mode (engine nil).
    func applyControlMessage(_ message: ControlMessage) {
        if let patch = message.patch {
            apply(patch)
        }
        if let action = message.action {
            apply(action)
        }
        lastAppliedRequestID = message.requestID
        writeControlSnapshot()
    }

    /// Apply a settings patch field-by-field. Each present field is validated (defense in depth —
    /// a malformed notification must not bypass the invariants the UI enforces) and routed through
    /// the existing setter with `userInitiated: false` so no tone/tick plays for a programmatic change.
    private func apply(_ patch: SettingsPatch) {
        if let strength = patch.globalWarmthStrength,
           let valid = try? ControlValidation.validatedStrength(strength) {
            setGlobalWarmth(valid)
        }
        if let kelvin = patch.warmestPointKelvin,
           let valid = try? ControlValidation.validatedKelvin(kelvin) {
            // Enforce the SAME warm-ceiling invariant the cold-launch restore path uses: a warmest
            // point above `ceilingCoolBound` (3400K) neuters warming, so the live control path must
            // clamp to it too (validatedKelvin only guards the full 500…6500 type domain).
            setWarmestPoint(Kelvin(min(valid, Kelvin.ceilingCoolBound.value)))
        }
        if let mode = patch.scheduleMode {
            setScheduleMode(mode.toScheduleMode(), userInitiated: false)
        }
        if let revealRaw = patch.revealMode,
           let valid = try? ControlValidation.validatedRevealMode(revealRaw),
           let mode = RevealMode(rawValue: valid) {
            setRevealMode(mode)
        }
        if let apps = patch.excludedApps {
            setExcludedApps(Set(apps))
        }
        // Coordinate: an explicit clear wins; otherwise apply a complete, VALIDATED lat+lon pair.
        // Defense in depth — a non-finite/out-of-range value (e.g. 1e308) from a malformed control
        // message would otherwise trap downstream in `approximateTimeZone`'s mired/longitude math.
        if patch.clearUserCoordinate == true {
            setUserCoordinate(nil)
        } else if let lat = patch.userLatitude, let lon = patch.userLongitude,
                  let coord = try? ControlValidation.validatedCoordinate(lat: lat, lon: lon) {
            setUserCoordinate(.init(latitude: coord.lat, longitude: coord.lon))
        }
        // Cozy — the expanded-warmth master toggle — routes through `setCozy` (the SAME path the
        // Settings card uses), which moves the ceiling AND re-pins the on-screen warmth. Applied after
        // the raw `warmestPointKelvin` setter so, in the (CLI never sends this) both-set case, the cozy
        // toggle's ceiling wins. No validation needed — it's a plain Bool master toggle.
        if let cozy = patch.cozy {
            setCozy(cozy, userInitiated: false)
        }
        // Enabled last (mild nicety; the engine recomputes from the whole box regardless).
        if let enabled = patch.isEnabled {
            setEnabled(enabled, userInitiated: false)
        }
    }

    /// Apply a transient control action. Reveal is live-only (never persisted): begin the peek and
    /// schedule its end after `holdSeconds` (default 3s), superseding any in-flight reveal task.
    private func apply(_ action: ControlAction) {
        switch action {
        case .reveal(let holdSeconds):
            let hold = holdSeconds ?? 3
            beginReveal()
            controlRevealTask?.cancel()
            controlRevealTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(max(0, hold)))
                guard !Task.isCancelled else { return }
                self?.endReveal()
                self?.writeControlSnapshot()
            }
        }
    }

    /// Encode the current state to `~/Library/Application Support/Abendrot/state.json` atomically.
    /// Called every engine state tick and after each accepted control message. Errors are swallowed
    /// quietly — a failed status write must never disrupt warming.
    func writeControlSnapshot() {
        let info = Bundle.main.infoDictionary
        let snapshot = ControlStateSnapshot(
            appVersion: info?["CFBundleShortVersionString"] as? String ?? "0.0.0",
            appBuild: info?["CFBundleVersion"] as? String ?? "0",
            pid: ProcessInfo.processInfo.processIdentifier,
            appLaunchID: appLaunchID,
            updatedAt: Date(),
            lastAppliedRequestID: lastAppliedRequestID,
            isEnabled: state.isEnabled,
            scheduleMode: ControlScheduleMode(state.scheduleMode),
            isScheduleActiveNow: state.isScheduleActiveNow,
            isRevealing: state.isRevealing,
            globalWarmthStrength: state.globalWarmth.strength,
            globalKelvin: globalKelvin.value,
            warmestPointKelvin: state.warmestPoint.value,
            revealMode: revealMode.rawValue,
            excludedApps: excludedApps.sorted(),
            displays: state.displays.map { display in
                DisplaySnapshot(
                    id: display.id.cgUUID.uuidString,
                    name: display.name,
                    appliedMethod: display.appliedMethod.rawValue,
                    preferredMethod: display.preferredMethod?.rawValue,
                    warmthStrength: display.warmth.strength,
                    warmthOverridden: display.warmthOverridden,
                    isHardwareDDCEnabled: display.isHardwareDDCEnabled,
                    lastError: display.lastError?.message
                )
            }
        )
        do {
            let dir = ControlStateSnapshot.directoryURL()
            try FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(snapshot)
            let fileURL = ControlStateSnapshot.fileURL()
            try data.write(to: fileURL, options: .atomic)
            // The atomic write lands at the default 0644 (world-readable); the dir is already 0700.
            // Tighten the file to 0600 so only the owner can read the snapshot (it carries runtime
            // state). Best-effort — a failed chmod must not disrupt warming.
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            // Best-effort: a status-file failure must not affect the user's warming.
        }
    }

    /// Neutral-reset + tear down. Call on app quit.
    func shutdown() async {
        flushWarmingSession()   // capture the in-flight warming time before quitting
        observationTask?.cancel()
        observationTask = nil
        controlRevealTask?.cancel()
        controlRevealTask = nil
        if let controlObserver {
            DistributedNotificationCenter.default().removeObserver(controlObserver)
            self.controlObserver = nil
        }
        frontmostMonitor?.stop()
        await engine?.shutdown()
    }

    // MARK: ── Global intents ────────────────────────────────────────────────

    func setEnabled(_ enabled: Bool, userInitiated: Bool = true) {
        // Optimistic UI (no spinners): reflect immediately, engine confirms.
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
    /// (by preference: muted timbre, not quieter). Fresh, retained player each time so overlapping toggles each
    /// finish (a local player would deallocate before its async playback ends).
    private func playSoftConfirmationTone(warming: Bool) {
        guard UserDefaults.standard.bool(forKey: "softConfirmationTone") else { return }
        // ON = the bright Glass chime; OFF = the SAME chime pitched DOWN ~5 semitones — a deeper,
        // dampened version . (AVAudioPlayer.rate only time-stretches — it PRESERVES pitch — so
        // it was imperceptible; a real pitch shift needs the AVAudioUnitTimePitch graph below.)
        confirmationChime?.play(pitchCents: warming ? 0 : -500, volume: 0.7)   // ~0.35 effective vs the 0.5 master
    }

    /// A soft tick when the user switches Schedule mode (Sunset · Manual), gated by the SAME
    /// "Soft confirmation tone" pref as the warming chime (General tab). Reuses the Glass graph but
    /// QUIETER and pitched UP into a light "selection" tick — not the warming bloom — and each mode
    /// gets its OWN note (Always-on brighter/higher, Sunset lower), so you hear WHICH mode you picked:
    /// a choice, not an on/off.
    /// Internal (not private) so onboarding can play the same mode tick when its picker is toggled.
    func playSoftModeTone(_ mode: ScheduleMode) {
        guard UserDefaults.standard.bool(forKey: "softConfirmationTone") else { return }
        // ponytail: taste-tune these three by ear — sound is sensory. Cents are vs. the Glass
        // fundamental; both sit ABOVE the warming tones (0 / -500) so they read as a lighter tick, and
        // a major third apart from each other.
        let cents: Float = ScheduleModeOption(mode) == .alwaysOn ? 700 : 300
        confirmationChime?.play(pitchCents: cents, volume: 0.22)   // ~0.11 effective vs the 0.5 master
    }

    /// Flip the popover's advanced panel. Plays the airy swoosh — rising on EXPAND, falling on COLLAPSE
    /// gated by the SAME "Soft confirmation tone" pref as the chimes. The caller wraps this in
    /// `withAnimation` so the panel still animates; the swoosh is just a side effect of the flip.
    func toggleAdvanced() {
        isAdvancedExpanded.toggle()
        guard UserDefaults.standard.bool(forKey: "softConfirmationTone") else { return }
        // ponytail: quiet by ear; tune with the synth knobs in SwooshSound.
        expandSwoosh?.play(opening: isAdvancedExpanded, volume: 0.03)
    }

    private func playCozyFireSound(starting: Bool) {
        guard UserDefaults.standard.bool(forKey: "softConfirmationTone") else { return }
        cozyFireSound?.play(starting: starting)
    }


    func setGlobalWarmth(_ strength: Double) {
        let level = WarmthLevel(strength: strength)
        state.globalWarmth = level
        // Persist the clamped canonical value, not the raw arg.
        UserDefaults.standard.set(level.strength, forKey: Self.globalWarmthStrengthKey)
        Task { await engine?.setWarmth(level) }
    }

    /// Set the global warmth so the *effective Kelvin* lands at (or as near as the curve allows) `target`,
    /// at the current `warmestPoint`. Inverts `WarmthLevel.kelvin(warmestPoint:)` — which is monotonic in
    /// strength — by binary search, so there's no duplicated mired math and it tracks the engine's own
    /// curve exactly. Used by Cozy mode to keep the screen where it is while the warmest ceiling expands.
    func setGlobalWarmthToKelvin(_ target: Kelvin) {
        let wp = state.warmestPoint
        var lo = 0.0, hi = 1.0
        // kelvin() is non-increasing in strength (warmer = lower K): if a strength is warm enough
        // (≤ target), we don't need more; otherwise we need more.
        for _ in 0..<24 {
            let mid = (lo + hi) / 2
            if WarmthLevel(strength: mid).kelvin(warmestPoint: wp).value <= target.value {
                hi = mid
            } else {
                lo = mid
            }
        }
        setGlobalWarmth((lo + hi) / 2)
    }

    func setScheduleMode(_ mode: ScheduleMode, userInitiated: Bool = true) {
        // Compare at the UI grain (Sunset · Manual): the dormant cases (.solar/.custom/...) all read
        // as Sunset, so re-selecting one is not a user-visible change and must not tick.
        let changed = ScheduleModeOption(mode) != ScheduleModeOption(state.scheduleMode)
        state.scheduleMode = mode
        // ScheduleMode carries associated values (.solar/.custom) → encode as Codable JSON,
        // not a bare string.
        if let data = try? JSONEncoder().encode(mode) {
            UserDefaults.standard.set(data, forKey: Self.scheduleModeKey)
        }
        Task { await engine?.setScheduleMode(mode) }
        // Tick only on a real user-initiated switch (not the launch-time restore, userInitiated: false).
        if userInitiated, changed { playSoftModeTone(mode) }
    }

    // MARK: ── Persistence ───────────────────────────────────────────
    //
    // User-facing engine state that must survive relaunch. `warmestPoint` already
    // persisted (the hybrid expanded-range pick); this extends the same pattern to the
    // master toggle, the nightly warmth, and the schedule mode so the app reopens exactly
    // as the user left it instead of resetting to disabled / off / follow-Night-Shift every
    // launch (a major "it worked then broke" contributor — Session-5 RESULTS).
    //
    // Each value is written in its setter and restored once in `start()` *after*
    // `engine.start()` by replaying that same setter, so the engine and the published
    // `state` converge through the path a live interaction would take. Reads use
    // `object(forKey:)` (NOT `bool`/`double`, which collapse "never saved" into false/0.0)
    // so a fresh install keeps the engine's defaults — notably the 0.7 out-of-box warmth,
    // which a `double(forKey:)` miss would silently clobber to 0.0.
    // The CLI control-surface keys are sourced from the shared `PreferenceKey` (AbendrotControl) so
    // the app and the `abendrot` CLI can never drift on a key string. The `*Key` names are kept so
    // the rest of AppModel is untouched — only the right-hand side now points at the shared constant.
    static let warmestPointKey = PreferenceKey.warmestPointKelvin
    static let isEnabledKey = PreferenceKey.isEnabled
    static let globalWarmthStrengthKey = PreferenceKey.globalWarmthStrength
    static let scheduleModeKey = PreferenceKey.scheduleMode
    static let revealModeKey = PreferenceKey.revealMode
    static let excludedAppsKey = PreferenceKey.excludedApps
    static let userLatitudeKey = PreferenceKey.userLatitude
    static let userLongitudeKey = PreferenceKey.userLongitude
    // Stats + onboarding keys stay local — they are NOT part of the CLI control surface.
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

    /// Cozy mode — the master "expanded warmth" toggle, in ONE place so the Settings card, onboarding,
    /// and the `abendrot cozy on|off` CLI all share this exact path (UI and CLI can never disagree).
    ///
    /// ON drops the warmest-point ceiling to `Kelvin.warmestSupported` (~500K — the deepest candle &
    /// ember). OFF restores the everyday `Kelvin.everydayWarmest` (1900K) ceiling. In both directions
    /// the *on-screen warmth holds*: we capture the current effective Kelvin first, move the ceiling,
    /// then re-pin the screen to that same Kelvin via `setGlobalWarmthToKelvin` — so expanding the
    /// range never jumps the picture. The one richer-than-pin nuance is Always-on turning cozy ON:
    /// there the screen warms straight to the new maximum (1.0), matching the Settings card today.
    func setCozy(_ on: Bool, userInitiated: Bool = true) {
        let changed = on != (state.warmestPoint.value < Kelvin.everydayWarmest.value)
        if on {
            // Turning ON: unlock the deepest candle & ember (~500K). In Always-on, warm to that maximum
            // right away; otherwise keep the current warmth exactly where it is and just hand over the
            // headroom to push warmer. Capture BEFORE moving the ceiling so the pin uses the old Kelvin.
            let current = globalKelvin
            setWarmestPoint(Kelvin.warmestSupported)
            if ScheduleModeOption(state.scheduleMode) == .alwaysOn {
                setGlobalWarmth(1.0)
            } else {
                setGlobalWarmthToKelvin(current)
            }
        } else {
            // Turning OFF: restore the everyday 1900K ceiling, keeping the screen where it is — a
            // deeper-than-everyday pick is pulled up to exactly 1900K (the new cap).
            let restore = Kelvin(max(globalKelvin.value, Kelvin.everydayWarmest.value))
            setWarmestPoint(Kelvin.everydayWarmest)
            setGlobalWarmthToKelvin(restore)
        }
        if userInitiated, changed { playCozyFireSound(starting: on) }
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

    /// Switch the reveal behaviour between hold and toggle. `HotkeyService.mode` already honours
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
        // Persist a sorted [String] (stable, plist-native) so the set survives relaunch.
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

    /// "h:mm a" formatter for the sunset readout, built once (DateFormatter is expensive to create).
    private static let sunsetReadoutFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.timeZone = .current
        return formatter
    }()

    /// Live "Today's sunset ≈ h:mm a" for the chosen (or auto) location — zero permission, zero network
    /// (time-zone coordinates). Shared by Settings → Schedule and onboarding so the picked city feels real.
    var todaysSunsetReadout: String {
        let coordinate = userCoordinate ?? TimeZoneCoordinates.current()
        guard let sunset = ScheduleResolver.sunsetTime(forCoordinate: coordinate, on: Date()) else {
            return "Today's sunset: —"
        }
        // Display zone: Auto = the system zone; a picked city = its real IANA zone (looked up from the
        // city) so the sunset prints in that city's local clock with a proper DST-aware abbreviation
        // (PST/PDT, EST/EDT). Longitude zone is only a last-ditch fallback. Mutating the shared formatter
        // is safe: AppModel is @MainActor.
        let zone: TimeZone
        if userCoordinate == nil {
            zone = .current
        } else if let city = MajorCities.all.first(where: { $0.coordinate == coordinate }),
                  let cityZone = TimeZone(identifier: city.timeZone) {
            zone = cityZone
        } else {
            zone = TimeZoneCoordinates.approximateTimeZone(forLongitude: coordinate.longitude) ?? .current
        }
        let formatter = Self.sunsetReadoutFormatter
        formatter.timeZone = zone
        // Show a real, named abbreviation ("EDT", "PDT") but NOT a bare "GMT-5" offset — a picked city's
        // longitude-derived zone has no place name, and the city name is already in the field .
        let time = formatter.string(from: sunset)
        if let abbr = zone.abbreviation(for: sunset), !abbr.hasPrefix("GMT") {
            return "Today's sunset ≈ \(time) \(abbr)"
        }
        return "Today's sunset ≈ \(time)"
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

    /// `totalWarmedSeconds` rendered as "2d 17h 41m 46s", dropping leading-zero top units but always
    /// keeping at least m + s. Shared by the Statistics tab and the About window so the two read the same.
    var warmedDurationString: String {
        let s = max(0, Int(totalWarmedSeconds))
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60, sec = s % 60
        var parts: [String] = []
        if d > 0 { parts.append("\(d)d") }
        if h > 0 || d > 0 { parts.append("\(h)h") }
        parts.append("\(m)m")
        parts.append("\(sec)s")
        return parts.joined(separator: " ")
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
        // "Actively warming" = enabled, the schedule says warm NOW, and not mid-reveal. NOT merely
        // "enabled with strength > 0", which is also true in daytime Sunset mode (the solar ramp applies
        // 0 while the schedule is inactive) and would over-count the daylight hours.
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
    /// disagree with the applied warmth — fixed so the number never lies.
    var globalKelvin: Kelvin {
        state.globalWarmth.kelvin(warmestPoint: state.warmestPoint)
    }

    /// The Kelvin the engine is ACTUALLY applying right now (the ramped target), vs `globalKelvin`
    /// which is the configured peak. Equal in Always-on; in Sunset it tracks the time-of-day ramp
    /// (neutral by day → peak by night). Drives the live, locked popover readout.
    var liveKelvin: Kelvin {
        state.resolvedWarmth.kelvin(warmestPoint: state.warmestPoint)
    }

    /// In Sunset mode the popover warmth slider is LOCKED: warmth is set automatically by time of
    /// day, so the menu-bar control shows the live value read-only and points to Settings for the
    /// maximum. (Always-on keeps the slider editable; off hides it.)
    var isWarmthLockedInSunset: Bool {
        state.isEnabled && ScheduleModeOption(state.scheduleMode) == .followSunset
    }

    /// True when the screen is actually being warmed right now — drives the menu-bar icon's amber
    /// "active" state. Mirrors the `warmingNow` stats signal (minus the analytics-only `statsEnabled`
    /// gate): enabled, the schedule says warm now, and not mid-reveal.
    var isWarmingActive: Bool {
        state.isEnabled && state.isScheduleActiveNow && !state.isRevealing
    }

    // MARK: ── Incompatibility ("can only be tinted") detection — ──────────

    /// A display can only be TINTED when no true-warm path is available to it: gamma is not
    /// supported on this chip/OS (or private APIs are off) AND it is not DDC-capable. Capability-
    /// based, so it reads honestly even before warming is enabled. Lives here (not in a view) so the
    /// app-level banner in PopoverView and the per-display rows in AdvancedExpansion share one
    /// source of truth.
    func isTintOnly(_ display: DisplayState) -> Bool {
        let priv = state.privateAPIsEnabled
        let gammaPossible = priv && display.capabilities.gamma.isSupported
        let ddcPossible = priv && display.capabilities.hardware.isSupported
        return !(gammaPossible || ddcPossible)
    }
}

// MARK: - Capability

extension Capability {
    /// True when this capability is `.supported`. Shared by `AppModel.isTintOnly` and the Settings →
    /// Displays method/warning logic so the "can this display be truly warmed?" test reads one way.
    var isSupported: Bool {
        if case .supported = self { return true }
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
