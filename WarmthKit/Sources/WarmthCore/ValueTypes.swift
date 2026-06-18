import Foundation

// MARK: - Kelvin

/// Correlated colour temperature, clamped to a sane display range. Neutral = 6500K.
///
/// The clamp range is 500...6500: 6500K is the neutral white point. Two warm anchors matter:
///   - `everydayWarmest` (1900K) — the warmest the *everyday* slider reaches by default. This is
///     the point where the blue channel gain hits 0 (blue fully removed), so "minimize blue light"
///     is already 100% achieved here. Below it, only green keeps falling — for little additional
///     circadian benefit but a real legibility cost (see docs/research/max-warmth-circadian-research.md;
///     Brown et al. 2022; CIE S 026:2018). This is the research-backed everyday maximum.
///   - `warmestSupported` (500K) — the absolute floor (near-pure red), reachable ONLY via the opt-in
///     "expanded range" power control. Going below ~1900K removes green toward pure red; deep and
///     candle-like, but hard to read. The type floors at 500 so the expanded range can reach it and
///     callers can never construct an out-of-range temperature.
public struct Kelvin: Hashable, Sendable, Comparable, Codable {
    public static let neutral = Kelvin(6500)
    public static let everydayWarmest = Kelvin(1900)   // default everyday slider max (blue fully removed)
    public static let warmestSupported = Kelvin(500)   // absolute floor, opt-in expanded range only (near-pure red)
    /// The least-warm end of the "Maximum warmth" ceiling control — a mild warm, not full neutral.
    /// Also the upper bound a persisted warmest point may take (a sanity clamp on read).
    public static let ceilingCoolBound = Kelvin(3400)

    public let value: Int

    public init(_ value: Int) { self.value = min(6500, max(500, value)) }

    public static func < (l: Kelvin, r: Kelvin) -> Bool { l.value < r.value }
}

// MARK: - WarmthLevel

/// The canonical user-facing warmth control: a normalized "Softer ⟷ Warmer" strength.
/// Kelvin is *derived* for display, never the dominant control (plan §4.1).
public struct WarmthLevel: Hashable, Sendable, Codable {
    /// 0.0 = neutral/off, 1.0 = maximum configured warmth.
    public let strength: Double                  // clamped 0...1

    public init(strength: Double) { self.strength = min(1, max(0, strength)) }

    public static let off = WarmthLevel(strength: 0)

    /// Target CCT for a strength, given the user's configured warmest point.
    ///
    /// Interpolates in **mired** space (reciprocal megakelvin, M = 1e6/K), not Kelvin. Perceived
    /// warmth — and, roughly, melanopic change — scale ~linearly with mireds, while equal Kelvin
    /// steps near 6500K are nearly invisible and equal steps near 2700K are huge. A Kelvin-linear
    /// ramp therefore feels dead through the first half of the slider then lurches warm; the
    /// mired-linear ramp is perceptually even. Endpoints are unchanged (0 → neutral, 1 →
    /// warmestPoint) and the result is monotonically non-increasing in Kelvin as strength rises.
    /// (§25 melanopic research.)
    public func kelvin(warmestPoint: Kelvin) -> Kelvin {
        let neutralMired = 1_000_000.0 / Double(Kelvin.neutral.value)
        let warmestMired = 1_000_000.0 / Double(warmestPoint.value)
        let mired = neutralMired + strength * (warmestMired - neutralMired)
        return Kelvin(Int((1_000_000.0 / mired).rounded()))
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
