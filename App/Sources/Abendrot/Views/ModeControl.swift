import SwiftUI
import WarmthKit

// MARK: - ScheduleModeOption
//
// A UI-facing projection of the contract's `ScheduleMode` (which carries associated
// values that don't fit a segmented control). Exposes the two user-selectable modes —
// Sunset · Always on — while the engine's other ScheduleMode cases stay dormant.
enum ScheduleModeOption: String, CaseIterable, Identifiable {
    case followSunset
    case alwaysOn

    var id: String { rawValue }

    var label: String {
        switch self {
        case .followSunset: return "Sunset"
        case .alwaysOn: return "Always on"
        }
    }

    /// Classify a contract `ScheduleMode` into a UI option. There is no "Off" option — the master
    /// "Warm my displays" toggle owns on/off — so a (UI-less) engine `.off` maps to the Sunset
    /// default. The manual "Schedule" (custom-time) option was removed; the engine's `.custom` case
    /// is kept dormant for a future editor, so a persisted `.custom` also shows as Sunset.
    init(_ mode: ScheduleMode) {
        switch mode {
        case .followSystemNightShift, .solar, .custom, .off: self = .followSunset
        case .alwaysOn: self = .alwaysOn
        }
    }

    /// Produce a contract `ScheduleMode` for this option. Only Sunset (real solar) and Always-on are
    /// user-selectable; the engine's `.custom` schedule stays dormant for a future custom editor.
    func toScheduleMode() -> ScheduleMode {
        switch self {
        case .followSunset: return .followSystemNightShift
        case .alwaysOn: return .alwaysOn
        }
    }
}

// MARK: - ModeControl

/// The ember-styled segmented control for schedule mode (plan §4.1). A custom segmented control
/// (not the system `Picker`) so the selected segment can wear the sunset gradient under a liquid-
/// glass sheen, and the selection slides between segments with the brand's warm ease.
struct ModeControl: View {
    @Binding var selection: ScheduleModeOption
    var onChange: (ScheduleModeOption) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var pillNamespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ScheduleModeOption.allCases) { option in
                segment(option)
            }
        }
        .padding(3)
        .background(track)
        .clipShape(Capsule(style: .continuous))
    }

    // MARK: Segments

    private func segment(_ option: ScheduleModeOption) -> some View {
        let isSelected = option == selection
        return Text(option.label)
            .font(Theme.Typography.ui(12, weight: isSelected ? .bold : .medium))
            // Dark ink on the bright gradient (the app's high-contrast convention) — cream/white on
            // the light-gold top of the ramp fails contrast. Muted on the dark track when unselected.
            .foregroundStyle(isSelected ? Theme.Color.groundIndigo : Theme.Color.textMuted)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background {
                if isSelected {
                    selectedPill.matchedGeometryEffect(id: "selectedPill", in: pillNamespace)
                }
            }
            .contentShape(Capsule(style: .continuous))
            .onTapGesture { select(option) }
            .accessibilityElement()
            .accessibilityLabel(option.label)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func select(_ option: ScheduleModeOption) {
        guard option != selection else { return }
        withAnimation(Theme.Motion.warm(reduceMotion: reduceMotion)) { selection = option }
        onChange(option)
    }

    // MARK: Brand surfaces

    /// The selected segment: the sunset gradient with a top sheen + soft warm glow → liquid glass.
    private var selectedPill: some View {
        Capsule(style: .continuous)
            .fill(Theme.Gradient.sunset)
            .overlay(
                // Specular top sheen so the fill reads as wet glass, not flat paint.
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.32), .white.opacity(0.04), .clear],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .blendMode(.softLight)
            )
            .overlay(Capsule(style: .continuous).strokeBorder(.white.opacity(0.16), lineWidth: 0.5))
            .shadow(color: Theme.Color.accentDeep.opacity(0.45), radius: 5, y: 1.5)
    }

    /// The recessed track the segments sit in — a subtle dark glass capsule.
    private var track: some View {
        Capsule(style: .continuous)
            .fill(Theme.Color.line.opacity(0.5))
            .overlay(Capsule(style: .continuous).strokeBorder(Theme.Color.lineStrong, lineWidth: 0.5))
    }
}
