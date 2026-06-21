import Foundation

// MARK: - SettingsPatch
//
// A partial set of settings to change. Each `nil` field means "leave unchanged". The CLI does
// the add/remove math itself and sends the FULL replacement set for `excludedApps`, so the app
// never has to diff — it just applies what's present through its existing setters. This keeps the
// app's apply path identical to a UI interaction (plan §2.2).
public struct SettingsPatch: Codable, Sendable, Equatable {
    public var isEnabled: Bool?
    /// Validated 0.0...1.0 by `ControlValidation.validatedStrength`.
    public var globalWarmthStrength: Double?
    /// Validated 500...6500 by `ControlValidation.validatedKelvin` (the `Kelvin` clamp domain).
    public var warmestPointKelvin: Int?
    public var scheduleMode: ControlScheduleMode?
    /// "hold" | "toggle" — validated by `ControlValidation.validatedRevealMode`.
    public var revealMode: String?
    /// The FULL replacement exclusion set (sorted). The CLI computes add/remove before sending.
    public var excludedApps: [String]?
    public var userLatitude: Double?
    public var userLongitude: Double?
    /// `true` == `--auto`: clear the manual coordinate (remove both lat/lon keys).
    public var clearUserCoordinate: Bool?

    public init(
        isEnabled: Bool? = nil,
        globalWarmthStrength: Double? = nil,
        warmestPointKelvin: Int? = nil,
        scheduleMode: ControlScheduleMode? = nil,
        revealMode: String? = nil,
        excludedApps: [String]? = nil,
        userLatitude: Double? = nil,
        userLongitude: Double? = nil,
        clearUserCoordinate: Bool? = nil
    ) {
        self.isEnabled = isEnabled
        self.globalWarmthStrength = globalWarmthStrength
        self.warmestPointKelvin = warmestPointKelvin
        self.scheduleMode = scheduleMode
        self.revealMode = revealMode
        self.excludedApps = excludedApps
        self.userLatitude = userLatitude
        self.userLongitude = userLongitude
        self.clearUserCoordinate = clearUserCoordinate
    }

    /// True when no field is set — used by the app to decide a message is a no-op patch.
    public var isEmpty: Bool {
        isEnabled == nil && globalWarmthStrength == nil && warmestPointKelvin == nil
            && scheduleMode == nil && revealMode == nil && excludedApps == nil
            && userLatitude == nil && userLongitude == nil && clearUserCoordinate == nil
    }
}

// MARK: - ControlAction
//
// A transient, non-persisted action (currently just the momentary reveal-true-color peek). Kept
// separate from `SettingsPatch` because it never touches CFPreferences — it is live-only and the
// CLI requires a running app + ack for it (plan §2.1 "transient actions").
public enum ControlAction: Codable, Sendable, Equatable {
    case reveal(holdSeconds: Double?)
}

// MARK: - ControlMessage
//
// The full payload the CLI posts and the app decodes: a schema/requestID envelope around an
// optional `SettingsPatch` (live apply of persisted settings) and/or an optional `ControlAction`
// (transient). `requestID` lets the CLI verify its own change landed by watching
// `state.json.lastAppliedRequestID`.
public struct ControlMessage: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var requestID: String
    public var writtenAt: Date
    public var patch: SettingsPatch?
    public var action: ControlAction?

    public init(
        requestID: String,
        writtenAt: Date,
        patch: SettingsPatch? = nil,
        action: ControlAction? = nil
    ) {
        self.schemaVersion = AbendrotControl.schemaVersion
        self.requestID = requestID
        self.writtenAt = writtenAt
        self.patch = patch
        self.action = action
    }
}

// MARK: - DistributedNotification userInfo packing
//
// A distributed-notification `userInfo` must be a property list. JSON `Data` IS a valid plist
// value, so we JSON-encode the whole `ControlMessage` under ONE key and surface the schema +
// requestID as plain plist scalars for cheap inspection. Encoding the message once, as Data,
// keeps plist-correctness in a single tested place — the app and CLI cannot drift on the shape,
// and the transport-safety test proves the dict survives a real plist round-trip.
public extension ControlMessage {
    static let userInfoPayloadKey = "payload"
    static let userInfoSchemaKey = "schemaVersion"
    static let userInfoRequestIDKey = "requestID"

    /// Pack into a plist-safe `userInfo` dict. Throws only if JSON encoding fails (it won't for
    /// this fixed Codable shape, but the API is honest about it).
    func toUserInfo() throws -> [String: Any] {
        let data = try JSONEncoder().encode(self)
        return [
            Self.userInfoSchemaKey: schemaVersion,
            Self.userInfoRequestIDKey: requestID,
            Self.userInfoPayloadKey: data,
        ]
    }

    /// Unpack from a received `userInfo`. Returns nil if the payload is absent or undecodable —
    /// the app treats that as the raw-`defaults` fallback path (reload from disk).
    static func from(userInfo: [AnyHashable: Any]?) -> ControlMessage? {
        guard let data = userInfo?[userInfoPayloadKey] as? Data else { return nil }
        return try? JSONDecoder().decode(ControlMessage.self, from: data)
    }
}
