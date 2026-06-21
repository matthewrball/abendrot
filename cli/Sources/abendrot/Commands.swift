import ArgumentParser
import Foundation
import WarmthCore
import AbendrotControl

// MARK: - Shared apply flow

/// The common path for a settings command: persist the patch (survives restart), post it live, then
/// report based on whether the app is running and acked. Throws ArgumentParser's `ExitCode` to set the
/// process exit code; never crashes. (Plan §2.3 exit codes.)
///
/// - app running + ack within timeout → success, `appliedLive: true`, exit 0.
/// - app NOT running → "saved; app not running" on stderr, `appliedLive: false`, exit 0 (persist
///   succeeded; applies on next launch).
/// - app running but NO ack within timeout → exit 4 (persisted, but live apply didn't confirm).
func applySettings(_ patch: SettingsPatch, json: Bool) throws {
    Control.persist(patch)
    let wasRunning = Control.runningSnapshot() != nil
    let requestID = Control.post(patch: patch)

    if !wasRunning {
        // The app might have launched between the check and the post; give the ack a brief chance.
        if Control.waitForAck(requestID, timeout: 0.3) {
            emitApplyResult(appliedLive: true, json: json)
            return
        }
        printErr("saved; app not running")
        emitApplyResult(appliedLive: false, json: json)
        return   // exit 0 — persist succeeded
    }

    if Control.waitForAck(requestID) {
        emitApplyResult(appliedLive: true, json: json)
    } else {
        if json { print("{\"ok\":false,\"appliedLive\":false,\"persisted\":true}") }
        throw fail("saved, but the running app did not confirm the change in time",
                   code: CLIExit.liveApplyTimeout)
    }
}

private func emitApplyResult(appliedLive: Bool, json: Bool) {
    if json {
        print("{\"ok\":true,\"appliedLive\":\(appliedLive),\"persisted\":true}")
    } else if appliedLive {
        print("ok")
    }
    // Not-running path: the human note already went to stderr; keep stdout quiet.
}

// MARK: - status

struct Status: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Show live app state (enabled, mode, warmth, per-display method).")
    @Flag(name: .long, help: "Emit machine-readable JSON.") var json = false

    func run() throws {
        let snapshot = Control.readSnapshot()
        let running = snapshot.map { Control.pidAlive($0.pid) } ?? false

        if json {
            print(StatusReport.json(snapshot: snapshot, running: running))
            return
        }
        guard let snapshot else {
            // No live snapshot — show the persisted values so `status` still says something.
            print(StatusReport.humanFromPreferences())
            return
        }
        print(StatusReport.human(snapshot: snapshot, running: running))
    }
}

// MARK: - get <key>

struct Get: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Print one configured setting (warmth, mode, max-warmth, reveal-mode, location, enabled).")
    @Argument(help: "warmth | mode | max-warmth | reveal-mode | location | enabled") var key: String
    @Flag(name: .long, help: "Emit machine-readable JSON.") var json = false

    func run() throws {
        guard let (label, value) = GetReport.value(forKey: key) else {
            throw fail("unknown key '\(key)' — try warmth | mode | max-warmth | reveal-mode | location | enabled",
                       code: CLIExit.badInput)
        }
        if json {
            print("{\"\(label)\":\(GetReport.jsonValue(value))}")
        } else {
            print(value)
        }
    }
}

// MARK: - on / off

struct On: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Enable warming (isEnabled = true).")
    @Flag(name: .long) var json = false
    func run() throws { try applySettings(SettingsPatch(isEnabled: true), json: json) }
}

struct Off: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Disable warming (isEnabled = false).")
    @Flag(name: .long) var json = false
    func run() throws { try applySettings(SettingsPatch(isEnabled: false), json: json) }
}

// MARK: - set <subcommand>

// Named `SetCommand` (not `Set`) so it never shadows Swift's `Set<Element>`, which the exclude
// add/remove math uses in this same file. `commandName: "set"` keeps the user-facing verb.
struct SetCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "set",
        abstract: "Change a setting.",
        subcommands: [SetWarmth.self, SetMode.self, SetMaxWarmth.self, SetRevealMode.self, SetLocation.self]
    )
}

struct SetWarmth: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "warmth", abstract: "Set global warmth 0.0–1.0, or target a Kelvin with --kelvin.")
    @Argument(help: "Warmth strength 0.0–1.0 (omit when using --kelvin).") var strength: Double?
    @Option(name: .long, help: "Target effective Kelvin (500–6500) instead of a strength.") var kelvin: Int?
    @Flag(name: .long) var json = false

    func run() throws {
        if let kelvin {
            // Map a target Kelvin to a strength against the configured warmest point, inverting the
            // engine's own mired curve so the CLI tracks `WarmthLevel.kelvin(warmestPoint:)` exactly.
            let validKelvin = try requireValid { try ControlValidation.validatedKelvin(kelvin) }
            let warmest = Control.configuredWarmestPoint()
            let strength = WarmthCurve.strength(forKelvin: Kelvin(validKelvin), warmestPoint: warmest)
            try applySettings(SettingsPatch(globalWarmthStrength: strength), json: json)
        } else if let strength {
            let valid = try requireValid { try ControlValidation.validatedStrength(strength) }
            try applySettings(SettingsPatch(globalWarmthStrength: valid), json: json)
        } else {
            throw fail("provide a strength 0.0–1.0 or --kelvin <K>", code: CLIExit.badInput)
        }
    }
}

struct SetMode: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "mode", abstract: "Set schedule mode: sunset | always-on | off.")
    @Argument(help: "sunset | always-on | off") var mode: String
    @Flag(name: .long) var json = false

    func run() throws {
        guard let controlMode = ControlScheduleMode(rawValue: mode) else {
            throw fail("mode must be sunset|always-on|off, got \(mode)", code: CLIExit.badInput)
        }
        try applySettings(SettingsPatch(scheduleMode: controlMode), json: json)
    }
}

struct SetMaxWarmth: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "max-warmth", abstract: "Set the warmest-point ceiling in Kelvin (500–6500).")
    @Argument(help: "Kelvin 500–6500.") var kelvin: Int
    @Flag(name: .long) var json = false

    func run() throws {
        let valid = try requireValid { try ControlValidation.validatedKelvin(kelvin) }
        try applySettings(SettingsPatch(warmestPointKelvin: valid), json: json)
    }
}

struct SetRevealMode: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "reveal-mode", abstract: "Set reveal behaviour: hold | toggle.")
    @Argument(help: "hold | toggle") var mode: String
    @Flag(name: .long) var json = false

    func run() throws {
        let valid = try requireValid { try ControlValidation.validatedRevealMode(mode) }
        try applySettings(SettingsPatch(revealMode: valid), json: json)
    }
}

struct SetLocation: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "location", abstract: "Set manual sunset location <lat> <lon>, or --auto to clear it.")
    @Argument(help: "Latitude (omit with --auto).") var latitude: Double?
    @Argument(help: "Longitude (omit with --auto).") var longitude: Double?
    @Flag(name: .long, help: "Clear the manual coordinate; derive sunset from the system time zone.") var auto = false
    @Flag(name: .long) var json = false

    func run() throws {
        if auto {
            try applySettings(SettingsPatch(clearUserCoordinate: true), json: json)
            return
        }
        guard let latitude, let longitude else {
            throw fail("provide <lat> <lon>, or --auto to clear", code: CLIExit.badInput)
        }
        guard (-90.0...90.0).contains(latitude) else {
            throw fail("latitude must be -90…90, got \(latitude)", code: CLIExit.badInput)
        }
        guard (-180.0...180.0).contains(longitude) else {
            throw fail("longitude must be -180…180, got \(longitude)", code: CLIExit.badInput)
        }
        try applySettings(SettingsPatch(userLatitude: latitude, userLongitude: longitude), json: json)
    }
}

// MARK: - exclude

struct Exclude: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage the per-app warmth-exclusion list.",
        subcommands: [ExcludeAdd.self, ExcludeRemove.self, ExcludeList.self]
    )
}

struct ExcludeAdd: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "add", abstract: "Add a bundle id to the exclusion set.")
    @Argument(help: "Bundle id, e.g. com.apple.dt.Xcode") var bundleID: String
    @Flag(name: .long) var json = false

    func run() throws {
        let current = Control.configuredExcludedApps()
        let next = Set(current).union([bundleID]).sorted()
        try applySettings(SettingsPatch(excludedApps: next), json: json)
    }
}

struct ExcludeRemove: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "remove", abstract: "Remove a bundle id from the exclusion set.")
    @Argument(help: "Bundle id to remove.") var bundleID: String
    @Flag(name: .long) var json = false

    func run() throws {
        let current = Control.configuredExcludedApps()
        let next = Set(current).subtracting([bundleID]).sorted()
        try applySettings(SettingsPatch(excludedApps: next), json: json)
    }
}

struct ExcludeList: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List excluded bundle ids.")
    @Flag(name: .long) var json = false

    func run() throws {
        let apps = Control.configuredExcludedApps()
        if json {
            let items = apps.map { "\"\(JSONString.escape($0))\"" }.joined(separator: ",")
            print("{\"excludedApps\":[\(items)]}")
        } else if apps.isEmpty {
            print("(none)")
        } else {
            apps.forEach { print($0) }
        }
    }
}

// MARK: - reveal

struct Reveal: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Momentary true-color peek (live-only; requires a running app).")
    @Option(name: .long, help: "Hold the reveal for N seconds (default 3).") var hold: Double?
    @Flag(name: .long) var json = false

    func run() throws {
        // Reveal is live-only: NO defaults write. Require a running app + ack, else exit 3.
        guard Control.runningSnapshot() != nil else {
            if json { print("{\"ok\":false,\"reason\":\"app-not-running\"}") }
            throw fail("app not running — reveal requires the running app", code: CLIExit.appNotRunning)
        }
        let requestID = Control.post(action: .reveal(holdSeconds: hold))
        if Control.waitForAck(requestID) {
            if json { print("{\"ok\":true,\"appliedLive\":true}") } else { print("ok") }
        } else {
            if json { print("{\"ok\":false,\"reason\":\"no-ack\"}") }
            throw fail("app did not confirm the reveal in time", code: CLIExit.appNotRunning)
        }
    }
}

// MARK: - small helpers

/// Run a `ControlValidation` throw and re-surface a failure as exit 2 with a clean message (no
/// ArgumentParser usage spew, and code 2 not EX_USAGE=64).
func requireValid<T>(_ body: () throws -> T) throws -> T {
    do {
        return try body()
    } catch let error as ControlError {
        throw fail(error.description, code: CLIExit.badInput)
    }
}

enum JSONString {
    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
