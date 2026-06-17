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

    // MARK: Observation

    /// One continuation per active `stateUpdates()` subscriber.
    private var continuations: [UUID: AsyncStream<WarmthState>.Continuation] = [:]

    private let logger = Logger(label: "com.abendrot.WarmthKit.WarmthEngine")

    // MARK: Init

    public init(configuration: EngineConfiguration) {
        self.configuration = configuration
        self.overlay = OverlayBackend()
        self.gamma = GammaBackend()
        self.ddc = DDCBackend(warmestPoint: configuration.defaultWarmestPoint)
        self.registry = DisplayRegistry()
        self.nightShiftFollower = SystemNightShiftStateFollower()
        self.box = WarmthStateBox(
            value: WarmthState(
                isEnabled: false,
                scheduleMode: configuration.defaultScheduleMode,
                warmestPoint: configuration.defaultWarmestPoint,
                privateAPIsEnabled: configuration.startWithPrivateAPIsEnabled
            )
        )
    }

    // MARK: ── Lifecycle ───────────────────────────────────────────────────────

    /// Build the display registry, run launch-time stale-state recovery, baseline
    /// capabilities, then apply current settings. Safe to call once at app launch.
    public func start() async {
        // TODO: stale-state recovery from persisted EDID snapshots, baseline
        // capabilities per display, re-apply persisted per-display state.
        await rebaselineDisplays()
        publish()
    }

    /// Neutral-reset every display via every active layer, then tear down. Called on quit.
    public func shutdown() async {
        for display in box.value.displays {
            try? await overlay.reset(display.id)
            try? await gamma.reset(display.id)
            try? await ddc.reset(display.id)
        }
        finishContinuations()
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
        // TODO: ease back over ~100–150ms instead of a hard re-apply.
        await reapply()
        publish()
    }

    // MARK: ── Per-display ───────────────────────────────────────────────────────

    public func setWarmth(_ level: WarmthLevel, for id: DisplayIdentity) async {
        guard let index = box.value.displays.firstIndex(where: { $0.id == id }) else { return }
        box.value.displays[index].warmth = level
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
        await reapply()
        publish()
    }

    /// DDC opt-in toggle. No-op (returns .unsupported in state) where DDC isn't capable.
    public func setHardwareDDCEnabled(_ enabled: Bool, for id: DisplayIdentity) async {
        guard let index = box.value.displays.firstIndex(where: { $0.id == id }) else { return }
        box.value.displays[index].isHardwareDDCEnabled = enabled
        await reapply()
        publish()
    }

    /// Per-app exclusions (v1.0 = per-app only; per-website is future).
    public func setExcludedApps(_ bundleIDs: Set<String>) async {
        // TODO: persist exclusions and suspend warmth while an excluded app is front.
        box.excludedApps = bundleIDs
        publish()
    }

    // MARK: ── Safety ────────────────────────────────────────────────────────────

    /// Emergency "Restore Displays": neutral gamma + overlay teardown + DDC native-state
    /// restore for every known display. Surfaced as a menu command. Always available.
    public func restoreAllDisplays() async {
        for display in box.value.displays {
            try? await gamma.reset(display.id)
            try? await overlay.reset(display.id)
            try? await ddc.reset(display.id)
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

    // MARK: ── Internals ─────────────────────────────────────────────────────────

    /// Re-read the connected displays and (re)build their `DisplayState` baseline.
    private func rebaselineDisplays() async {
        let identities = registry.currentDisplays()
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
                recommendedMethod: recommend(overlay: overlayCap, gamma: gammaCap, hardware: hardwareCap)
            )

            // Preserve any existing per-display settings across re-baseline.
            let previous = box.value.displays.first(where: { $0.id == identity })
            rows.append(
                DisplayState(
                    id: identity,
                    name: identity.edid?.displayName ?? "Display",
                    appliedMethod: previous?.appliedMethod ?? caps.recommendedMethod,
                    capabilities: caps,
                    warmth: previous?.warmth ?? .off,
                    isHardwareDDCEnabled: previous?.isHardwareDDCEnabled ?? false,
                    preferredMethod: previous?.preferredMethod,
                    lastError: previous?.lastError
                )
            )
        }

        box.value.displays = rows
        await reapply()
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

        for index in box.value.displays.indices {
            let display = box.value.displays[index]
            // Resolve the LAYER fresh each pass from capability + opt-in + override + kill switch
            // (never read back `appliedMethod`, which is only the badge). LayerResolver never
            // returns `.off`, so a display can always resume warming after it has gone neutral.
            let layer = LayerResolver.resolveLayer(
                capabilities: display.capabilities,
                isHardwareDDCEnabled: display.isHardwareDDCEnabled,
                override: display.preferredMethod,
                privateAPIsEnabled: privateOn
            )
            let effective = engineOn ? maxWarmth(display.warmth, decision.target) : .off
            let layerBackend = backend(for: layer)

            if effective == .off {
                try? await layerBackend?.reset(display.id)
                box.value.displays[index].appliedMethod = .off
            } else {
                let kelvin = effective.kelvin(warmestPoint: box.value.warmestPoint)
                try? await layerBackend?.apply(kelvin, to: display.id)
                box.value.displays[index].appliedMethod = layer
            }
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
        hardware: Capability<Void>
    ) -> DisplayMethod {
        // Overlay is always the safe default; better layers are opt-in / proven later.
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
