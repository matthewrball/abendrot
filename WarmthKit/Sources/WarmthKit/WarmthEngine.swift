import Foundation
import WarmthCore
import DisplayServices
import HardwareDDC
import OverlayRenderer
import NightShiftBridge
import Logging

// MARK: - WarmthEngine

/// The public actor the app drives. The only WarmthKit type the app constructs.
///
/// Holds the three warmth layers behind the `WarmthBackend` protocol (overlay default, DDC
/// opt-in, gamma capability-classified) and publishes `WarmthState` through an `AsyncStream`.
/// Internals are minimal/TODO for this scaffold milestone; the public surface is complete and
/// actor/Sendable-correct under Swift 6 strict concurrency.
public actor WarmthEngine {

    // MARK: Stored configuration & state

    private let configuration: EngineConfiguration
    private var box: WarmthStateBox

    // MARK: Backends (behind the protocol)

    private let overlay: any WarmthBackend
    private let gamma: any WarmthBackend
    private let ddc: any WarmthBackend
    private let registry: DisplayRegistry
    private let nightShiftFollower: SystemNightShiftStateFollower

    /// Persisted DDC native-state snapshot + write-ahead dirty flag, shared with the DDC transport
    /// so launch-time recovery (engine-driven) and native-gain restore (transport-driven) read the
    /// same record (§9). Crash/exit handlers can't reliably do async DDC, so recovery is driven
    /// from this store on the next `start()`, not from teardown hooks (invariant 7).
    private let snapshotStore: any DDCSnapshotStore

    /// Test-only fixed display list. When non-nil the engine is in test mode: it enumerates these
    /// identities instead of the live CoreGraphics registry, and does NOT start the real system
    /// observers (hotplug is driven by `simulateReconfiguration(present:)`).
    private var injectedDisplays: [DisplayIdentity]?

    /// Display keys a PRIOR run left warmed (read from `snapshotStore` at launch). Each is restored
    /// to native BEFORE this run applies anything, then drained so it can't re-fire mid-session.
    private var staleKeys: Set<String> = []

    /// Per-display user settings retained by STABLE identity even while a display is disconnected,
    /// so warmth / DDC opt-in / layer override survive an unplug→replug (contract §3 identity,
    /// §9 "re-applies per-display state"). Keyed by `persistentKey`.
    private var rememberedSettings: [String: RememberedDisplaySettings] = [:]

    private struct RememberedDisplaySettings {
        var warmth: WarmthLevel
        var isHardwareDDCEnabled: Bool
        var preferredMethod: DisplayMethod?
    }

    // MARK: System layers (hotplug / wake re-baseline)

    /// Hotplug / mode-change observer (CoreGraphics reconfiguration callback).
    private let reconfigurationObserver: DisplayReconfigurationObserver
    /// System-wake observer (NSWorkspace) — main-actor, owned by the umbrella.
    private let wakeObserver: SystemWakeObserver
    /// The long-lived task that coalesces reconfiguration + wake bursts and re-baselines once
    /// per quiet window. Cancelled in `shutdown()`.
    private var rebaselineTask: Task<Void, Never>?
    /// Debounce policy (the timing arithmetic is pure / unit-tested in `ReconfigurationDebounce`).
    private let rebaselineDebounceWindow: Duration = .milliseconds(400)

    // MARK: Observation

    /// One continuation per active `stateUpdates()` subscriber.
    private var continuations: [UUID: AsyncStream<WarmthState>.Continuation] = [:]

    private let logger = Logger(label: "com.abendrot.WarmthKit.WarmthEngine")

    // MARK: Init

    public init(configuration: EngineConfiguration) {
        // Production wiring: the DDC transport and the engine share ONE snapshot store so the
        // transport's persisted native gains and the engine's dirty flag stay coherent across a
        // crash/relaunch (§9).
        let store = FileDDCSnapshotStore()
        let transport = IOAVServiceDDCTransport(store: store)
        self.init(
            configuration: configuration,
            overlay: OverlayBackend(),
            gamma: GammaBackend(),
            ddc: DDCBackend(transport: transport),
            snapshotStore: store,
            nightShiftFollower: SystemNightShiftStateFollower(),
            injectedDisplays: nil
        )
    }

    /// Designated initializer with injectable layers + snapshot store. Internal so it does not
    /// widen the frozen public surface; the public `init(configuration:)` delegates here with
    /// production defaults, and `test(...)` uses it to inject fakes for the failure-injection suite
    /// (§21‑E14) — neither changes the contract.
    init(
        configuration: EngineConfiguration,
        overlay: any WarmthBackend,
        gamma: any WarmthBackend,
        ddc: any WarmthBackend,
        snapshotStore: any DDCSnapshotStore,
        nightShiftFollower: SystemNightShiftStateFollower,
        injectedDisplays: [DisplayIdentity]?
    ) {
        self.configuration = configuration
        self.overlay = overlay
        self.gamma = gamma
        self.ddc = ddc
        self.snapshotStore = snapshotStore
        self.registry = DisplayRegistry()
        self.nightShiftFollower = nightShiftFollower
        self.reconfigurationObserver = DisplayReconfigurationObserver()
        self.wakeObserver = SystemWakeObserver()
        self.injectedDisplays = injectedDisplays
        self.box = WarmthStateBox(
            value: WarmthState(
                isEnabled: false,
                scheduleMode: configuration.defaultScheduleMode,
                // A sensible non-zero default so flipping the master toggle visibly warms even
                // before the user touches the slider. With the warmest point at ~1000K (deep
                // firelight) this lands around a comfortable ~2700K evening warmth, leaving most of
                // the slider as headroom to go MUCH warmer toward the firelight end, or softer.
                // (§25: "enabled but never warms" + founder wants a much warmer max.)
                globalWarmth: WarmthLevel(strength: 0.25),
                warmestPoint: configuration.defaultWarmestPoint,
                privateAPIsEnabled: configuration.startWithPrivateAPIsEnabled
            )
        )
    }

    /// Test factory for the failure-injection suite. Picks backends by `method` (filling absent
    /// layers with a neutral no-op), injects a snapshot store and a fixed display list, and runs in
    /// test mode (no real system observers). Internal — not part of the public surface.
    static func test(
        configuration: EngineConfiguration = EngineConfiguration(),
        backends: [any WarmthBackend],
        store: any DDCSnapshotStore,
        displays: [DisplayIdentity]
    ) -> WarmthEngine {
        func backend(_ method: DisplayMethod) -> any WarmthBackend {
            backends.first { $0.method == method } ?? NoopBackend(method: method)
        }
        return WarmthEngine(
            configuration: configuration,
            overlay: backend(.overlay),
            gamma: backend(.gamma),
            ddc: backend(.hardware),
            snapshotStore: store,
            nightShiftFollower: SystemNightShiftStateFollower(),
            injectedDisplays: displays
        )
    }

    // MARK: ── Lifecycle ───────────────────────────────────────────────────────

    /// Build the display registry, run launch-time stale-state recovery, baseline
    /// capabilities, then apply current settings. Safe to call once at app launch.
    public func start() async {
        // Live system integration only outside test mode (tests are hermetic: they never touch the
        // real CBBlueLightClient / CoreGraphics observers, and drive reconfiguration explicitly via
        // `simulateReconfiguration`).
        if injectedDisplays == nil {
            // Start the read-only Night Shift follower. Its change hook re-applies the schedule so
            // following the system state is live, not just sampled at launch. The follower degrades
            // cleanly to `.unknown(.privateSymbolUnavailable)` when CBBlueLightClient is unavailable
            // or the kill switch is engaged, and the engine falls back to the evening window.
            nightShiftFollower.start { [weak self] in
                // Runs on an arbitrary CoreBrightness queue → hop onto the actor.
                Task { await self?.handleNightShiftChange() }
            }
            // Start the hotplug + wake observers and the coalescing re-baseline loop.
            await startSystemObservers()
        }

        // Launch-time stale-state recovery (§9, invariant 7). A prior run may have died (crash /
        // SIGKILL) with DDC gain or gamma left altered; crash/exit handlers can't reliably do async
        // DDC, so we recover here. Capture the persisted dirty set, build display rows WITHOUT
        // applying, restore every stale display to native FIRST, then apply current settings.
        staleKeys = await snapshotStore.dirtyKeys()
        await rebuildDisplayRows(for: currentDisplays())
        await recoverStaleDisplays()
        await reapply()
        publish()
    }

    /// Neutral-reset every display via every active layer, then tear down. Called on quit.
    public func shutdown() async {
        rebaselineTask?.cancel()
        rebaselineTask = nil
        reconfigurationObserver.stop()
        await wakeObserver.stop()
        nightShiftFollower.stop()

        for display in box.value.displays {
            try? await overlay.reset(display.id)
            try? await gamma.reset(display.id)
            // Restore native DDC gain and, on a verified restore, clear the write-ahead dirty flag
            // so a clean quit doesn't trigger launch-time recovery next run; a failed restore keeps
            // it dirty for recovery.
            await restoreHardwareAndClearDirty(display.id)
        }
        finishContinuations()
    }

    /// Re-resolve the schedule when the followed Night Shift state changes. (Re-apply only; the
    /// display set is unchanged, so no re-baseline is needed.)
    private func handleNightShiftChange() async {
        await reapply()
        publish()
    }

    // MARK: ── Global controls ──────────────────────────────────────────────────

    public func setEnabled(_ enabled: Bool) async {
        box.value.isEnabled = enabled
        await reapply()
        publish()
    }

    public func setWarmth(_ level: WarmthLevel) async {
        box.value.globalWarmth = level
        await reapply()
        publish()
    }

    public func setScheduleMode(_ mode: ScheduleMode) async {
        box.value.scheduleMode = mode
        await reapply()
        publish()
    }

    public func setWarmestPoint(_ kelvin: Kelvin) async {
        box.value.warmestPoint = kelvin
        await reapply()
        publish()
    }

    // MARK: ── Reveal True Color ─────────────────────────────────────────────────

    /// Suspend warmth across ALL displays (true colour). Idempotent.
    public func beginReveal() async {
        guard !box.value.isRevealing else { return }
        box.value.isRevealing = true
        await reapply()
        publish()
    }

    /// Ease warmth back across all displays (~100–150ms). Idempotent.
    public func endReveal() async {
        guard box.value.isRevealing else { return }
        box.value.isRevealing = false
        // TODO(milestone): ease back over ~100–150ms instead of a hard re-apply.
        await reapply()
        publish()
    }

    // MARK: ── Per-display ───────────────────────────────────────────────────────

    public func setWarmth(_ level: WarmthLevel, for id: DisplayIdentity) async {
        guard let index = box.value.displays.firstIndex(where: { $0.id == id }) else { return }
        box.value.displays[index].warmth = level
        rememberSettings(box.value.displays[index])
        await reapply()
        publish()
    }

    /// Force a specific layer for a display, or nil to return to automatic best-available.
    public func setPreferredMethod(_ method: DisplayMethod?, for id: DisplayIdentity) async {
        guard let index = box.value.displays.firstIndex(where: { $0.id == id }) else { return }
        // Record the per-display override; nil → automatic best-available. The layer is resolved
        // (and validated against capability + opt-in + kill switch) in `reapply()`, never written
        // straight to `appliedMethod` — that conflation is what would trap a display off.
        box.value.displays[index].preferredMethod = method
        rememberSettings(box.value.displays[index])
        await reapply()
        publish()
    }

    /// DDC opt-in toggle. No-op (returns .unsupported in state) where DDC isn't capable.
    public func setHardwareDDCEnabled(_ enabled: Bool, for id: DisplayIdentity) async {
        guard let index = box.value.displays.firstIndex(where: { $0.id == id }) else { return }
        box.value.displays[index].isHardwareDDCEnabled = enabled
        rememberSettings(box.value.displays[index])
        await reapply()
        publish()
    }

    /// Retain a display's user settings by stable identity so they survive a disconnect→reconnect.
    private func rememberSettings(_ display: DisplayState) {
        rememberedSettings[display.id.persistentKey] = RememberedDisplaySettings(
            warmth: display.warmth,
            isHardwareDDCEnabled: display.isHardwareDDCEnabled,
            preferredMethod: display.preferredMethod
        )
    }

    /// Per-app exclusions (v1.0 = per-app only; per-website is future, §21‑E8).
    public func setExcludedApps(_ bundleIDs: Set<String>) async {
        // TODO(milestone): persist exclusions and suspend warmth while an excluded app is front.
        box.excludedApps = bundleIDs
        publish()
    }

    // MARK: ── Safety ────────────────────────────────────────────────────────────

    /// Emergency "Restore Displays": neutral gamma + overlay teardown + DDC native-state
    /// restore for every known display. Surfaced as a menu command. Always available.
    public func restoreAllDisplays() async {
        let ids = box.value.displays.map(\.id)   // capture before awaits
        for id in ids {
            try? await gamma.reset(id)
            try? await overlay.reset(id)
            await restoreHardwareAndClearDirty(id)
            if let index = box.value.displays.firstIndex(where: { $0.id == id }) {
                box.value.displays[index].appliedMethod = .off
                box.value.displays[index].lastError = nil
            }
        }
        publish()
    }

    /// Disable all private-API (DDC + Night Shift) paths and fall back to overlay-only.
    public func setPrivateAPIsEnabled(_ enabled: Bool) async {
        box.value.privateAPIsEnabled = enabled
        await reapply()
        publish()
    }

    // MARK: ── Observation ───────────────────────────────────────────────────────

    public var state: WarmthState {
        get async { box.value }
    }

    /// The UI renders from this stream. Emits on every meaningful state change.
    public func stateUpdates() -> AsyncStream<WarmthState> {
        let id = UUID()
        // Build the continuation OUTSIDE the (escaping, @Sendable) AsyncStream builder closure and
        // register it here in the actor-isolated context — mutating `continuations` inside the
        // builder closure violates Swift 6 actor isolation.
        let (stream, continuation) = AsyncStream<WarmthState>.makeStream()
        continuations[id] = continuation
        continuation.yield(box.value)
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeContinuation(id) }
        }
        return stream
    }

    private func removeContinuation(_ id: UUID) {
        continuations[id] = nil
    }

    // MARK: ── System observers (hotplug / wake re-baseline) ─────────────────────

    /// Start the reconfiguration + wake observers and the single coalescing loop that turns a
    /// burst of either signal into exactly one debounced re-baseline. Debouncing/re-baseline
    /// living in the engine is the contract (§21‑E4); the observers themselves are dumb emitters.
    private func startSystemObservers() async {
        reconfigurationObserver.start()
        await wakeObserver.start()

        // Snapshot the streams before entering the detached loop (the observers are immutable).
        let reconfigEvents = reconfigurationObserver.events
        let wakeEvents = wakeObserver.events
        let window = rebaselineDebounceWindow

        rebaselineTask = Task { [weak self] in
            // A local debounce policy: coalesce events arriving within `window` of each other and
            // re-baseline once after the burst goes quiet. The arithmetic is the pure,
            // unit-tested `ReconfigurationDebounce`; here we only drive its timers.
            await withTaskGroup(of: Void.self) { group in
                // One child drains reconfiguration events, one drains wake events; both funnel
                // into the same actor-side coalescer.
                group.addTask { [weak self] in
                    for await _ in reconfigEvents {
                        await self?.coalesceRebaseline(window: window)
                    }
                }
                group.addTask { [weak self] in
                    for await _ in wakeEvents {
                        await self?.coalesceRebaseline(window: window)
                    }
                }
            }
        }
    }

    /// The pure debounce policy (timing arithmetic) for the in-flight burst. The actor below
    /// drives its timers; the policy itself is unit-tested headlessly in `ReconfigurationDebounce`.
    private lazy var rebaselineDebounce = ReconfigurationDebounce(window: rebaselineDebounceWindow)
    /// The monotonic clock the debounce times against. Only differences are used.
    private let rebaselineClock = ContinuousClock()
    /// The fixed origin the monotonic seconds are measured from (so the policy sees a stable,
    /// increasing seconds value across the run).
    private let rebaselineEpoch = ContinuousClock().now

    /// Seconds elapsed since the engine's clock epoch — the monotonic domain the debounce policy
    /// records against.
    private func nowSeconds() -> Double {
        let d = rebaselineEpoch.duration(to: rebaselineClock.now).components
        return Double(d.seconds) + Double(d.attoseconds) / 1e18
    }

    /// Record a reconfiguration/wake event and ensure exactly one debounced re-baseline fires for
    /// the burst. Re-entrant-safe on the actor: overlapping events extend the burst's quiet window
    /// (via `ReconfigurationDebounce`) rather than scheduling a second re-baseline.
    private func coalesceRebaseline(window: Duration) async {
        // `record` returns true only when this event STARTS a new burst; subsequent events while a
        // fire is pending merely push the deadline out and return false, so only one waiter runs.
        guard rebaselineDebounce.record(at: nowSeconds()) else { return }

        // Drain the burst: sleep for the remaining quiet window, re-checking after each nap since
        // late events extend it.
        while let remaining = rebaselineDebounce.remainingDelay(at: nowSeconds()), remaining > 0 {
            try? await rebaselineClock.sleep(for: .seconds(remaining))
            if Task.isCancelled { rebaselineDebounce.consumeFire(); return }
        }

        rebaselineDebounce.consumeFire()
        guard !Task.isCancelled else { return }
        await rebaselineDisplays()
        publish()
    }

    // MARK: ── Internals ─────────────────────────────────────────────────────────

    /// The currently connected displays — the injected fixed list in test mode, else a live read
    /// of the CoreGraphics registry.
    private func currentDisplays() -> [DisplayIdentity] {
        injectedDisplays ?? registry.currentDisplays()
    }

    /// Re-read the connected displays, rebuild their baseline rows, recover any prior-run stale
    /// state for a display that just (re)appeared, then re-apply. The hotplug/wake path.
    private func rebaselineDisplays() async {
        await rebuildDisplayRows(for: currentDisplays())
        await recoverStaleDisplays()
        await reapply()
    }

    /// (Re)build the `DisplayState` rows for `identities` WITHOUT applying — so launch-time recovery
    /// can restore native state before any warm write. Preserves per-display settings across the
    /// rebuild by stable identity.
    private func rebuildDisplayRows(for identities: [DisplayIdentity]) async {
        var rows: [DisplayState] = []
        rows.reserveCapacity(identities.count)

        for identity in identities {
            let hardwareCap = await ddc.classify(identity)
            let gammaCap = await gamma.classify(identity)
            let overlayCap = await overlay.classify(identity)

            let caps = DisplayCapabilities(
                identity: identity,
                hardware: mapToDDCCaps(hardwareCap),
                gamma: gammaCap,
                overlay: overlayCap,
                recommendedMethod: recommend(overlay: overlayCap, gamma: gammaCap, privateAPIsEnabled: box.value.privateAPIsEnabled)
            )

            // Preserve per-display settings across re-baseline: the live row if present, else the
            // settings retained by stable identity (so an unplug→replug keeps the user's choices).
            let previous = box.value.displays.first(where: { $0.id == identity })
            let remembered = rememberedSettings[identity.persistentKey]
            rows.append(
                DisplayState(
                    id: identity,
                    name: identity.edid?.displayName ?? "Display",
                    appliedMethod: previous?.appliedMethod ?? caps.recommendedMethod,
                    capabilities: caps,
                    warmth: previous?.warmth ?? remembered?.warmth ?? .off,
                    isHardwareDDCEnabled: previous?.isHardwareDDCEnabled ?? remembered?.isHardwareDDCEnabled ?? false,
                    preferredMethod: previous?.preferredMethod ?? remembered?.preferredMethod,
                    lastError: previous?.lastError
                )
            )
        }

        box.value.displays = rows
    }

    /// Restore any currently-connected display that a PRIOR run left warmed (DDC gain / gamma) to
    /// native, BEFORE this run applies anything (§9, invariant 7). Each recovered key is drained
    /// from `staleKeys` so an in-session warm of the same display is never mistaken for stale.
    private func recoverStaleDisplays() async {
        guard !staleKeys.isEmpty else { return }
        // Capture the stale IDs by value before any await (no live index across suspension).
        let staleIDs = box.value.displays.map(\.id).filter { staleKeys.contains($0.persistentKey) }
        for id in staleIDs {
            await restoreHardwareAndClearDirty(id)   // DDC restore from snapshot; keep dirty if it fails
            try? await gamma.reset(id)                // gamma reset is global/idempotent
            if let index = box.value.displays.firstIndex(where: { $0.id == id }) {
                box.value.displays[index].appliedMethod = .off
            }
            staleKeys.remove(id.persistentKey)
        }
    }

    /// Test seam (§21‑E14): drive a hotplug/wake reconfiguration with an explicit display set.
    /// Updates the injected list, rebuilds rows (debounce-free), recovers any reappearing stale
    /// display, and re-applies — the headless equivalent of the reconfiguration callback firing.
    func simulateReconfiguration(present displays: [DisplayIdentity]) async {
        injectedDisplays = displays
        await rebaselineDisplays()
        publish()
    }

    /// Resolve the schedule + master enable + reveal and push the target to each display via
    /// its applied layer. Minimal for this scaffold — full layer selection is a later milestone.
    private func reapply() async {
        let privateOn = box.value.privateAPIsEnabled

        // The Night Shift follower is "available" only when private APIs are on AND it reports a
        // value; otherwise hand the resolver `nil` so it degrades (to the evening fallback)
        // instead of reading a false "inactive" and never warming.
        let nightShift: Bool?
        if privateOn, case let .supported(active) = nightShiftFollower.currentlyActive {
            nightShift = active
        } else {
            nightShift = nil
        }

        let decision = ScheduleResolver.resolveWithDegrade(
            mode: box.value.scheduleMode,
            at: Date(),
            configuredWarmth: box.value.globalWarmth,
            nightShift: nightShift,
            privateAPIsEnabled: privateOn,
            fallback: configuration.fallbackSchedule
        )
        box.value.isScheduleActiveNow = decision.isActiveNow

        let engineOn = box.value.isEnabled && decision.isActiveNow && !box.value.isRevealing
        let warmestPoint = box.value.warmestPoint

        // Snapshot the work set by VALUE before any await. The engine is an actor, so each await is
        // a reentrancy point where a reconfiguration / Night Shift / UI message can replace
        // `box.value.displays` (different count/order). Never hold a live index across an await:
        // compute against the captured `DisplayState`, then write the result back by RE-LOCATING the
        // row via stable identity (skipping it if the display vanished mid-pass).
        for display in box.value.displays {
            let id = display.id
            let key = id.persistentKey
            // Resolve the LAYER fresh from capability + opt-in + override + kill switch (never read
            // back `appliedMethod`, which is only the badge). LayerResolver never returns `.off`, so
            // a display can always resume warming after it has gone neutral.
            let layer = LayerResolver.resolveLayer(
                capabilities: display.capabilities,
                isHardwareDDCEnabled: display.isHardwareDDCEnabled,
                override: display.preferredMethod,
                privateAPIsEnabled: privateOn
            )
            let effective = engineOn ? maxWarmth(display.warmth, decision.target) : .off

            // Clean up a layer we are LEAVING this pass (user disabled DDC, capability changed) so a
            // display can't stay warm on two layers at once.
            await tearDownPreviousLayer(display.appliedMethod, leavingFor: layer, id: id)

            let appliedMethod: DisplayMethod
            let lastError: EngineErrorSummary?
            if effective == .off {
                if layer == .hardware {
                    await restoreHardwareAndClearDirty(id)
                } else {
                    try? await backend(for: layer)?.reset(id)
                }
                appliedMethod = .off
                lastError = nil
            } else {
                let kelvin = effective.kelvin(warmestPoint: warmestPoint)
                if layer == .hardware {
                    // Write-ahead the dirty flag BEFORE the DDC write: a crash mid-write is then
                    // recoverable on the next launch (the panel does not restore itself).
                    await snapshotStore.setDirty(true, for: key)
                    do {
                        try await ddc.apply(kelvin, to: id)
                        appliedMethod = .hardware
                        lastError = nil
                    } catch {
                        // DDC failed/verify-mismatch → fall back to the overlay floor and NEVER claim
                        // the Hardware badge (invariant 1 + §4.1 honest badges). The dirty flag stays
                        // set so a possibly-partial write is restored on reset/relaunch.
                        logger.notice("DDC apply failed; falling back to overlay: \(String(describing: error))")
                        try? await overlay.apply(kelvin, to: id)
                        appliedMethod = .overlay
                        lastError = EngineErrorSummary(
                            method: .hardware,
                            reason: .ddcProbeFailed,
                            message: "Hardware DDC didn’t verify; using overlay."
                        )
                    }
                } else {
                    try? await backend(for: layer)?.apply(kelvin, to: id)
                    appliedMethod = layer
                    lastError = nil
                }
            }

            // Re-locate the row AFTER the awaits — it may have moved or vanished during a
            // concurrent reconfiguration.
            if let index = box.value.displays.firstIndex(where: { $0.id == id }) {
                box.value.displays[index].appliedMethod = appliedMethod
                box.value.displays[index].lastError = lastError
            }
        }
    }

    /// Restore a display's native DDC gain and clear its dirty flag ONLY if the restore fully
    /// verified. A partial/failed restore keeps `dirty = true` so launch-time recovery retries —
    /// mirroring the apply branch, so the "always recoverable" invariant (§9, invariant 7) holds
    /// even when a single channel never reads back to native.
    private func restoreHardwareAndClearDirty(_ id: DisplayIdentity) async {
        do {
            try await ddc.reset(id)
            await snapshotStore.setDirty(false, for: id.persistentKey)
        } catch {
            logger.notice("DDC restore did not fully verify; keeping dirty for recovery: \(String(describing: error))")
        }
    }

    /// Reset a layer the display is leaving so warmth never stacks across layers. Only acts when
    /// the previously-applied method differs from the layer we're switching to.
    private func tearDownPreviousLayer(
        _ previous: DisplayMethod, leavingFor layer: DisplayMethod, id: DisplayIdentity
    ) async {
        guard previous != layer else { return }
        switch previous {
        case .hardware:
            await restoreHardwareAndClearDirty(id)
        case .gamma:
            try? await gamma.reset(id)
        case .overlay:
            try? await overlay.reset(id)
        case .off:
            break
        }
    }

    private func backend(for method: DisplayMethod) -> (any WarmthBackend)? {
        switch method {
        case .overlay:  overlay
        case .gamma:    gamma
        case .hardware: ddc
        case .off:      nil
        }
    }

    private func recommend(
        overlay: Capability<Void>,
        gamma: Capability<Void>,
        privateAPIsEnabled: Bool
    ) -> DisplayMethod {
        // The recommended *default* badge mirrors LayerResolver's automatic resolution BEFORE any
        // DDC opt-in or user override: ANY display recommends gamma — the universal true white-point
        // warm path — where supported (built-in or external); everything else defaults to the
        // overlay floor. DDC is opt-in, so the hardware tier is deliberately excluded here — it only
        // becomes the badge once the user enables it for a display. (§25.)
        if privateAPIsEnabled, case .supported = gamma {
            return .gamma
        }
        if case .supported = overlay { return .overlay }
        return .off
    }

    private func mapToDDCCaps(_ cap: Capability<Void>) -> Capability<DDCColorCaps> {
        switch cap {
        case .supported:                 return .supported(DDCColorCaps(supportsRGBGain: true))
        case let .unsupported(reason):   return .unsupported(reason: reason)
        case let .unknown(reason):       return .unknown(reason: reason)
        }
    }

    private func maxWarmth(_ a: WarmthLevel, _ b: WarmthLevel) -> WarmthLevel {
        a.strength >= b.strength ? a : b
    }

    // MARK: Publishing

    private func publish() {
        let snapshot = box.value
        for continuation in continuations.values {
            continuation.yield(snapshot)
        }
    }

    private func finishContinuations() {
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations.removeAll()
    }
}

// MARK: - WarmthStateBox (engine-private mutable container)

/// Bundles the observable `WarmthState` with engine-private fields that aren't part of the
/// published surface (the warmest-point and the excluded-app set).
private struct WarmthStateBox {
    var value: WarmthState
    var excludedApps: Set<String> = []
}

// MARK: - NoopBackend (test-support neutral layer)

/// A neutral `WarmthBackend` that fills an absent layer in `WarmthEngine.test(...)`. Overlay is the
/// universal floor so it classifies as supported; other methods classify as not-yet-probed. Apply
/// and reset are no-ops. Internal — never wired in production.
struct NoopBackend: WarmthBackend {
    let method: DisplayMethod
    func classify(_ identity: DisplayIdentity) async -> Capability<Void> {
        method == .overlay ? .supported(()) : .unsupported(reason: .notYetProbed)
    }
    func apply(_ kelvin: Kelvin, to identity: DisplayIdentity) async throws {}
    func reset(_ identity: DisplayIdentity) async throws {}
}
