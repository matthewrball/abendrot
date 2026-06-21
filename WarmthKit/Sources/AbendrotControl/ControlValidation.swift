import Foundation

// MARK: - ControlError
//
// A single, message-carrying error type for control-surface validation. The CLI surfaces
// `.description` on stderr and exits 2; the app's payload decoder uses the same validators so a
// malformed notification can never bypass the invariants the UI enforces.
public enum ControlError: Error, CustomStringConvertible, Equatable {
    case badInput(String)

    public var description: String {
        switch self {
        case .badInput(let message):
            return message
        }
    }
}

// MARK: - ControlValidation
//
// Pure value validators shared by the CLI (clear agent-facing errors) and the app (defense in
// depth on every payload). Bounds mirror the engine's own clamps: `WarmthLevel` clamps strength
// to 0...1 and `Kelvin` clamps to 500...6500 — we reject out-of-range input loudly here rather
// than silently clamping, so an agent learns it asked for something impossible.
public enum ControlValidation {
    /// Global warmth strength must be 0.0–1.0 (matches `WarmthLevel`'s clamp domain).
    public static func validatedStrength(_ value: Double) throws -> Double {
        guard (0.0...1.0).contains(value) else {
            throw ControlError.badInput("warmth must be 0.0–1.0, got \(value)")
        }
        return value
    }

    /// Warmest-point / max-warmth Kelvin must be 500–6500 (matches `Kelvin`'s clamp domain).
    public static func validatedKelvin(_ kelvin: Int) throws -> Int {
        guard (500...6500).contains(kelvin) else {
            throw ControlError.badInput("kelvin must be 500–6500, got \(kelvin)")
        }
        return kelvin
    }

    /// Reveal behaviour is the two `RevealMode` raw values.
    public static func validatedRevealMode(_ string: String) throws -> String {
        guard string == "hold" || string == "toggle" else {
            throw ControlError.badInput("reveal-mode must be hold|toggle, got \(string)")
        }
        return string
    }
}
