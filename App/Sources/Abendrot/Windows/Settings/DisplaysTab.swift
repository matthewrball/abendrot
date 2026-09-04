import SwiftUI
import WarmthKit

// MARK: - Displays

struct DisplaysTab: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            TabHeader(title: model.state.displays.count == 1 ? "Display" : "Displays", subtitle: "Each connected display and its warming settings.")
            if let inactiveMessage {
                Label(inactiveMessage, systemImage: "clock")
                    .font(Theme.Typography.ui(11.5))
                    .foregroundStyle(Theme.Color.textMuted)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        Theme.Color.line.opacity(0.4),
                        in: RoundedRectangle(cornerRadius: Theme.Radius.control - 1, style: .continuous)
                    )
            }
            VStack(spacing: 12) {
                ForEach(model.state.displays) { display in
                    DisplayConfigRow(display: display, model: model)
                }
            }
        }
    }

    private var inactiveMessage: String? {
        if !model.state.isEnabled {
            return "Warming is turned off. Changes are saved and apply when you turn it on."
        }
        if model.state.isRevealing {
            return "True Color Reveal is active. Changes are saved and apply when it ends."
        }
        if !model.state.isScheduleActiveNow {
            return "Warming is not active right now. Changes are saved and apply when warming is active."
        }
        return nil
    }
}

/// One display in Settings → Displays: its name, a plain-language status of whether it can be truly
/// warmed or only tinted, and a per-display "Advanced" disclosure revealing the warming-method
/// picker. This *is* the "Displays → Advanced" compatibility section — the engine/method jargon
/// (gamma / DDC / overlay badges) that used to sit on these rows is now expressed in plain language
/// here and nowhere else.
private struct DisplayConfigRow: View {
    let display: DisplayState
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(display.name)
                    .font(Theme.Typography.ui(13, weight: .medium))
                    .foregroundStyle(Theme.Color.textPrimary)
                Text(statusLine)
                    .font(Theme.Typography.ui(11.5))
                    .foregroundStyle(Theme.Color.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // The warming-method picker + per-display warmth show INLINE — no "Advanced" disclosure. This
            // tab exists to configure each display, so its controls shouldn't hide behind a chevron.
            DividerLine()
            WarmingMethodPicker(display: display, model: model)
            PerDisplayWarmthControl(display: display, model: model)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 12)
        .background(Theme.Color.line.opacity(0.4),
                    in: RoundedRectangle(cornerRadius: Theme.Radius.control - 1, style: .continuous))
    }

    private var statusLine: String {
        switch display.appliedMethod {
        case .hardware:
            return "Using display hardware"
        case .gamma:
            return "Using standard color adjustment"
        case .overlay:
            return "Using a warm screen tint"
        case .off:
            switch display.preferredMethod {
            case .hardware:
                return "Hardware control selected"
            case .overlay:
                return "Screen tint selected"
            default:
                return "Automatic method selected"
            }
        }
    }
}

// MARK: - Per-display override + custom warmth (Settings superset of the popover quick control)

/// The Settings → Displays version of the menu-bar popover's per-display "Override" control. Same
/// wiring (`setWarmthOverride` / `setWarmth`, `display.warmthOverridden` / `display.warmth`) for
/// experience congruency, in the roomier Settings layout. Settings is the superset — custom warmth
/// AND warming method; the popover stays the quick, override-only version.
private struct PerDisplayWarmthControl: View {
    let display: DisplayState
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Override")
                        .font(Theme.Typography.ui(11.5, weight: .medium))
                        .foregroundStyle(display.warmthOverridden ? Theme.Color.textPrimary : Theme.Color.textMuted)
                    Text(display.warmthOverridden ? "Custom warmth for this display" : "Follows the global warmth")
                        .font(Theme.Typography.ui(11))
                        .foregroundStyle(display.warmthOverridden ? Theme.Color.textMuted : Theme.Color.textFaint)
                }
                Spacer()
                Toggle("", isOn: overrideBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(Theme.Color.accent)
                    .accessibilityLabel("Override warmth for \(display.name)")
            }
            if display.warmthOverridden {
                // WarmSlider already renders its own Softer/Warmer caption (and a "Warmth" header when
                // not compact) — so use the compact slider and don't add a second caption row. The
                // "Override · Custom warmth for this display" header above is label enough. (Fixes the
                // duplicate Softer/Warmer.)
                WarmSlider(strength: warmthBinding, model: model, compact: true)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
        .animation(Theme.Motion.controlReveal(reduceMotion: reduceMotion), value: display.warmthOverridden)
    }

    private var overrideBinding: Binding<Bool> {
        Binding(get: { display.warmthOverridden }, set: { model.setWarmthOverride($0, for: display.id) })
    }

    private var warmthBinding: Binding<Double> {
        Binding(get: { display.warmth.strength }, set: { model.setWarmth($0, for: display.id) })
    }
}

// MARK: - Warming-method picker (plain-language per-display layer choice)

/// The de-jargoned per-display warming-method control. Plain labels: **Automatic /
/// Screen tint / Hardware control** map onto the engine's `DisplayMethod` override.
/// Only methods actually usable for this display are offered, so the available options themselves
/// communicate what the hardware/OS supports.
private struct WarmingMethodPicker: View {
    let display: DisplayState
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Warming method")
                .font(Theme.Typography.ui(11.5, weight: .medium))
                .foregroundStyle(Theme.Color.textMuted)

            if availableChoices.count == 1, let choice = availableChoices.first {
                Text(choice.label)
                    .font(Theme.Typography.ui(12, weight: .bold))
                    .foregroundStyle(Theme.Color.inkOnAccent)
                    .lineLimit(1)
                    .padding(.vertical, 7)
                    .padding(.horizontal, 16)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Theme.Gradient.sunset)
                            .overlay(Capsule(style: .continuous).strokeBorder(.white.opacity(0.16), lineWidth: 0.5))
                    )
                    .accessibilityLabel("Warming method: \(choice.label)")
            } else {
                BrandSegmentedControl(
                    options: availableChoices,
                    selection: choiceBinding,
                    label: \.label,
                    onChange: { _ in }
                )
            }

            if let note = unavailableNote {
                Text(note)
                    .font(Theme.Typography.ui(11))
                    .foregroundStyle(Theme.Color.textFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 2)
    }

    /// The methods offered for this display, in UI order, filtered to what's usable right now.
    private var availableChoices: [WarmingMethodChoice] {
        let priv = model.state.privateAPIsEnabled
        var choices: [WarmingMethodChoice] = [.standard, .screenTint]    // automatic + overlay always work
        if priv, display.capabilities.hardware.isSupported { choices.append(.hardwareControl) }
        return choices
    }

    private var choiceBinding: Binding<WarmingMethodChoice> {
        Binding(
            get: {
                switch display.preferredMethod {
                case .gamma:
                    if availableChoices.contains(.standard) { return .standard }
                case .overlay:
                    if availableChoices.contains(.screenTint) { return .screenTint }
                case .hardware:
                    if availableChoices.contains(.hardwareControl) { return .hardwareControl }
                default:
                    break
                }
                return availableChoices.contains(.standard) ? .standard : .screenTint
            },
            set: { apply($0) }
        )
    }

    /// Hardware control opts into DDC; Screen tint opts out. Automatic only clears the layer
    /// override, preserving the user's DDC opt-in as an input to the resolver.
    private func apply(_ choice: WarmingMethodChoice) {
        switch choice {
        case .hardwareControl:
            model.setHardwareDDCEnabled(true, for: display.id)
            model.setPreferredMethod(.hardware, for: display.id)
        case .screenTint:
            model.setHardwareDDCEnabled(false, for: display.id)
            model.setPreferredMethod(.overlay, for: display.id)
        case .standard:
            model.setPreferredMethod(nil, for: display.id)
        }
    }

    private var unavailableNote: String? {
        let priv = model.state.privateAPIsEnabled
        if !priv {
            return "Advanced warming isn’t available on this Mac, so only a screen tint is possible."
        }
        if !display.capabilities.gamma.isSupported, !display.capabilities.hardware.isSupported {
            return "This display can’t be truly warmed on this Mac — only a screen tint is available."
        }
        return nil
    }
}

/// Plain-language names for the per-display warming method. Automatic clears the override so the
/// engine can choose the best usable layer; Screen tint = overlay; Hardware control = DDC.
private enum WarmingMethodChoice: String, CaseIterable, Identifiable, Sendable {
    case standard, screenTint, hardwareControl
    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard: return "Automatic"
        case .screenTint: return "Screen tint"
        case .hardwareControl: return "Hardware control"
        }
    }

}
