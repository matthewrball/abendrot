import Foundation
import WarmthCore

// MARK: - ControlScheduleMode
//
// The CLI's stable, lossless schedule vocabulary. The UI's `ScheduleModeOption` deliberately
// collapses `.off` → Sunset (the master toggle owns on/off), but the CLI must NOT — an agent
// that writes `set mode off` and reads it back has to get `off`. So the control surface keeps
// its own three-case enum and maps to/from the engine's `ScheduleMode`.
//
// `sunset` ↔ `.followSystemNightShift` (the real local-sunset path), `always-on` ↔ `.alwaysOn`,
// `off` ↔ `.off`. The engine's `.solar`/`.custom` cases are dormant in the app (no UI contract)
// and read back as `sunset` — consistent with how the app itself projects them.
public enum ControlScheduleMode: String, Codable, Sendable, CaseIterable, Equatable {
    case sunset
    case alwaysOn = "always-on"
    case off

    /// Project an engine `ScheduleMode` into the stable CLI vocabulary.
    public init(_ mode: ScheduleMode) {
        switch mode {
        case .alwaysOn:
            self = .alwaysOn
        case .off:
            self = .off
        case .followSystemNightShift, .solar, .custom:
            self = .sunset
        }
    }

    /// Produce the engine `ScheduleMode` the CLI should persist/apply for this control mode.
    /// `sunset` writes `.followSystemNightShift` — the SAME case the app's UI writes for Sunset —
    /// so the CLI and the UI persist byte-identical `scheduleMode` data.
    public func toScheduleMode() -> ScheduleMode {
        switch self {
        case .sunset:
            return .followSystemNightShift
        case .alwaysOn:
            return .alwaysOn
        case .off:
            return .off
        }
    }
}
