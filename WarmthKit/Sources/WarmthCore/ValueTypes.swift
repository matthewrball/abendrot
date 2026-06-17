import Foundation

// MARK: - Kelvin

/// Correlated colour temperature, clamped to a sane display range. Neutral = 6500K.
///
/// The clamp range is 1000...6500: 6500K is the neutral white point and the warmest
/// value we ever drive a panel to is well above 1000K, but the type keeps a generous
/// floor so callers can never construct an out-of-range temperature.
public struct Kelvin: Hashable, Sendable, Comparable, Codable {
    public static let neutral = Kelvin(6500)
    public static let warmestSupported = Kelvin(1900)   // floor we expose in UI

    public let value: Int

    public init(_ value: Int) { self.value = min(6500, max(1000, value)) }

    public static func < (l: Kelvin, r: Kelvin) -> Bool { l.value < r.value }
}

// MARK: - WarmthLevel

/// The canonical user-facing warmth control: a normalized "Softer ⟷ Warmer" strength.
/// Kelvin is *derived* for display, never the dominant control.
public struct WarmthLevel: Hashable, Sendable, Codable {
    /// 0.0 = neutral/off, 1.0 = maximum configured warmth.
    public let strength: Double                  // clamped 0...1

    public init(strength: Double) { self.strength = min(1, max(0, strength)) }

    public static let off = WarmthLevel(strength: 0)

    /// Target CCT for a strength, given the user's configured warmest point.
    ///
    /// Linear interpolation between neutral (strength 0) and the warmest point
    /// (strength 1). Monotonically non-increasing in Kelvin as strength rises.
    public func kelvin(warmestPoint: Kelvin) -> Kelvin {
        let k = Double(Kelvin.neutral.value) -
                strength * Double(Kelvin.neutral.value - warmestPoint.value)
        return Kelvin(Int(k.rounded()))
    }
}

// MARK: - DisplayMethod

/// Which physical layer is producing warmth for a display right now. Drives the UI badge.
public enum DisplayMethod: String, Sendable, Codable, CaseIterable {
    case hardware   // DDC RGB-gain — real hardware warmth (badge: "Hardware")
    case gamma      // CGSetDisplayTransferByTable — best-effort, classified (badge: "Gamma")
    case overlay    // Metal multiply veil — universal default (badge: "Overlay")
    case off        // no warmth applied

    public var badge: String {
        switch self {
        case .hardware: "Hardware"
        case .gamma:    "Gamma"
        case .overlay:  "Overlay"
        case .off:      "Off"
        }
    }
}

// MARK: - ScheduleMode

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

    public init(start: DateComponents, end: DateComponents, warmest: WarmthLevel) {
        self.start = start
        self.end = end
        self.warmest = warmest
    }
}
