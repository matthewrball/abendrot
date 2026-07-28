import Foundation
import WarmthCore

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
    public static let defaultRevealHoldSeconds = 3.0
    public static let maximumRevealHoldSeconds = 300.0
    public static let maximumBundleIDBytes = 255
    public static let maximumDisplaySettingsKeyBytes = 512

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

    /// A reveal is intentionally momentary. Reject non-finite, negative, or excessively long holds
    /// before converting the value to `Duration`, which traps on non-finite/huge doubles.
    public static func validatedRevealHold(_ seconds: Double) throws -> Double {
        guard seconds.isFinite, (0.0...maximumRevealHoldSeconds).contains(seconds) else {
            throw ControlError.badInput(
                "reveal hold must be 0–\(Int(maximumRevealHoldSeconds)) seconds, got \(seconds)")
        }
        return seconds
    }

    /// A manual-location override must be a finite, in-range lat/lon pair. Rejects non-finite values
    /// (NaN/±inf) and anything outside −90…90 / −180…180 — defense in depth so a malformed control
    /// notification can't push a junk coordinate (e.g. 1e308) that traps the timezone/solar math
    /// downstream. Returns the validated pair (callers build the engine's Coordinate from it).
    public static func validatedCoordinate(lat: Double, lon: Double) throws -> (lat: Double, lon: Double) {
        guard lat.isFinite, lon.isFinite else {
            throw ControlError.badInput("coordinate must be finite, got lat \(lat), lon \(lon)")
        }
        guard (-90.0...90.0).contains(lat) else {
            throw ControlError.badInput("latitude must be −90…90, got \(lat)")
        }
        guard (-180.0...180.0).contains(lon) else {
            throw ControlError.badInput("longitude must be −180…180, got \(lon)")
        }
        return (lat, lon)
    }

    /// Bundle ids are persisted and mirrored through the local control surface. Keep this strict:
    /// ASCII reverse-DNS shape only, so path-ish strings, controls, shell metacharacters, and
    /// Unicode lookalikes never become durable app state.
    public static func validatedBundleID(_ raw: String) throws -> String {
        guard !raw.isEmpty else {
            throw ControlError.badInput("bundle id must not be empty")
        }
        guard raw.utf8.count <= maximumBundleIDBytes else {
            throw ControlError.badInput("bundle id must be at most \(maximumBundleIDBytes) bytes")
        }
        guard raw.unicodeScalars.allSatisfy({ scalar in
            scalar.value == 45 || scalar.value == 46 ||
                (48...57).contains(scalar.value) ||
                (65...90).contains(scalar.value) ||
                (97...122).contains(scalar.value)
        }) else {
            throw ControlError.badInput("bundle id may contain only ASCII letters, digits, hyphens, and periods")
        }
        let parts = raw.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2, parts.allSatisfy({ !$0.isEmpty }) else {
            throw ControlError.badInput("bundle id must have at least two non-empty dot-separated components")
        }
        return raw
    }

    public static func validatedBundleIDs(_ raw: [String]) throws -> [String] {
        try raw.map { try validatedBundleID($0) }
    }

    public static func normalizedPersistedBundleIDs(_ raw: [String]) -> [String] {
        Array(Set(raw.compactMap { try? validatedBundleID($0) })).sorted()
    }

    /// Display settings are restored by durable `DisplayIdentity.persistentKey`. Reject malformed
    /// keys and impossible warmth values, and collapse legacy/unsafe method overrides to automatic
    /// (`nil`) rather than preserving a forced layer that the current UI no longer exposes.
    public static func decodedPersistedDisplaySettings(from data: Data) -> [String: DisplaySettingsPreference]? {
        guard let topLevel = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return topLevel.reduce(into: [:]) { result, entry in
            guard isValidDisplaySettingsKey(entry.key),
                  JSONSerialization.isValidJSONObject(entry.value),
                  let entryData = try? JSONSerialization.data(withJSONObject: entry.value),
                  let raw = try? JSONDecoder().decode(RawDisplaySettingsPreference.self, from: entryData),
                  let sanitized = normalizedPersistedDisplaySetting(raw) else { return }
            result[entry.key] = sanitized
        }
    }

    public static func normalizedPersistedDisplaySettings(
        _ raw: [String: DisplaySettingsPreference]
    ) -> [String: DisplaySettingsPreference] {
        raw.reduce(into: [:]) { result, entry in
            guard isValidDisplaySettingsKey(entry.key),
                  let sanitized = normalizedPersistedDisplaySetting(entry.value) else { return }
            result[entry.key] = sanitized
        }
    }

    private static func normalizedPersistedDisplaySetting(
        _ raw: DisplaySettingsPreference
    ) -> DisplaySettingsPreference? {
        normalizedPersistedDisplaySetting(
            warmth: raw.warmth,
            warmthOverridden: raw.warmthOverridden,
            isHardwareDDCEnabled: raw.isHardwareDDCEnabled,
            preferredMethod: raw.preferredMethod
        )
    }

    private static func normalizedPersistedDisplaySetting(
        _ raw: RawDisplaySettingsPreference
    ) -> DisplaySettingsPreference? {
        let method: DisplayMethod?
        switch raw.preferredMethod {
        case "hardware": method = .hardware
        case "overlay": method = .overlay
        case "gamma", "off", nil: method = nil
        default: method = nil
        }
        return normalizedPersistedDisplaySetting(
            strength: raw.warmth.strength,
            warmthOverridden: raw.warmthOverridden,
            isHardwareDDCEnabled: raw.isHardwareDDCEnabled,
            preferredMethod: method
        )
    }

    private static func normalizedPersistedDisplaySetting(
        warmth: WarmthLevel,
        warmthOverridden: Bool,
        isHardwareDDCEnabled: Bool,
        preferredMethod: DisplayMethod?
    ) -> DisplaySettingsPreference? {
        normalizedPersistedDisplaySetting(
            strength: warmth.strength,
            warmthOverridden: warmthOverridden,
            isHardwareDDCEnabled: isHardwareDDCEnabled,
            preferredMethod: preferredMethod
        )
    }

    private static func normalizedPersistedDisplaySetting(
        strength: Double,
        warmthOverridden: Bool,
        isHardwareDDCEnabled: Bool,
        preferredMethod: DisplayMethod?
    ) -> DisplaySettingsPreference? {
        guard strength.isFinite, (0.0...1.0).contains(strength) else { return nil }
        var ddcEnabled = isHardwareDDCEnabled
        let method: DisplayMethod?
        switch preferredMethod {
        case .hardware:
            method = ddcEnabled ? .hardware : nil
        case .overlay:
            method = .overlay
            ddcEnabled = false
        case .gamma, .off, nil:
            method = nil
        }
        return DisplaySettingsPreference(
            warmth: WarmthLevel(strength: strength),
            warmthOverridden: warmthOverridden,
            isHardwareDDCEnabled: ddcEnabled,
            preferredMethod: method
        )
    }

    private static func isValidDisplaySettingsKey(_ key: String) -> Bool {
        guard !key.isEmpty, key.utf8.count <= maximumDisplaySettingsKeyBytes else { return false }
        return key.unicodeScalars.allSatisfy { scalar in
            scalar.value == 45 || scalar.value == 46 || scalar.value == 124 ||
                (48...57).contains(scalar.value) ||
                (65...90).contains(scalar.value) ||
                (97...122).contains(scalar.value)
        }
    }

    private struct RawDisplaySettingsPreference: Decodable {
        var warmth: RawWarmthLevel
        var warmthOverridden: Bool
        var isHardwareDDCEnabled: Bool
        var preferredMethod: String?
    }

    private struct RawWarmthLevel: Decodable {
        var strength: Double
    }
}
