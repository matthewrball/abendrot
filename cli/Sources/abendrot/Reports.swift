import Foundation
import WarmthCore
import AbendrotControl

// MARK: - WarmthCurve
//
// Invert `WarmthLevel.kelvin(warmestPoint:)` — monotonic non-increasing in strength — by binary
// search, exactly as AppModel's `setGlobalWarmthToKelvin` does. No duplicated mired math; this
// tracks the engine's own curve so `set warmth --kelvin K` lands where the app would put it.
enum WarmthCurve {
    static func strength(forKelvin target: Kelvin, warmestPoint: Kelvin) -> Double {
        var lo = 0.0, hi = 1.0
        for _ in 0..<24 {
            let mid = (lo + hi) / 2
            if WarmthLevel(strength: mid).kelvin(warmestPoint: warmestPoint).value <= target.value {
                hi = mid
            } else {
                lo = mid
            }
        }
        return (lo + hi) / 2
    }
}

// MARK: - StatusReport

enum StatusReport {
    /// JSON object = the snapshot fields PLUS running / cliVersion / snapshotSchemaVersion. Built by
    /// re-encoding the decoded snapshot and splicing in the CLI-only fields, so it stays in lockstep
    /// with the schema (no hand-maintained field list).
    static func json(snapshot: ControlStateSnapshot?, running: Bool) -> String {
        var root: [String: Any] = [
            "running": running,
            "cliVersion": cliVersion,
        ]
        if let snapshot {
            root["snapshotSchemaVersion"] = snapshot.schemaVersion
            if let data = try? snapshotEncoder.encode(snapshot),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                for (key, value) in obj { root[key] = value }
            }
        } else {
            // No live snapshot — surface the persisted values so an agent still gets something.
            root["snapshotSchemaVersion"] = AbendrotControl.schemaVersion
            for (key, value) in persistedFields() { root[key] = value }
        }
        let data = (try? JSONSerialization.data(
            withJSONObject: root, options: [.sortedKeys])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    static func human(snapshot: ControlStateSnapshot, running: Bool) -> String {
        var lines: [String] = []
        lines.append("Abendrot \(snapshot.appVersion) (build \(snapshot.appBuild)) — \(running ? "running" : "not running")")
        lines.append("Enabled:  \(snapshot.isEnabled ? "yes" : "no")")
        lines.append("Mode:     \(snapshot.scheduleMode.rawValue)\(snapshot.isScheduleActiveNow ? " (warming now)" : "")")
        lines.append("Warmth:   \(String(format: "%.2f", snapshot.globalWarmthStrength)) (~\(snapshot.globalKelvin)K, max \(snapshot.warmestPointKelvin)K)")
        lines.append("Cozy:     \(snapshot.cozy ? "on" : "off")")
        lines.append("Reveal:   \(snapshot.revealMode)\(snapshot.isRevealing ? " (revealing now)" : "")")
        if !snapshot.excludedApps.isEmpty {
            lines.append("Excluded: \(snapshot.excludedApps.joined(separator: ", "))")
        }
        if snapshot.displays.isEmpty {
            lines.append("Displays: (none reported)")
        } else {
            lines.append("Displays:")
            for display in snapshot.displays {
                var row = "  • \(display.name): \(display.appliedMethod)"
                if display.warmthOverridden { row += " (custom \(String(format: "%.2f", display.warmthStrength)))" }
                if display.isHardwareDDCEnabled { row += " [DDC]" }
                if let error = display.lastError { row += " — \(error)" }
                lines.append(row)
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Human summary when no full snapshot decodes — last-known persisted values. `running` is the
    /// forward-tolerant liveness: normally the app is closed, but it is also true when a NEWER app
    /// is live and its rich snapshot just doesn't decode here, so the header stays honest.
    static func humanFromPreferences(running: Bool = false) -> String {
        let enabled = Control.configuredBool(PreferenceKey.isEnabled) ?? false
        let mode = Control.configuredScheduleMode().rawValue
        let strength = Control.configuredDouble(PreferenceKey.globalWarmthStrength)
        let maxWarmth = Control.configuredInt(PreferenceKey.warmestPointKelvin) ?? Kelvin.everydayWarmest.value
        let header = running
            ? "Abendrot — running (newer app; showing saved settings)"
            : "Abendrot — not running (showing saved settings)"
        var lines = [header]
        lines.append("Enabled:  \(enabled ? "yes" : "no")")
        lines.append("Mode:     \(mode)")
        if let strength {
            let kelvin = WarmthLevel(strength: strength).kelvin(warmestPoint: Kelvin(maxWarmth)).value
            lines.append("Warmth:   \(String(format: "%.2f", strength)) (~\(kelvin)K, max \(maxWarmth)K)")
        } else {
            lines.append("Warmth:   (default, max \(maxWarmth)K)")
        }
        lines.append("Cozy:     \(ControlStateSnapshot.isCozy(warmestPointKelvin: maxWarmth) ? "on" : "off")")
        let excluded = Control.configuredExcludedApps()
        if !excluded.isEmpty { lines.append("Excluded: \(excluded.joined(separator: ", "))") }
        return lines.joined(separator: "\n")
    }

    private static var snapshotEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    /// Persisted fields surfaced under `status --json` when the app isn't running.
    private static func persistedFields() -> [String: Any] {
        var fields: [String: Any] = [:]
        fields["isEnabled"] = Control.configuredBool(PreferenceKey.isEnabled) ?? false
        fields["scheduleMode"] = Control.configuredScheduleMode().rawValue
        if let strength = Control.configuredDouble(PreferenceKey.globalWarmthStrength) {
            fields["globalWarmthStrength"] = strength
        }
        let maxWarmth = Control.configuredInt(PreferenceKey.warmestPointKelvin) ?? Kelvin.everydayWarmest.value
        fields["warmestPointKelvin"] = maxWarmth
        // Mirror the running snapshot's derived field so `status --json` carries `cozy` either way.
        fields["cozy"] = ControlStateSnapshot.isCozy(warmestPointKelvin: maxWarmth)
        if let revealMode = Control.configuredString(PreferenceKey.revealMode) {
            fields["revealMode"] = revealMode
        }
        fields["excludedApps"] = Control.configuredExcludedApps()
        return fields
    }
}

// MARK: - GetReport

enum GetReport {
    /// Resolve one human-facing setting key to a (label, printable-value) pair from CFPreferences.
    /// Returns nil for an unknown key (the caller maps that to exit 2 with a clear message).
    static func value(forKey key: String) -> (label: String, value: String)? {
        switch key {
        case "warmth":
            if let strength = Control.configuredDouble(PreferenceKey.globalWarmthStrength) {
                return ("warmth", String(format: "%.2f", strength))
            }
            return ("warmth", "default")
        case "mode":
            return ("mode", Control.configuredScheduleMode().rawValue)
        case "max-warmth":
            let k = Control.configuredInt(PreferenceKey.warmestPointKelvin) ?? Kelvin.everydayWarmest.value
            return ("max-warmth", String(k))
        case "cozy":
            // Cozy is derived from the persisted ceiling — on exactly when it sits below 1900K.
            let k = Control.configuredInt(PreferenceKey.warmestPointKelvin) ?? Kelvin.everydayWarmest.value
            return ("cozy", ControlStateSnapshot.isCozy(warmestPointKelvin: k) ? "on" : "off")
        case "reveal-mode":
            return ("reveal-mode", Control.configuredString(PreferenceKey.revealMode) ?? "hold")
        case "location":
            if let coord = Control.configuredCoordinate() {
                return ("location", "\(coord.lat) \(coord.lon)")
            }
            return ("location", "auto")
        case "enabled":
            return ("enabled", (Control.configuredBool(PreferenceKey.isEnabled) ?? false) ? "true" : "false")
        default:
            return nil
        }
    }

    /// JSON-encode a printed value: numbers/bools bare, everything else quoted.
    static func jsonValue(_ value: String) -> String {
        if value == "true" || value == "false" { return value }
        if Double(value) != nil { return value }
        // location prints "lat lon" — quote it; auto/default/hold/etc. are also strings.
        return "\"\(JSONString.escape(value))\""
    }

    /// The `--json` object for one key. Unlike the human path, this emits structured, lossless
    /// values an agent can parse without string-splitting: `warmth` at full precision (not %.2f),
    /// and `location` as `{"latitude":…,"longitude":…}` or `{"auto":true}` (not a packed string).
    /// Returns nil for an unknown key (the caller maps that to exit 2).
    static func jsonObject(forKey key: String) -> String? {
        switch key {
        case "warmth":
            if let strength = Control.configuredDouble(PreferenceKey.globalWarmthStrength) {
                return "{\"warmth\":\(jsonNumber(strength))}"
            }
            return "{\"warmth\":\"default\"}"
        case "location":
            if let coord = Control.configuredCoordinate() {
                return "{\"latitude\":\(jsonNumber(coord.lat)),\"longitude\":\(jsonNumber(coord.lon))}"
            }
            return "{\"auto\":true}"
        default:
            // Everything else keeps the simple {key:value} shape from the human resolver.
            guard let (label, value) = value(forKey: key) else { return nil }
            return "{\"\(label)\":\(jsonValue(value))}"
        }
    }

    /// Render a Double as a JSON number at full precision. `String(describing:)` gives the shortest
    /// round-trippable decimal for a `Double`, so no significant digits are lost.
    private static func jsonNumber(_ value: Double) -> String {
        String(describing: value)
    }
}
