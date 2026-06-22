import Foundation
// Re-export WarmthCore so a single `import WarmthKit` brings the value types that
// appear in the engine's public API (DisplayIdentity, Kelvin, WarmthLevel, etc.).
@_exported import WarmthCore

// MARK: - EngineConfiguration

public struct EngineConfiguration: Sendable {
    public var startWithPrivateAPIsEnabled: Bool   // false on denylisted OS builds
    public var defaultScheduleMode: ScheduleMode   // .followSystemNightShift
    public var defaultWarmestPoint: Kelvin
    /// Approximate evening window used when `.followSystemNightShift` can't read the system
    /// state (private follower unavailable, or kill switch engaged). Prevents "never warms".
    public var fallbackSchedule: CustomSchedule

    public init(
        startWithPrivateAPIsEnabled: Bool = true,
        defaultScheduleMode: ScheduleMode = .followSystemNightShift,
        // Everyday slider max = 1900K (blue fully removed). Pure-red (~500K) is reachable only via
        // the opt-in expanded-range control.
        defaultWarmestPoint: Kelvin = Kelvin.everydayWarmest,
        fallbackSchedule: CustomSchedule = ScheduleResolver.defaultEveningFallback
    ) {
        self.startWithPrivateAPIsEnabled = startWithPrivateAPIsEnabled
        self.defaultScheduleMode = defaultScheduleMode
        self.defaultWarmestPoint = defaultWarmestPoint
        self.fallbackSchedule = fallbackSchedule
    }
}

// MARK: - EngineErrorSummary

/// A non-fatal, surfaced-quietly error summary attached to a `DisplayState` in advanced mode.
public struct EngineErrorSummary: Sendable, Equatable, Codable {
    public var method: DisplayMethod
    public var reason: CapabilityReason
    public var message: String

    public init(method: DisplayMethod, reason: CapabilityReason, message: String) {
        self.method = method
        self.reason = reason
        self.message = message
    }
}

// MARK: - WarmthState

public struct WarmthState: Sendable, Equatable {
    public var isEnabled: Bool
    public var scheduleMode: ScheduleMode
    public var isScheduleActiveNow: Bool          // resolved schedule decision
    public var isRevealing: Bool                  // hold-to-reveal active
    public var globalWarmth: WarmthLevel
    /// The warmth the engine is ACTUALLY applying right now — the schedule decision's target
    /// (`globalWarmth` in Always-on; `globalWarmth × sunset-ramp` in Sunset; `.off`/neutral by day).
    /// Published so the popover can show a live, locked readout in Sunset mode instead of the peak.
    public var resolvedWarmth: WarmthLevel
    /// The Kelvin the warmth slider's max (strength 1.0) maps to — published so the UI can show
    /// an accurate Kelvin readout instead of assuming a default.
    public var warmestPoint: Kelvin
    public var privateAPIsEnabled: Bool
    public var displays: [DisplayState]           // one per connected display

    public init(
        isEnabled: Bool = false,
        scheduleMode: ScheduleMode = .followSystemNightShift,
        isScheduleActiveNow: Bool = false,
        isRevealing: Bool = false,
        globalWarmth: WarmthLevel = .off,
        resolvedWarmth: WarmthLevel = .off,
        warmestPoint: Kelvin = Kelvin.everydayWarmest,
        privateAPIsEnabled: Bool = true,
        displays: [DisplayState] = []
    ) {
        self.isEnabled = isEnabled
        self.scheduleMode = scheduleMode
        self.isScheduleActiveNow = isScheduleActiveNow
        self.isRevealing = isRevealing
        self.globalWarmth = globalWarmth
        self.resolvedWarmth = resolvedWarmth
        self.warmestPoint = warmestPoint
        self.privateAPIsEnabled = privateAPIsEnabled
        self.displays = displays
    }
}

// MARK: - DisplayState

public struct DisplayState: Sendable, Equatable, Identifiable {
    public var id: DisplayIdentity
    public var name: String                       // human label for the row
    public var appliedMethod: DisplayMethod       // the layer currently warming this display
    public var capabilities: DisplayCapabilities
    public var warmth: WarmthLevel
    /// When true, this display uses its OWN `warmth` (a user "Custom warmth" override). When false
    /// it follows the global warmth/schedule. (Replaces the old max(per-display, global) boost.)
    public var warmthOverridden: Bool
    public var isHardwareDDCEnabled: Bool          // opt-in flag
    /// The user's explicit per-display layer override (`setPreferredMethod`), or nil for
    /// automatic best-available. `appliedMethod` is the *currently applied* badge; this is the
    /// *chosen* layer and is what advanced mode check-marks.
    public var preferredMethod: DisplayMethod?
    public var lastError: EngineErrorSummary?      // non-fatal, surfaced quietly in advanced mode

    public init(
        id: DisplayIdentity,
        name: String,
        appliedMethod: DisplayMethod,
        capabilities: DisplayCapabilities,
        warmth: WarmthLevel,
        warmthOverridden: Bool = false,
        isHardwareDDCEnabled: Bool,
        preferredMethod: DisplayMethod? = nil,
        lastError: EngineErrorSummary? = nil
    ) {
        self.id = id
        self.name = name
        self.appliedMethod = appliedMethod
        self.capabilities = capabilities
        self.warmth = warmth
        self.warmthOverridden = warmthOverridden
        self.isHardwareDDCEnabled = isHardwareDDCEnabled
        self.preferredMethod = preferredMethod
        self.lastError = lastError
    }

    // Hand-rolled equality: `capabilities` (DisplayCapabilities) carries `Capability<Void>`
    // values which cannot be `Equatable` (Void is not Equatable), so we compare its
    // identity-relevant scalar projection rather than synthesizing across the capability enums.
    public static func == (lhs: DisplayState, rhs: DisplayState) -> Bool {
        lhs.id == rhs.id
            && lhs.name == rhs.name
            && lhs.appliedMethod == rhs.appliedMethod
            && lhs.warmth == rhs.warmth
            && lhs.warmthOverridden == rhs.warmthOverridden
            && lhs.isHardwareDDCEnabled == rhs.isHardwareDDCEnabled
            && lhs.preferredMethod == rhs.preferredMethod
            && lhs.lastError == rhs.lastError
            && lhs.capabilities.identity == rhs.capabilities.identity
            && lhs.capabilities.recommendedMethod == rhs.capabilities.recommendedMethod
    }
}
