import Foundation

// MARK: - ControlStateSnapshot
//
// The Codable DTO the app writes to ~/Library/Application Support/Abendrot/state.json on every
// state change and after every accepted control message. `WarmthState` is intentionally NOT
// Codable, so this is the read model the CLI consumes for `status` and for verifying its own
// changes via `lastAppliedRequestID`.
//
// Liveness is "snapshot decodes AND `kill(pid, 0) == 0`" — never file mtime, because a healthy
// idle app emits no state ticks for long stretches (plan §2.2.3).
public struct ControlStateSnapshot: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var appVersion: String          // CFBundleShortVersionString
    public var appBuild: String            // CFBundleVersion
    public var pid: Int32
    public var appLaunchID: String         // UUID, regenerated each app launch
    public var updatedAt: Date
    public var lastAppliedRequestID: String?

    public var isEnabled: Bool
    public var scheduleMode: ControlScheduleMode
    public var isScheduleActiveNow: Bool
    public var isRevealing: Bool
    public var globalWarmthStrength: Double
    public var globalKelvin: Int
    public var warmestPointKelvin: Int
    public var revealMode: String
    public var excludedApps: [String]
    public var displays: [DisplaySnapshot]

    public init(
        schemaVersion: Int = AbendrotControl.schemaVersion,
        appVersion: String,
        appBuild: String,
        pid: Int32,
        appLaunchID: String,
        updatedAt: Date,
        lastAppliedRequestID: String?,
        isEnabled: Bool,
        scheduleMode: ControlScheduleMode,
        isScheduleActiveNow: Bool,
        isRevealing: Bool,
        globalWarmthStrength: Double,
        globalKelvin: Int,
        warmestPointKelvin: Int,
        revealMode: String,
        excludedApps: [String],
        displays: [DisplaySnapshot]
    ) {
        self.schemaVersion = schemaVersion
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.pid = pid
        self.appLaunchID = appLaunchID
        self.updatedAt = updatedAt
        self.lastAppliedRequestID = lastAppliedRequestID
        self.isEnabled = isEnabled
        self.scheduleMode = scheduleMode
        self.isScheduleActiveNow = isScheduleActiveNow
        self.isRevealing = isRevealing
        self.globalWarmthStrength = globalWarmthStrength
        self.globalKelvin = globalKelvin
        self.warmestPointKelvin = warmestPointKelvin
        self.revealMode = revealMode
        self.excludedApps = excludedApps
        self.displays = displays
    }

    /// ~/Library/Application Support/Abendrot/state.json — the one path both ends agree on.
    public static func fileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent(AbendrotControl.appSupportDirectoryName, isDirectory: true)
            .appendingPathComponent(AbendrotControl.stateFileName)
    }

    /// The directory that holds `state.json` (created user-only by the app on first write).
    public static func directoryURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent(AbendrotControl.appSupportDirectoryName, isDirectory: true)
    }
}

// MARK: - DisplaySnapshot
//
// Per-display read-only status the CLI surfaces under `status` — the live runtime truth that is
// NOT in UserDefaults (applied method, override, DDC, last error). Keyed by the stable display id.
public struct DisplaySnapshot: Codable, Sendable, Equatable {
    public var id: String                  // DisplayIdentity.cgUUID.uuidString
    public var name: String
    public var appliedMethod: String       // DisplayMethod.rawValue
    public var preferredMethod: String?    // DisplayMethod.rawValue, or nil for automatic
    public var warmthStrength: Double
    public var warmthOverridden: Bool
    public var isHardwareDDCEnabled: Bool
    public var lastError: String?

    public init(
        id: String,
        name: String,
        appliedMethod: String,
        preferredMethod: String?,
        warmthStrength: Double,
        warmthOverridden: Bool,
        isHardwareDDCEnabled: Bool,
        lastError: String?
    ) {
        self.id = id
        self.name = name
        self.appliedMethod = appliedMethod
        self.preferredMethod = preferredMethod
        self.warmthStrength = warmthStrength
        self.warmthOverridden = warmthOverridden
        self.isHardwareDDCEnabled = isHardwareDDCEnabled
        self.lastError = lastError
    }
}
