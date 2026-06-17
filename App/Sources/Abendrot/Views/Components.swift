import SwiftUI
import WarmthKit

// MARK: - Shared Abendrot UI components
//
// Mirrors brand/explorations/components.html: warm slider, segmented mode control,
// method badges, per-display rows. Provisional structure — final motion polish + the
// "wet glass" specular/lens treatment are deferred to the /design-motion-principles
// + brand-lock pass (§21.3). Hooks/TODOs are left explicit, not faked.

// MARK: - MethodBadge

/// The trust-proof badge showing HOW a display is warmed (Hardware / Gamma / Overlay).
/// Drives directly from `DisplayState.appliedMethod` (the contract's `DisplayMethod`).
struct MethodBadge: View {
    let method: DisplayMethod

    var body: some View {
        Text(method.badge.uppercased())
            .font(Theme.Typography.ui(10, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(background, in: Capsule())
    }

    private var foreground: Color {
        switch method {
        case .hardware, .gamma, .overlay: return Theme.Color.groundIndigo
        case .off: return Theme.Color.textMuted
        }
    }

    // Hardware = best (green), Gamma = ember, Overlay = safe default (lilac-on-ember).
    private var background: AnyShapeStyle {
        switch method {
        case .hardware:
            return AnyShapeStyle(
                LinearGradient(colors: [Theme.Color.accentHighlight, Theme.Color.accent],
                               startPoint: .top, endPoint: .bottom)
            )
        case .gamma:
            return AnyShapeStyle(
                LinearGradient(colors: [Theme.Color.accentHighlight, Theme.Color.accentPress],
                               startPoint: .top, endPoint: .bottom)
            )
        case .overlay:
            return AnyShapeStyle(Theme.Color.accentHi)
        case .off:
            return AnyShapeStyle(Theme.Color.line)
        }
    }
}

// MARK: - WarmSlider

/// The signature warm-tinted "Softer ⟷ Warmer" strength slider. Kelvin is secondary
/// (shown as a label), per plan §4.1. Wraps the system `Slider` for accessibility +
/// keyboard, restyled with the ember track.
struct WarmSlider: View {
    @Binding var strength: Double
    var kelvin: Kelvin?
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 9) {
            if !compact {
                HStack(alignment: .firstTextBaseline) {
                    Text("Warmth")
                        .font(Theme.Typography.ui(13, weight: .medium))
                        .foregroundStyle(Theme.Color.textMuted)
                    Spacer()
                    if let kelvin {
                        Text("\(kelvin.value) K")
                            .font(Theme.Typography.serif(13))
                            .monospacedDigit()
                            .foregroundStyle(Theme.Color.accentHighlight)
                    }
                }
            }

            Slider(value: $strength, in: 0...1)
                .controlSize(compact ? .small : .regular)
                .tint(Theme.Color.accent)

            HStack {
                Text("Softer")
                Spacer()
                Text("Warmer")
            }
            .font(Theme.Typography.ui(11.5))
            .foregroundStyle(Theme.Color.textMuted)
        }
    }
}

// MARK: - DisplayRow (simple popover)

/// A glanceable per-display row: name + method badge (plan §4.1).
struct DisplayRow: View {
    let display: DisplayState

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(display.name)
                    .font(Theme.Typography.ui(12.5))
                    .foregroundStyle(Theme.Color.textPrimary)
                Text(subtitle)
                    .font(Theme.Typography.ui(10.5))
                    .foregroundStyle(Theme.Color.textFaint)
            }
            Spacer()
            MethodBadge(method: display.appliedMethod)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(Theme.Color.line.opacity(0.4), in: RoundedRectangle(cornerRadius: Theme.Radius.control - 1, style: .continuous))
    }

    private var subtitle: String {
        switch display.appliedMethod {
        case .hardware: return "via DDC/CI"
        case .gamma: return "gamma table"
        case .overlay: return "Metal overlay"
        case .off: return "not warmed"
        }
    }
}

// MARK: - SectionLabel

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(Theme.Typography.ui(11, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(Theme.Color.textFaint)
    }
}

// MARK: - DividerLine

struct DividerLine: View {
    var body: some View {
        Rectangle()
            .fill(Theme.Color.lineStrong)
            .frame(height: 0.5)
    }
}
