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
    /// Absolute timed-pause end, when one is active. Omitted by older snapshots.
    public var pauseUntil: Date?
    /// `TimedPause.Kind` raw value.
    public var pauseKind: String?
    /// Standing fullscreen-cover preference. Nil on a snapshot that predates the field.
    public var pausesForFullScreen: Bool?
    /// Sunset mode's late-night stage as configured. Nil on a snapshot that predates the field.
    public var lateNight: LateNightSnapshot?
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
        pauseUntil: Date? = nil,
        pauseKind: String? = nil,
        pausesForFullScreen: Bool? = nil,
        lateNight: LateNightSnapshot? = nil,
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
        self.pauseUntil = pauseUntil
        self.pauseKind = pauseKind
        self.pausesForFullScreen = pausesForFullScreen
        self.lateNight = lateNight
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

// MARK: - LateNightSnapshot
//
// Sunset mode's opt-in late-night stage, as `status --json` reports it under `lateNight`. The
// whole object is optional on `ControlStateSnapshot`, and the fields added after the first four
// settings are optional here, so an older app's snapshot and an older CLI both keep decoding with
// no `schemaVersion` bump. `bedtime` and `kelvin` are derived in the init, so the app's snapshot
// and the CLI's configured-values fallback cannot disagree on either.
public struct LateNightSnapshot: Codable, Sendable, Equatable {
    public var enabled: Bool
    /// Bedtime on the Mac's own clock, 24-hour "HH:MM".
    public var bedtime: String
    /// The same bedtime as minutes after midnight, 0..<1440.
    public var bedtimeMinutes: Int
    /// The saved late-night warmth, 0.0–1.0 on the everyday curve. Kept while `cozy` overrides it.
    public var warmthStrength: Double
    /// The colour the screen reaches at bedtime: Cozy's floor when `cozy`, else `warmthStrength`
    /// on the everyday curve.
    public var kelvin: Int
    /// Go all the way to Cozy at bedtime.
    public var cozy: Bool
    /// Length of the ease that ends at bedtime, in minutes.
    public var easeMinutes: Int?
    /// What the stage is doing to the screen right now, from the running app only. One of the
    /// `LateNightPhase` raw values:
    /// - `inactive`: not contributing (daytime, the evening before the ease, another mode, the
    /// stage or warmth off), or the screen is held neutral by a pause or a reveal;
    /// - `easing`: getting warmer over the ease before bed;
    /// - `held`: the ease is done and nothing is moving;
    /// - `releasing`: on its way back to day, after sunrise or over the last hour before midday.
    ///
    /// Nil when the app is closed. A plain string, so a consumer must tolerate values it does not
    /// know: `releasing` was added after the first three without a `schemaVersion` bump.
    public var phase: String?

    public static let phaseInactive = LateNightPhase.inactive.rawValue
    public static let phaseEasing = LateNightPhase.easing.rawValue
    public static let phaseHeld = LateNightPhase.held.rawValue
    public static let phaseReleasing = LateNightPhase.releasing.rawValue

    public init(
        enabled: Bool,
        bedtimeMinutes: Int,
        warmthStrength: Double,
        cozy: Bool,
        easeMinutes: Int?,
        phase: String? = nil
    ) {
        self.enabled = enabled
        self.bedtime = Self.clock(minutes: bedtimeMinutes)
        self.bedtimeMinutes = ((bedtimeMinutes % 1440) + 1440) % 1440
        self.warmthStrength = warmthStrength
        self.kelvin = Self.targetKelvin(strength: warmthStrength, cozy: cozy).value
        self.cozy = cozy
        self.easeMinutes = easeMinutes
        self.phase = phase
    }

    /// The stage from raw saved preferences (nil = key absent), with the defaults and repairs the
    /// app applies on launch. The app's load and the CLI's app-closed fallback both come through
    /// here, so `get` and `status` report what the app will actually use.
    public static func configured(
        enabled: Bool?, bedtimeMinutes: Int?, warmthStrength: Double?, cozy: Bool?, easeMinutes: Int?,
        phase: String? = nil
    ) -> LateNightSnapshot {
        LateNightSnapshot(
            enabled: enabled ?? false,
            bedtimeMinutes: bedtimeMinutes.map(LateNightStage.clampedBedtime(minutesOfDay:))
                ?? LateNightStage.defaultBedtimeMinutes,
            warmthStrength: warmthStrength.flatMap { try? ControlValidation.validatedStrength($0) } ?? 1,
            cozy: cozy ?? false,
            easeMinutes: easeMinutes.map(LateNightStage.nearestEaseMinutes(to:)) ?? LateNightStage.defaultEaseMinutes,
            phase: phase
        )
    }

    /// The one rule for the late-night colour, shared by the app, the snapshot and the CLI.
    public static func targetKelvin(strength: Double, cozy: Bool) -> Kelvin {
        cozy ? .warmestSupported : WarmthLevel(strength: strength).kelvin(warmestPoint: .everydayWarmest)
    }

    /// Minutes after midnight (any integer; wrapped into one day) as 24-hour "HH:MM".
    public static func clock(minutes: Int) -> String {
        let clock = ((minutes % 1440) + 1440) % 1440
        let hour = clock / 60, minute = clock % 60
        return (hour < 10 ? "0" : "") + String(hour) + ":" + (minute < 10 ? "0" : "") + String(minute)
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
// Per-display status the CLI surfaces under `status`. `appliedMethod` and `lastError` are live
// runtime truth only; `preferredMethod`, `warmthStrength`/`warmthOverridden`, and DDC opt-in also
// mirror the persisted per-display Settings choices. Keyed by the stable display id.
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
