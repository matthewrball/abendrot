import ArgumentParser
import Foundation
import WarmthCore
import AbendrotControl

// MARK: - Control
//
// The shared CLI core: persist settings to the app's CFPreferences domain, post the live
// `settingsChanged` notification, and read the app's `state.json` snapshot for `status` + acks.
// A thin client — never drives displays itself. All four pieces (persist / post / snapshot /
// liveness) live here so every subcommand routes through one tested path.
enum Control {

    // MARK: Liveness

    /// True iff a snapshot exists (in full OR minimal form) and its pid is alive. Used for the
    /// "is the app running?" gate on `set`/`reveal`. Forward-tolerant: a newer app whose full
    /// snapshot no longer decodes here still counts as running via the minimal liveness read.
    static func isRunning() -> Bool {
        guard let liveness = readLiveness() else { return false }
        return pidAlive(liveness.pid)
    }

    /// The full snapshot when it both decodes AND its pid is alive — used where the rich fields are
    /// needed. Never use file mtime: a healthy idle app can go a long time between state ticks, so
    /// mtime would wrongly read a quiet-but-running app as stale.
    static func runningSnapshot() -> ControlStateSnapshot? {
        guard let snapshot = readSnapshot() else { return nil }
        return pidAlive(snapshot.pid) ? snapshot : nil
    }

    /// Decode the full current snapshot, retrying briefly on a transient/partial read (the app writes
    /// atomically, so a partial read should be rare, but a decode failure mid-replace is possible).
    /// Returns nil if the current shape no longer matches — callers that only need liveness/ack use
    /// `readLiveness()` instead, which tolerates a forward-incompatible (newer-app) snapshot.
    static func readSnapshot() -> ControlStateSnapshot? {
        let url = ControlStateSnapshot.fileURL()
        for attempt in 0..<3 {
            guard let data = try? Data(contentsOf: url) else { return nil }
            if let snapshot = try? JSONDecoder().decode(ControlStateSnapshot.self, from: data) {
                return snapshot
            }
            if attempt < 2 { usleep(30_000) }   // 30ms, then retry
        }
        return nil
    }

    /// Read only the fields needed for liveness and ack, decoding a MINIMAL struct so a future app
    /// snapshot — new required field, changed type on a field we don't read, or a higher
    /// `schemaVersion` — still reports `running` correctly and still lets a `set` confirm its ack.
    /// JSONDecoder ignores unknown keys; the real forward-incompat risk is a new *required* field on
    /// the full struct, which this minimal struct sidesteps. Same 3-try transient-read retry.
    static func readLiveness() -> ControlLiveness? {
        let url = ControlStateSnapshot.fileURL()
        for attempt in 0..<3 {
            guard let data = try? Data(contentsOf: url) else { return nil }
            if let liveness = try? JSONDecoder().decode(ControlLiveness.self, from: data) {
                return liveness
            }
            if attempt < 2 { usleep(30_000) }   // 30ms, then retry
        }
        return nil
    }

    /// `kill(pid, 0)` probes existence without sending a signal: 0 = alive, ESRCH = gone.
    static func pidAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM   // exists but owned by another user (shouldn't happen here)
    }

    // MARK: Persist (CFPreferences — the app's preference domain)

    private static var domain: CFString { AbendrotControl.preferenceDomain as CFString }

    /// Write one value (nil removes the key) to the app's preference domain, then synchronize so the
    /// on-disk plist is updated for the next app launch and a fresh CFPreferences read.
    static func setPreference(_ key: String, _ value: CFPropertyList?) {
        CFPreferencesSetAppValue(key as CFString, value, domain)
    }

    static func synchronize() {
        CFPreferencesAppSynchronize(domain)
    }

    /// Read one value back from the app's preference domain (for `get`/`status` when the app is
    /// closed). Synchronizes first so a write by another process is visible.
    static func preference(_ key: String) -> CFPropertyList? {
        CFPreferencesAppSynchronize(domain)
        return CFPreferencesCopyAppValue(key as CFString, domain)
    }

    // MARK: Typed configured-value reads (persisted CFPreferences — used when computing patches)

    static func configuredBool(_ key: String) -> Bool? {
        (preference(key) as? NSNumber)?.boolValue
    }
    static func configuredInt(_ key: String) -> Int? {
        (preference(key) as? NSNumber)?.intValue
    }
    static func configuredDouble(_ key: String) -> Double? {
        (preference(key) as? NSNumber)?.doubleValue
    }
    static func configuredString(_ key: String) -> String? {
        preference(key) as? String
    }

    /// The persisted warmest-point ceiling, or the engine default (1900K) when unset — used to map a
    /// `set warmth --kelvin` target to a strength against the right curve.
    static func configuredWarmestPoint() -> Kelvin {
        if let value = configuredInt(PreferenceKey.warmestPointKelvin) {
            return Kelvin(value)
        }
        return Kelvin.everydayWarmest
    }

    /// The persisted schedule mode (engine `ScheduleMode` decoded from the JSON `Data`), defaulting
    /// to Sunset when unset/malformed.
    static func configuredScheduleMode() -> ControlScheduleMode {
        guard let data = preference(PreferenceKey.scheduleMode) as? Data,
              let mode = try? JSONDecoder().decode(ScheduleMode.self, from: data) else {
            return .sunset
        }
        return ControlScheduleMode(mode)
    }

    /// The persisted exclusion set (sorted), empty when unset.
    static func configuredExcludedApps() -> [String] {
        (preference(PreferenceKey.excludedApps) as? [String])?.sorted() ?? []
    }

    /// The persisted manual coordinate, or nil (= Auto).
    static func configuredCoordinate() -> (lat: Double, lon: Double)? {
        guard let lat = configuredDouble(PreferenceKey.userLatitude),
              let lon = configuredDouble(PreferenceKey.userLongitude) else { return nil }
        return (lat, lon)
    }

    /// Persist a `SettingsPatch` to CFPreferences with the EXACT encodings AppModel reads:
    /// Bool/Double/Int/String/[String] as their plist scalars, and `scheduleMode` as the JSON
    /// `Data` of the engine `ScheduleMode` (matching AppModel's `JSONEncoder().encode(mode)` write).
    static func persist(_ patch: SettingsPatch) {
        if let v = patch.isEnabled {
            setPreference(PreferenceKey.isEnabled, v as CFBoolean)
        }
        if let v = patch.globalWarmthStrength {
            setPreference(PreferenceKey.globalWarmthStrength, v as CFNumber)
        }
        if let v = patch.warmestPointKelvin {
            setPreference(PreferenceKey.warmestPointKelvin, v as CFNumber)
        }
        if let v = patch.scheduleMode {
            let data = try? JSONEncoder().encode(v.toScheduleMode())
            setPreference(PreferenceKey.scheduleMode, data as CFData?)
        }
        if let v = patch.revealMode {
            setPreference(PreferenceKey.revealMode, v as CFString)
        }
        if let v = patch.excludedApps {
            setPreference(PreferenceKey.excludedApps, v.sorted() as CFArray)
        }
        if patch.clearUserCoordinate == true {
            setPreference(PreferenceKey.userLatitude, nil)
            setPreference(PreferenceKey.userLongitude, nil)
        } else if let lat = patch.userLatitude, let lon = patch.userLongitude {
            setPreference(PreferenceKey.userLatitude, lat as CFNumber)
            setPreference(PreferenceKey.userLongitude, lon as CFNumber)
        }
        synchronize()
    }

    // MARK: Post (live apply)

    /// Post the `settingsChanged` notification carrying a `ControlMessage`. `deliverImmediately`
    /// wakes the app even when idle. Returns the requestID so the caller can poll for the ack.
    @discardableResult
    static func post(patch: SettingsPatch? = nil, action: ControlAction? = nil) -> String {
        let requestID = UUID().uuidString
        let message = ControlMessage(
            requestID: requestID, writtenAt: Date(), patch: patch, action: action)
        let userInfo = try? message.toUserInfo()
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(AbendrotControl.settingsChangedNotification),
            object: nil,
            userInfo: userInfo,
            deliverImmediately: true
        )
        return requestID
    }

    // MARK: Ack

    /// Poll `state.json.lastAppliedRequestID` until it equals `requestID` (the app applied our
    /// command) or the timeout elapses. ~50ms cadence up to ~1.5s by default.
    static func waitForAck(_ requestID: String, timeout: TimeInterval = 1.5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            // Use the minimal liveness read, not the full snapshot decode, so the ack still lands
            // against a newer app whose full snapshot shape we no longer decode.
            if let liveness = readLiveness(), liveness.lastAppliedRequestID == requestID {
                return true
            }
            usleep(50_000)   // 50ms
        }
        if let liveness = readLiveness(), liveness.lastAppliedRequestID == requestID {
            return true
        }
        return false
    }
}

// MARK: - CLI exit codes
//
// Exact POSIX-ish codes: 0 ok · 2 bad input · 3 app-not-running / no live ack for a command that
// REQUIRES the app (reveal) · 4 live-apply timeout after a successful persist. These do NOT match
// ArgumentParser's `ValidationError` (which exits EX_USAGE=64), so we print our own message to
// stderr and throw ArgumentParser's `ExitCode(n)` — which exits with code `n` and prints nothing.
// `main.swift` also remaps ArgumentParser's own parse/validation 64 down to 2 to keep this contract.
enum CLIExit {
    static let badInput: Int32 = 2
    static let appNotRunning: Int32 = 3
    static let liveApplyTimeout: Int32 = 4
}

/// Print `message` to stderr, then throw the given exit code (ArgumentParser exits with it silently).
func fail(_ message: String, code: Int32) -> ExitCode {
    printErr(message)
    return ExitCode(code)
}

/// Print to stderr (errors, "saved; app not running" notices).
func printErr(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}
