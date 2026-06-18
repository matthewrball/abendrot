import SwiftUI
import WarmthKit

// MARK: - ScheduleModeOption
//
// A UI-facing projection of the contract's `ScheduleMode` (which carries associated
// values that don't fit a segmented control). Maps the four product modes from
// plan: Follow sunset · Schedule · Always on · Off.
enum ScheduleModeOption: String, CaseIterable, Identifiable {
    case followSunset
    case schedule
    case alwaysOn
    case off

    var id: String { rawValue }

    var label: String {
        switch self {
        case .followSunset: return "Follow sunset"
        case .schedule: return "Schedule"
        case .alwaysOn: return "Always on"
        case .off: return "Off"
        }
    }

    /// Classify a contract `ScheduleMode` into a UI option.
    init(_ mode: ScheduleMode) {
        switch mode {
        case .followSystemNightShift, .solar: self = .followSunset
        case .custom: self = .schedule
        case .alwaysOn: self = .alwaysOn
        case .off: self = .off
        }
    }

    /// Produce a contract `ScheduleMode` for this option.
    ///
    /// `.schedule` needs a concrete `CustomSchedule`; until the Settings → Schedule
    /// tab wires a real editor, we hand the engine a sensible provisional evening
    /// ramp. TODO(settings): replace with the user-configured custom schedule.
    func toScheduleMode(currentCustom: CustomSchedule? = nil) -> ScheduleMode {
        switch self {
        case .followSunset: return .followSystemNightShift
        case .schedule:
            let provisional = CustomSchedule(
                start: DateComponents(hour: 19, minute: 0),
                end: DateComponents(hour: 6, minute: 0),
                warmest: WarmthLevel(strength: 0.7)
            )
            return .custom(currentCustom ?? provisional)
        case .alwaysOn: return .alwaysOn
        case .off: return .off
        }
    }
}

// MARK: - ModeControl

/// The ember-styled segmented control for schedule mode.
struct ModeControl: View {
    @Binding var selection: ScheduleModeOption
    var onChange: (ScheduleModeOption) -> Void

    var body: some View {
        Picker("Mode", selection: $selection) {
            ForEach(ScheduleModeOption.allCases) { option in
                Text(option.label).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .tint(Theme.Color.accent)
        .onChange(of: selection) { _, newValue in
            onChange(newValue)
        }
    }
}
