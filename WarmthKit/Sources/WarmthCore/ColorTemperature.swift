import Foundation

// MARK: - RGBGain

/// Per-channel linear multipliers in 0...1 applied to a display's white point to warm it.
///
/// Feeds both the Metal overlay shader (a multiply veil) and the DDC RGB-gain path.
/// At the neutral white point (6500K) all three channels are ~1.0 (an identity / no-op);
/// as the target gets warmer, blue is reduced most, green less, and red stays near 1.0.
public struct RGBGain: Hashable, Sendable, Codable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = Self.clamp(red)
        self.green = Self.clamp(green)
        self.blue = Self.clamp(blue)
    }

    public static let identity = RGBGain(red: 1, green: 1, blue: 1)

    private static func clamp(_ v: Double) -> Double { min(1, max(0, v)) }
}

// MARK: - Kelvin → RGB gain

/// Maps a correlated colour temperature to per-channel multipliers in 0...1.
///
/// This is a blackbody approximation in the spirit of Tanner Helland's well-known
/// piecewise fit, reimplemented here. The raw approximation yields 8-bit-ish channel
/// values for an *emissive* white point; we normalize the result against the neutral
/// 6500K white so that 6500K maps to the identity gain (1,1,1) and warmer temperatures
/// scale the blue and green channels down relative to red.
///
/// - Returns: an `RGBGain` with each channel clamped to 0...1.
public func rgbGain(for kelvin: Kelvin) -> RGBGain {
    let warmWhite = blackbodyWhite(kelvinValue: Double(kelvin.value))
    let neutralWhite = blackbodyWhite(kelvinValue: Double(Kelvin.neutral.value))

    // Normalize against the neutral white point so 6500K → identity, and the warmest
    // channel of the target maps to ~1.0 (we never *boost* a channel above the panel's
    // native output — warmth is achieved by attenuating cooler channels).
    let r = warmWhite.red / max(neutralWhite.red, .leastNonzeroMagnitude)
    let g = warmWhite.green / max(neutralWhite.green, .leastNonzeroMagnitude)
    let b = warmWhite.blue / max(neutralWhite.blue, .leastNonzeroMagnitude)

    // Anchor on the brightest channel (red for warm light) so the dominant channel sits
    // at 1.0 and the others are attenuated relative to it.
    let peak = max(r, max(g, b))
    guard peak > 0 else { return .identity }

    return RGBGain(red: r / peak, green: g / peak, blue: b / peak)
}

// MARK: - Blackbody approximation (internal)

/// One un-normalized blackbody white point in linear-ish 0...1 channel space.
private struct BlackbodyWhite {
    let red: Double
    let green: Double
    let blue: Double
}

/// Tanner Helland-style piecewise approximation of a blackbody radiator's RGB colour,
/// reimplemented. Returns channels normalized to 0...1 (the original fit produces 0...255).
private func blackbodyWhite(kelvinValue: Double) -> BlackbodyWhite {
    let temp = kelvinValue / 100.0

    let red: Double
    if temp <= 66 {
        red = 255
    } else {
        let t = temp - 60
        red = clamp255(329.698727446 * pow(t, -0.1332047592))
    }

    let green: Double
    if temp <= 66 {
        green = clamp255(99.4708025861 * log(temp) - 161.1195681661)
    } else {
        let t = temp - 60
        green = clamp255(288.1221695283 * pow(t, -0.0755148492))
    }

    let blue: Double
    if temp >= 66 {
        blue = 255
    } else if temp <= 19 {
        blue = 0
    } else {
        blue = clamp255(138.5177312231 * log(temp - 10) - 305.0447927307)
    }

    return BlackbodyWhite(red: red / 255.0, green: green / 255.0, blue: blue / 255.0)
}

private func clamp255(_ v: Double) -> Double { min(255, max(0, v)) }
