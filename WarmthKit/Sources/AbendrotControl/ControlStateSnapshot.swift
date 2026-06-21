import Foundation
import WarmthCore

// MARK: - ControlStateSnapshot
//
// The Codable DTO the app writes to ~/Library/Application Support/Abendrot/state.json on every
// state change and after every accepted control message. `WarmthState` is intentionally NOT
// Codable, so this is the read model the CLI consumes for `status` and for verifying its own
// changes via `lastAppliedRequestID`.
//
// Liveness is "snapshot decodes AND `kill(pid, 0) == 0`" — never file mtime, because a healthy
// idle app emits no state ticks for long stretches, so mtime would read as stale while running.
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
    /// Cozy mode — derived from the warmest point so the snapshot can never disagree with the engine:
    /// the expanded-warmth ceiling is in effect exactly when it sits below the everyday 1900K cap. Held
    /// as a stored field (not computed) so it lands in `state.json` / `status --json` for agents, and
    /// `Self.isCozy(warmestPointKelvin:)` keeps the one derivation rule shared with the app + CLI.
    public var cozy: Bool
    public var revealMode: String
    public var excludedApps: [String]
    public var displays: [DisplaySnapshot]

    /// The single source of truth for "is cozy on": the warmest-point ceiling is below the everyday
    /// 1900K cap. Used by the app to set the snapshot field and by the CLI to read it from a patch.
    public static func isCozy(warmestPointKelvin: Int) -> Bool {
        warmestPointKelvin < Kelvin.everydayWarmest.value
    }

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
        // Derived in the init so every snapshot is internally consistent (cozy ⇔ ceiling < 1900K).
        self.cozy = Self.isCozy(warmestPointKelvin: warmestPointKelvin)
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

// MARK: - ControlLiveness
//
// A MINIMAL forward-compatible view of `state.json` — just the fields the CLI needs to answer
// "is the app running?" and "did it apply my request?". The CLI decodes THIS (not the full
// `ControlStateSnapshot`) for liveness and ack, so a newer app whose full snapshot grows a new
// required field, changes a type, or bumps `schemaVersion` is still seen as running and can still
// confirm a `set`. JSONDecoder ignores unknown keys; the forward-incompat risk is a new *required*
// field on the full struct — keeping this set tiny (and all the same names/types) sidesteps it.
public struct ControlLiveness: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var pid: Int32
    public var appLaunchID: String
    public var updatedAt: Date
    public var lastAppliedRequestID: String?

    public init(
        schemaVersion: Int,
        pid: Int32,
        appLaunchID: String,
        updatedAt: Date,
        lastAppliedRequestID: String?
    ) {
        self.schemaVersion = schemaVersion
        self.pid = pid
        self.appLaunchID = appLaunchID
        self.updatedAt = updatedAt
        self.lastAppliedRequestID = lastAppliedRequestID
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
