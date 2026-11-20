import Foundation
import WarmthCore
import AbendrotControl

// MARK: - WarmthCurve
//
// Invert `WarmthLevel.kelvin(warmestPoint:)` — monotonic non-increasing in strength — by binary
// search. This tracks the engine's own curve so `set warmth --kelvin K` lands consistently.
//
// The answer is the lowest strength that shows the target, and the two ends are exact: a target
// at or past the warmest point is 1, neutral is 0. The search alone stops one step short of
// either end, which stored 0.9999999701976776 for "as warm as it goes".
enum WarmthCurve {
    static func strength(forKelvin target: Kelvin, warmestPoint: Kelvin) -> Double {
        if target.value <= warmestPoint.value { return 1 }
        if WarmthLevel(strength: 0).kelvin(warmestPoint: warmestPoint).value <= target.value { return 0 }
        var lo = 0.0, hi = 1.0
        for _ in 0..<24 {
            let mid = (lo + hi) / 2
            if WarmthLevel(strength: mid).kelvin(warmestPoint: warmestPoint).value <= target.value {
                hi = mid
            } else {
                lo = mid
            }
        }
        // `hi` is the side that reaches the target; the midpoint can land a Kelvin short of it.
        return hi
    }
}

// MARK: - StatusReport

enum StatusReport {
    /// JSON object = the snapshot fields PLUS running / cliVersion / snapshotSchemaVersion. Built by
    /// re-encoding the decoded snapshot and splicing in the CLI-only fields, so it stays in lockstep
    /// with the schema (no hand-maintained field list).
    static func json(snapshot: ControlStateSnapshot?, running: Bool) -> String {
        let snapshot = snapshot.map { current($0, running: running) }
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

    /// The snapshot as it may be reported. A snapshot left behind by an app that is no longer
    /// running (a crash, a reboot) still carries the phase of its last moment; only a running
    /// app knows the phase, so it is dropped.
    static func current(_ snapshot: ControlStateSnapshot, running: Bool) -> ControlStateSnapshot {
        guard !running else { return snapshot }
        var snapshot = snapshot
        snapshot.lateNight?.phase = nil
        return snapshot
    }

    static func human(snapshot: ControlStateSnapshot, running: Bool) -> String {
        let snapshot = current(snapshot, running: running)
        var lines: [String] = []
        lines.append("Abendrot \(snapshot.appVersion) (build \(snapshot.appBuild)) — \(running ? "running" : "not running")")
        lines.append("Enabled:  \(snapshot.isEnabled ? "yes" : "no")")
        let paused = snapshot.pauseUntil.map { $0 > Date() } ?? false
        let warmingNow = snapshot.isEnabled && snapshot.isScheduleActiveNow && !snapshot.isRevealing && !paused
        lines.append("Mode:     \(snapshot.scheduleMode.rawValue)\(warmingNow ? " (warming now)" : "")")
        lines.append("Warmth:   \(String(format: "%.2f", snapshot.globalWarmthStrength)) (~\(snapshot.globalKelvin)K, max \(snapshot.warmestPointKelvin)K)")
        lines.append("Cozy:     \(snapshot.cozy ? "on" : "off")")
        lines.append("Reveal:   \(snapshot.revealMode)\(snapshot.isRevealing ? " (revealing now)" : "")")
        if paused, let until = snapshot.pauseUntil {
            let when = until.formatted(date: .omitted, time: .shortened)
            let kind = snapshot.pauseKind == TimedPause.Kind.untilSunrise.rawValue ? "sunrise" : "one hour"
            lines.append("Pause:    until \(when) (\(kind))")
        }
        if snapshot.pausesForFullScreen == true {
            lines.append("Full screen: pause while a window covers its display")
        }
        if let line = snapshot.lateNight.flatMap({ lateNightLine(stage: $0, mode: snapshot.scheduleMode) }) {
            lines.append(line)
        }
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
        let strength = Control.configuredWarmthStrength()
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
        if let until = Control.configuredDouble(PreferenceKey.pauseUntil),
           let kind = Control.configuredString(PreferenceKey.pauseKind),
           let pauseKind = TimedPause.Kind(rawValue: kind),
           PausePolicy.active(TimedPause(until: Date(timeIntervalSince1970: until), kind: pauseKind), at: Date()) != nil {
            lines.append("Pause:    until \(Date(timeIntervalSince1970: until).formatted(date: .omitted, time: .shortened))")
        }
        if Control.configuredBool(PreferenceKey.pausesForFullScreen) == true {
            lines.append("Full screen: pause while a window covers its display")
        }
        if let line = lateNightLine(stage: Control.configuredLateNight(), mode: Control.configuredScheduleMode()) {
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    /// The one `status` line for Sunset mode's late-night stage, or nil while the stage is off.
    static func lateNightLine(stage: LateNightSnapshot, mode: ControlScheduleMode) -> String? {
        guard stage.enabled else { return nil }
        var line = "Late night: " + LateNightReport.plan(stage)
        if mode != .sunset {
            line += " — takes effect in Sunset mode"
        } else if stage.phase == LateNightSnapshot.phaseEasing {
            line += " (easing now)"
        } else if stage.phase == LateNightSnapshot.phaseHeld {
            line += " (holding now)"
        } else if stage.phase == LateNightSnapshot.phaseReleasing {
            line += " (releasing now)"
        }
        return line
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
        if let strength = Control.configuredWarmthStrength() {
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
        if let until = Control.configuredDouble(PreferenceKey.pauseUntil),
           let kind = Control.configuredString(PreferenceKey.pauseKind),
           let pauseKind = TimedPause.Kind(rawValue: kind),
           PausePolicy.active(TimedPause(until: Date(timeIntervalSince1970: until), kind: pauseKind), at: Date()) != nil {
            fields["pauseUntil"] = ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: until))
            fields["pauseKind"] = pauseKind.rawValue
        }
        if let fullscreen = Control.configuredBool(PreferenceKey.pausesForFullScreen) {
            fields["pausesForFullScreen"] = fullscreen
        }
        // The same object the running app writes, minus `phase`: only the app knows that.
        fields["lateNight"] = LateNightReport.object(stage: Control.configuredLateNight())
        return fields
    }
}

// MARK: - LateNightReport
//
// `abendrot late-night [status]`: Sunset mode's late-night stage as configured. Pure functions of
// a `LateNightSnapshot`, so the running app's snapshot and the saved-values fallback print alike.
enum LateNightReport {
    /// "bedtime 23:00, easing over 1 hr to ~1900K".
    static func plan(_ stage: LateNightSnapshot) -> String {
        let ease = LateNightStage.easeText(minutes: stage.easeMinutes ?? LateNightStage.defaultEaseMinutes)
        let colour = stage.cozy ? "Cozy (~\(stage.kelvin)K)" : "~\(stage.kelvin)K"
        return "bedtime \(stage.bedtime), easing over \(ease) to \(colour)"
    }

    static func human(stage: LateNightSnapshot, mode: ControlScheduleMode) -> String {
        var lines = ["Late night: \(stage.enabled ? "on" : "off")"]
        lines.append("Bedtime:    \(stage.bedtime)")
        lines.append("Ease:       \(LateNightStage.easeText(minutes: stage.easeMinutes ?? LateNightStage.defaultEaseMinutes)) before bedtime")
        let strength = String(format: "%.2f", stage.warmthStrength)
        let everyday = LateNightSnapshot.targetKelvin(strength: stage.warmthStrength, cozy: false).value
        if stage.cozy {
            lines.append("Warmth:     Cozy at bedtime (~\(stage.kelvin)K); saved warmth \(strength) (~\(everyday)K) is unused")
        } else {
            lines.append("Warmth:     \(strength) (~\(stage.kelvin)K)")
        }
        lines.append("Cozy:       \(stage.cozy ? "on" : "off")")
        if stage.enabled, mode == .sunset {
            switch stage.phase {
            case LateNightSnapshot.phaseEasing: lines.append("Now:        easing")
            case LateNightSnapshot.phaseHeld: lines.append("Now:        holding the late-night colour")
            case LateNightSnapshot.phaseReleasing: lines.append("Now:        releasing back to day")
            case LateNightSnapshot.phaseInactive: lines.append("Now:        not active")
            default: break   // nil (app closed), or a phase a newer app reports: say nothing
            }
        }
        if mode != .sunset {
            lines.append("Mode is \(mode.rawValue): late-night takes effect in Sunset mode.")
        }
        return lines.joined(separator: "\n")
    }

    /// The `lateNight` object exactly as `status --json` carries it.
    static func object(stage: LateNightSnapshot) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(stage),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object
    }

    /// `late-night --json`: the `lateNight` object, plus the mode it depends on.
    static func json(stage: LateNightSnapshot, mode: ControlScheduleMode) -> String {
        var root = object(stage: stage)
        root["scheduleMode"] = mode.rawValue
        root["activeInCurrentMode"] = stage.enabled && mode == .sunset
        let data = (try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - GetReport

enum GetReport {
    /// Every key `get` resolves, in help-text order.
    static let keys = [
        "warmth", "mode", "max-warmth", "cozy", "reveal-mode", "location", "enabled",
        "late-night", "bedtime", "late-night-warmth", "late-night-kelvin", "late-night-cozy", "late-night-ease",
    ]
    static var keyList: String { keys.joined(separator: " | ") }

    /// The late-night keys, resolved against one stage. Nil for any other key.
    static func lateNightValue(forKey key: String, stage: LateNightSnapshot) -> (label: String, value: String)? {
        switch key {
        case "late-night": return (key, stage.enabled ? "on" : "off")
        case "bedtime": return (key, stage.bedtime)
        case "late-night-warmth": return (key, String(format: "%.2f", stage.warmthStrength))
        case "late-night-kelvin": return (key, String(stage.kelvin))
        case "late-night-cozy": return (key, stage.cozy ? "on" : "off")
        case "late-night-ease": return (key, String(stage.easeMinutes ?? LateNightStage.defaultEaseMinutes))
        default: return nil
        }
    }

    /// Resolve one human-facing setting key to a (label, printable-value) pair from CFPreferences.
    /// Returns nil for an unknown key (the caller maps that to exit 2 with a clear message).
    static func value(forKey key: String) -> (label: String, value: String)? {
        switch key {
        case "warmth":
            if let strength = Control.configuredWarmthStrength() {
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
        case "late-night", "bedtime", "late-night-warmth", "late-night-kelvin", "late-night-cozy", "late-night-ease":
            return lateNightValue(forKey: key, stage: Control.configuredLateNight())
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
            if let strength = Control.configuredWarmthStrength() {
                return "{\"warmth\":\(jsonNumber(strength))}"
            }
            return "{\"warmth\":\"default\"}"
        case "location":
            if let coord = Control.configuredCoordinate() {
                return "{\"latitude\":\(jsonNumber(coord.lat)),\"longitude\":\(jsonNumber(coord.lon))}"
            }
            return "{\"auto\":true}"
        case "late-night-warmth":
            return "{\"late-night-warmth\":\(jsonNumber(Control.configuredLateNight().warmthStrength))}"
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
