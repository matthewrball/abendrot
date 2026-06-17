import Foundation

// MARK: - Per-display warmth state machine (pure)

/// The pure, testable model of a single display's warmth target. The engine layers
/// (`DisplayServices` / `HardwareDDC` / `OverlayRenderer`) translate the resolved
/// `effectiveWarmth` into actual pixels; this reducer holds *no* system handles.
public struct DisplayWarmthState: Hashable, Sendable {
    /// Master enable for the whole engine.
    public var isEngineEnabled: Bool
    /// Per-display warmth requested by the user / schedule.
    public var requestedWarmth: WarmthLevel
    /// Whether the schedule says warmth should be active right now.
    public var isScheduleActive: Bool
    /// Hold-to-reveal: suspends warmth across all displays while true.
    public var isRevealing: Bool

    public init(
        isEngineEnabled: Bool = true,
        requestedWarmth: WarmthLevel = .off,
        isScheduleActive: Bool = true,
        isRevealing: Bool = false
    ) {
        self.isEngineEnabled = isEngineEnabled
        self.requestedWarmth = requestedWarmth
        self.isScheduleActive = isScheduleActive
        self.isRevealing = isRevealing
    }

    /// The warmth that should actually be applied to the panel right now after folding in
    /// the engine enable, the schedule gate, and an active reveal.
    public var effectiveWarmth: WarmthLevel {
        guard isEngineEnabled, isScheduleActive, !isRevealing else { return .off }
        return requestedWarmth
    }
}

/// Events that mutate a `DisplayWarmthState`. Kept as a closed set so the transition
/// function is exhaustive and unit-testable.
public enum WarmthEvent: Sendable {
    case setEngineEnabled(Bool)
    case setRequestedWarmth(WarmthLevel)
    case setScheduleActive(Bool)
    case beginReveal
    case endReveal
}

public enum WarmthReducer {
    /// Apply an event to a state, returning the new state. Pure: no side effects.
    public static func reduce(_ state: DisplayWarmthState, _ event: WarmthEvent) -> DisplayWarmthState {
        var next = state
        switch event {
        case let .setEngineEnabled(value):    next.isEngineEnabled = value
        case let .setRequestedWarmth(level):  next.requestedWarmth = level
        case let .setScheduleActive(value):   next.isScheduleActive = value
        case .beginReveal:                    next.isRevealing = true
        case .endReveal:                      next.isRevealing = false
        }
        return next
    }
}
