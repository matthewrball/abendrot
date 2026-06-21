import Foundation
import WarmthCore

// MARK: - AbendrotControl
//
// The shared control-surface schema — the single source of truth for the app bundle id,
// the CFPreferences domain, the distributed-notification name, the Application Support
// paths, and the wire schema version. BOTH the running app and the `abendrot` CLI depend
// on this pure-Swift target so the two can never drift on a preference-key string, an enum
// encoding, or the snapshot/message shape. This is exactly where AI-facing CLIs rot — so we
// share the schema itself, not just the underlying `WarmthCore` engine types.
//
// Pure Foundation + WarmthCore ONLY — no AppKit / IOKit / CoreGraphics — so the CLI links
// it headlessly. `WarmthState` stays non-Codable; `ControlStateSnapshot` is the Codable DTO.
public enum AbendrotControl {
    /// Bumped only on a breaking change to the message/snapshot wire shape. Both ends stamp
    /// it into every `ControlMessage` and `ControlStateSnapshot` so a mismatch is detectable.
    public static let schemaVersion = 1

    /// The app's bundle identifier — also its CFPreferences application id (preference domain).
    public static let appBundleID = "app.abendrot.Abendrot"

    /// CFPreferences applicationID == the app's bundle id (its preference-domain plist at
    /// ~/Library/Preferences/app.abendrot.Abendrot.plist).
    public static let preferenceDomain = "app.abendrot.Abendrot"

    /// DistributedNotification name: the app observes it, the CLI posts it. Same login session
    /// only — never `postToAllSessions`, which keeps the control surface inside the user's own
    /// session as a security boundary.
    public static let settingsChangedNotification = "app.abendrot.settingsChanged"

    /// Sub-directory under ~/Library/Application Support that holds the live `state.json`.
    public static let appSupportDirectoryName = "Abendrot"

    /// Live control snapshot file name (the CLI reads it for `status` + ack).
    public static let stateFileName = "state.json"
}

// MARK: - PreferenceKey
//
// The CFPreferences keys the app persists and the CLI writes. These MUST exactly equal the
// strings `AppModel` persists today — AppModel re-exports them through its `*Key` constants so
// there is one literal per setting across the whole codebase, with no chance of the two drifting.
//
//   isEnabled              Bool
//   globalWarmthStrength   Double
//   warmestPointKelvin     Int
//   scheduleMode           Data (Codable JSON of ScheduleMode — carries associated values)
//   revealMode             String (RevealMode.rawValue: "hold" | "toggle")
//   excludedApps           [String] (sorted bundle ids)
//   userLatitude           Double
//   userLongitude          Double
public enum PreferenceKey {
    public static let isEnabled = "isEnabled"
    public static let globalWarmthStrength = "globalWarmthStrength"
    public static let warmestPointKelvin = "warmestPointKelvin"
    public static let scheduleMode = "scheduleMode"
    public static let revealMode = "revealMode"
    public static let excludedApps = "excludedApps"
    public static let userLatitude = "userLatitude"
    public static let userLongitude = "userLongitude"
}
