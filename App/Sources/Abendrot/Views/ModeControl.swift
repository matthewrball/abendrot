import SwiftUI
import WarmthKit

// MARK: - ScheduleModeOption
//
// A UI-facing projection of the contract's `ScheduleMode` (which carries associated
// values that don't fit a segmented control). Exposes the two user-selectable modes —
// Sunset · Manual — while the engine's other ScheduleMode cases stay dormant.
enum ScheduleModeOption: String, CaseIterable, Identifiable {
    case followSunset
    case alwaysOn

    var id: String { rawValue }

    var label: String {
        switch self {
        case .followSunset: return "Sunset"
        case .alwaysOn: return "Manual"
        }
    }

    /// One-line, plain-language description of the selected mode — the SINGLE source of truth shared by
    /// the popover Mode control and Settings → Schedule, so the two never drift.
    var subtitle: String {
        switch self {
        case .followSunset: return "Warms automatically around your local sunset."
        case .alwaysOn: return "Stays warm until you turn it off."
        }
    }

    var symbolName: String {
        switch self {
        case .followSunset: return "sunset"
        case .alwaysOn: return "sun.max"
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
//
// The Schedule either-or (Sunset · Manual) as a larger Liquid-Glass segmented control whose
// selected native glyph responds once: Sunset settles downward; Manual's rays rotate. There is no
// perpetual motion, and Reduce Motion keeps the state change instant. `compact` gives the popover a
// tighter version while Settings and onboarding use the full size.
struct ModeControl: View {
    @Binding var selection: ScheduleModeOption
    var compact: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered: ScheduleModeOption?
    @State private var sunsetGlyphTrigger = 0
    @State private var manualGlyphTrigger = 0

    // Sizing: full (Settings/Onboarding) vs compact (popover, stays glanceable).
    private var glyphSize: CGFloat { compact ? 30 : 42 }
    private var labelSize: CGFloat { compact ? 12.5 : 14.5 }
    private var stackGap: CGFloat { compact ? 7 : 11 }
    private var vPad: CGFloat { compact ? 12 : 18 }
    private var pillRadius: CGFloat { compact ? 13 : 16 }
    private var trackPad: CGFloat { compact ? 5 : 7 }
    private var trackRadius: CGFloat { pillRadius + trackPad }

    var body: some View {
        HStack(spacing: compact ? 6 : 8) {
            segment(.followSunset)
            segment(.alwaysOn)
        }
        .padding(trackPad)
        .background(modeTrack)
        .overlay(
            RoundedRectangle(cornerRadius: trackRadius, style: .continuous)
                .strokeBorder(Theme.Color.lineStrong, lineWidth: 0.5)
        )
        .animation(selectionAnimation, value: selection)
        .onChange(of: selection) { _, option in
            guard !reduceMotion else { return }
            switch option {
            case .followSunset: sunsetGlyphTrigger &+= 1
            case .alwaysOn: manualGlyphTrigger &+= 1
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Schedule mode")
    }

    // MARK: Segments

    private func segment(_ option: ScheduleModeOption) -> some View {
        let isSelected = option == selection
        // Dark ink on the bright gradient (the app's high-contrast convention); muted on the track.
        let ink = isSelected ? Theme.Color.inkOnAccent : Theme.Color.textMuted
        return Button {
            select(option)
        } label: {
            VStack(spacing: stackGap) {
                Image(systemName: option.symbolName + (isSelected ? ".fill" : ""))
                    .font(.system(size: compact ? 23 : 31, weight: .semibold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(ink)
                    .frame(width: glyphSize, height: glyphSize)
                    .symbolEffect(
                        .bounce.down.wholeSymbol,
                        options: .nonRepeating.speed(1.4),
                        value: option == .followSunset ? sunsetGlyphTrigger : 0
                    )
                    .symbolEffect(
                        .rotate.clockwise.byLayer,
                        options: .nonRepeating.speed(1.4),
                        value: option == .alwaysOn ? manualGlyphTrigger : 0
                    )
                    .symbolEffectsRemoved(reduceMotion)
                    .accessibilityHidden(true)
                Text(option.label)
                    // Keep label metrics stable; the moving pill and ink color carry selection.
                    .font(Theme.Typography.ui(labelSize, weight: .semibold))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.vertical, vPad)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .background {
                if isSelected {
                    selectedPill
                } else if hovered == option {
                    // Native hover highlight on the unselected segment.
                    RoundedRectangle(cornerRadius: pillRadius, style: .continuous)
                        .fill(.white.opacity(0.06))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: pillRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { inside in
            withAnimation(selectionAnimation) {
                if inside { hovered = option } else if hovered == option { hovered = nil }
            }
        }
        .accessibilityLabel(option.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func select(_ option: ScheduleModeOption) {
        // Fires only on a real change → the glyph flourish never re-fires on no-op taps (audit fix).
        guard option != selection else { return }
        selection = option
    }

    // MARK: Brand surfaces

    /// The selected segment: sunset gradient + specular sheen + hairline rim + soft ember glow → lit glass.
    private var selectedPill: some View {
        RoundedRectangle(cornerRadius: pillRadius, style: .continuous)
            .fill(Theme.Gradient.sunset)
            .overlay(
                RoundedRectangle(cornerRadius: pillRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.36), .white.opacity(0.06), .clear],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .blendMode(.softLight)
            )
            .overlay(RoundedRectangle(cornerRadius: pillRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
            .shadow(color: Theme.Color.accentDeep.opacity(0.42), radius: 6, y: 1.5)
            .shadow(color: Theme.Color.accent.opacity(0.30), radius: 14)   // soft ember glow
    }

    private var modeTrack: some View {
        RoundedRectangle(cornerRadius: trackRadius, style: .continuous)
            .fill(Theme.Color.line.opacity(0.42))
            .overlay {
                RoundedRectangle(cornerRadius: trackRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.055), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
    }

    private var selectionAnimation: Animation? {
        Theme.Motion.warm(reduceMotion: reduceMotion)
    }
}

// MARK: - BrandSegmentedControl

/// Reusable liquid-glass segmented control for small brand choices. Keeps Mode and Settings'
/// warming-method picker visually identical without falling back to the system segmented picker.
struct BrandSegmentedControl<Option: Identifiable & Equatable & Sendable>: View {
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> String
    var onChange: (Option) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var pillNamespace
    @State private var hovered: Option?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                segment(option)
            }
        }
        .padding(3)
        .background(track)
        .clipShape(Capsule(style: .continuous))
        .animation(segmentAnimation, value: selection)
        .animation(segmentAnimation, value: hovered)
    }

    // MARK: Segments

    private func segment(_ option: Option) -> some View {
        let isSelected = option == selection
        return Button {
            select(option)
        } label: {
            Text(label(option))
                // Keep label metrics stable; the moving pill and ink color carry selection.
                .font(Theme.Typography.ui(12, weight: .semibold))
                // Dark ink on the bright gradient (the app's high-contrast convention) — cream/white on
                // the light-gold top of the ramp fails contrast. Muted on the dark track when unselected.
                .foregroundStyle(isSelected ? Theme.Color.inkOnAccent : Theme.Color.textMuted)
                .lineLimit(1)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity)
                .background {
                    if isSelected {
                        selectedPill.matchedGeometryEffect(id: "selectedPill", in: pillNamespace)
                    } else if hovered == option {
                        Capsule(style: .continuous)
                            .fill(.white.opacity(0.055))
                    }
                }
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hovered = inside ? option : (hovered == option ? nil : hovered)
        }
        .accessibilityElement()
        .accessibilityLabel(label(option))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func select(_ option: Option) {
        guard option != selection else { return }
        withAnimation(segmentAnimation) { selection = option }
        onChange(option)
    }

    // MARK: Brand surfaces

    /// The selected segment: the sunset gradient with a top sheen + soft warm glow → liquid glass.
    private var selectedPill: some View {
        selectedPillBase
    }

    private var selectedPillBase: some View {
        Capsule(style: .continuous)
            .fill(Theme.Gradient.sunsetHorizontal)
            .overlay {
                Capsule(style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.42), .white.opacity(0.08), .clear],
                                         startPoint: .top, endPoint: .bottom))
                    .blendMode(.softLight)
            }
            .overlay(Capsule(style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
            .shadow(color: Theme.Color.accentDeep.opacity(0.42), radius: 5, y: 1.5)
            .shadow(color: Theme.Color.accent.opacity(0.24), radius: 12)
    }

    /// The recessed track the segments sit in — a subtle dark glass capsule.
    private var track: some View {
        Capsule(style: .continuous)
            .fill(Theme.Color.line.opacity(0.5))
            .overlay(
                Capsule(style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.055), .clear],
                                         startPoint: .top, endPoint: .bottom))
                    .blendMode(.softLight)
            )
            .overlay(Capsule(style: .continuous).strokeBorder(Theme.Color.lineStrong, lineWidth: 0.5))
    }

    private var segmentAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.76, blendDuration: 0.06)
    }
}
