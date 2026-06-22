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

    /// One-line, plain-language description of the selected mode — the SINGLE source of truth shared by
    /// the popover Mode control and Settings → Schedule, so the two never drift.
    var subtitle: String {
        switch self {
        case .followSunset: return "Warms automatically around your local sunset."
        case .alwaysOn: return "Warms continuously, day and night."
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

// MARK: - ModeControl (A3 "Living Glyph" — chosen finalist)
//
// The Schedule either-or (Sunset · Always on) as a larger Liquid-Glass segmented control whose
// SELECTED segment's glyph comes alive once and then HOLDS: the Sunset sun dips below a horizon;
// the Always-on sun blooms its rays and settles (no perpetual motion). The selection slides on the
// brand's warm ease and the chosen segment wears the sunset gradient as lit glass.
//
// Design source: brand/explorations/schedule-toggle/finalist-a3-living-glyph.html (variation A3.1).
// Picked over the rotary-dial finalist for legibility + nativeness. `BrandSegmentedControl` (below)
// is retained unchanged for the app's other small pickers. `compact` gives the popover a tighter
// version while Settings / Onboarding use the full showcase size.
struct ModeControl: View {
    @Binding var selection: ScheduleModeOption
    var compact: Bool = false
    var onChange: (ScheduleModeOption) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var pillNamespace
    @State private var hovered: ScheduleModeOption?

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
        // Native Liquid Glass track (frosted ember, the macOS-Tahoe material) + a hairline rim.
        .glassSurface(.frost, cornerRadius: trackRadius)
        .overlay(
            RoundedRectangle(cornerRadius: trackRadius, style: .continuous)
                .strokeBorder(Theme.Color.lineStrong, lineWidth: 0.5)
        )
        .animation(Theme.Motion.warm(reduceMotion: reduceMotion), value: selection)
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
                ModeGlyph(size: glyphSize, ink: ink, option: option,
                          isSelected: isSelected, reduceMotion: reduceMotion)
                    .frame(width: glyphSize, height: glyphSize)
                Text(option.label)
                    .font(Theme.Typography.ui(labelSize, weight: isSelected ? .bold : .semibold))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.vertical, vPad)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .background {
                if isSelected {
                    selectedPill.matchedGeometryEffect(id: "modePill", in: pillNamespace)
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
            withAnimation(Theme.Motion.warm(reduceMotion: reduceMotion)) {
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
        onChange(option)
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
}

// MARK: - ModeGlyph
//
// The living sun glyph for one segment, drawn proportionally to `size` (so compact + full share one
// recipe). The animation is a ONE-SHOT keyed off `isSelected` that settles via springs — never loops:
// · Sunset → the sun disc dips below a clipped horizon; faint dusk rays fade in.
// · Always → the eight rays bloom out (staggered scale-in) and the core gives one settle pulse.
// Under Reduce Motion every spring resolves instantly (nil animation), so state is correct with no motion.
private struct ModeGlyph: View {
    let size: CGFloat
    let ink: Color
    let option: ScheduleModeOption
    let isSelected: Bool
    let reduceMotion: Bool

    /// Unit scale from the canonical 46pt design grid.
    private var s: CGFloat { size / 46 }

    var body: some View {
        ZStack {
            switch option {
            case .followSunset: sunsetGlyph
            case .alwaysOn:     alwaysGlyph
            }
        }
        .frame(width: size, height: size)
    }

    // MARK: Sunset — sun dips below the horizon (one-shot)

    private var sunsetGlyph: some View {
        let discY: CGFloat = isSelected ? 30 * s : 19 * s   // dipped vs. riding high
        return ZStack {
            // faint dusk rays above the dipping sun (fade in when chosen)
            ZStack {
                Capsule().fill(ink).frame(width: 2.4 * s, height: 3.6 * s).offset(y: -13.5 * s)
                Capsule().fill(ink).frame(width: 2.4 * s, height: 3.4 * s).offset(y: -13.5 * s)
                    .rotationEffect(.degrees(-42))
                Capsule().fill(ink).frame(width: 2.4 * s, height: 3.4 * s).offset(y: -13.5 * s)
                    .rotationEffect(.degrees(42))
            }
            .opacity(isSelected ? 0.5 : 0)
            .animation(glyphAnim(.easeWarm), value: isSelected)

            // the sun disc, clipped to the sky (above the horizon) so it can set
            Circle().fill(ink)
                .frame(width: 16.8 * s, height: 16.8 * s)
                .position(x: size / 2, y: discY)
                .animation(glyphAnim(.dip), value: isSelected)
                .mask(
                    Rectangle()
                        .frame(width: size, height: 31 * s)
                        .position(x: size / 2, y: 31 * s / 2)
                )

            // horizon (a bright line + a fainter ground line)
            Capsule().fill(ink).frame(width: 36 * s, height: 2.6 * s)
                .position(x: size / 2, y: 31 * s)
            Capsule().fill(ink).frame(width: 24 * s, height: 2.4 * s).opacity(0.42)
                .position(x: size / 2, y: 37 * s)
        }
    }

    // MARK: Always on — rays bloom and settle (one-shot)

    private var alwaysGlyph: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                Capsule().fill(ink)
                    .frame(width: 2.6 * s, height: 6 * s)
                    .offset(y: -13.5 * s)
                    .frame(width: size, height: size)          // expand bounds → anchor at glyph centre
                    .rotationEffect(.degrees(Double(i) * 45))
                    .scaleEffect(isSelected ? 1 : 0.62, anchor: .center)
                    .opacity(isSelected ? 1 : 0.4)
                    .animation(glyphAnim(.bloom, delay: Double(i) * 0.025), value: isSelected)
            }
            Circle().fill(ink)
                .frame(width: 16 * s, height: 16 * s)
                .scaleEffect(isSelected ? 1 : 0.9)
                .animation(glyphAnim(.settle), value: isSelected)
        }
    }

    // MARK: Motion (one-shot, settles; nil under Reduce Motion)

    private enum GlyphMove { case dip, bloom, settle, easeWarm }

    private func glyphAnim(_ move: GlyphMove, delay: Double = 0) -> Animation? {
        guard !reduceMotion else { return nil }
        switch move {
        case .dip:      return .spring(response: 0.44, dampingFraction: 0.74).delay(delay)
        case .bloom:    return .spring(response: 0.34, dampingFraction: 0.62).delay(delay)
        case .settle:   return .spring(response: 0.40, dampingFraction: 0.64).delay(delay)
        case .easeWarm: return Theme.Motion.warm.delay(delay)
        }
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
                .font(Theme.Typography.ui(12, weight: isSelected ? .bold : .medium))
                // Dark ink on the bright gradient (the app's high-contrast convention) — cream/white on
                // the light-gold top of the ramp fails contrast. Muted on the dark track when unselected.
                .foregroundStyle(isSelected ? Theme.Color.inkOnAccent : Theme.Color.textMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
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
    @ViewBuilder
    private var selectedPill: some View {
        if reduceMotion {
            selectedPillBase
        } else {
            selectedPillBase
                .keyframeAnimator(initialValue: Stretch(), trigger: selection) { pill, stretch in
                    pill.scaleEffect(x: stretch.x, y: stretch.y)
                } keyframes: { _ in
                    KeyframeTrack(\.x) {
                        CubicKeyframe(1.08, duration: 0.12)
                        SpringKeyframe(1.0, duration: 0.24, spring: .snappy)
                    }
                    KeyframeTrack(\.y) {
                        CubicKeyframe(0.94, duration: 0.12)
                        SpringKeyframe(1.0, duration: 0.24, spring: .snappy)
                    }
                }
        }
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

    private struct Stretch {
        var x: CGFloat = 1
        var y: CGFloat = 1
    }
}
