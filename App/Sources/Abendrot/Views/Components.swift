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

/// The signature warm-tinted "Softer ⟷ Warmer" strength slider (plan §4.1). Strength is the
/// canonical control; the Kelvin readout now lives only in the popover header (one animated
/// number), not beside the slider. Wraps the system `Slider` for accessibility + keyboard,
/// restyled with the ember track.
struct WarmSlider: View {
    @Binding var strength: Double
    var compact: Bool = false

    /// True while the thumb is being pressed/dragged — drives the Liquid-Glass "grab" feedback
    /// (a springy scale-up + brighter glow), mirroring the master toggle's press effect.
    @GestureState private var isPressing = false

    private var trackHeight: CGFloat { compact ? 5 : 7 }
    private var thumbSize: CGFloat { compact ? 15 : 20 }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 9) {
            if !compact {
                // Kelvin readout intentionally omitted here — it lives only in the popover header
                // now (one canonical, animated number), so the slider isn't a second place to read.
                Text("Warmth")
                    .font(Theme.Typography.ui(13, weight: .medium))
                    .foregroundStyle(Theme.Color.textMuted)
            }

            gradientSlider

            HStack {
                Text("Softer")
                Spacer()
                Text("Warmer")
            }
            .font(Theme.Typography.ui(11.5))
            .foregroundStyle(Theme.Color.textMuted)
        }
    }

    // MARK: Custom gradient slider
    //
    // The system `Slider` can't wear a gradient, so the track is custom: the brand sunset ramp —
    // gold at "Softer", deep ember toward "Warmer" — under a glassy thumb. Tap-anywhere to set, and
    // ←/→ + VoiceOver (adjustable) keep keyboard/a11y parity with the control it replaces.
    private var gradientSlider: some View {
        GeometryReader { geo in
            let usable = max(geo.size.width - thumbSize, 1)
            let thumbX = CGFloat(strength.clamped01) * usable

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)                       // unfilled groove
                    .fill(Theme.Color.line.opacity(0.55))
                    .frame(height: trackHeight)

                Capsule(style: .continuous)                       // full gradient, masked to the fill
                    .fill(Theme.Gradient.sunsetHorizontal)
                    .frame(height: trackHeight)
                    .mask(alignment: .leading) {
                        Capsule(style: .continuous)
                            .frame(width: thumbX + thumbSize / 2, height: trackHeight)
                    }

                glassThumb(pressed: isPressing)
                    .frame(width: thumbSize, height: thumbSize)
                    .scaleEffect(isPressing ? 1.14 : 1.0)
                    .animation(.spring(response: 0.28, dampingFraction: 0.62), value: isPressing)
                    .offset(x: thumbX)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isPressing) { _, state, _ in state = true }
                    .onChanged { value in
                        strength = Double((value.location.x - thumbSize / 2) / usable).clamped01
                    }
            )
        }
        .frame(height: max(thumbSize, 22))
        // No `.focusable()`: a menu-bar NSPopover doesn't do tab-traversal, so it only produced a
        // stray focus ring on click. VoiceOver still adjusts via the action below.
        .accessibilityElement()
        .accessibilityLabel("Warmth")
        .accessibilityValue("\(Int((strength * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: nudge(0.05)
            case .decrement: nudge(-0.05)
            default: break
            }
        }
    }

    private func nudge(_ delta: Double) { strength = (strength + delta).clamped01 }

    /// A glassy thumb: a bright warm-white core, a hairline rim, and a soft ember glow. On press the
    /// rim brightens and the ember glow blooms — the Liquid-Glass "grab" feedback.
    private func glassThumb(pressed: Bool) -> some View {
        Circle()
            .fill(LinearGradient(colors: [.white, Theme.Color.accentHi], startPoint: .top, endPoint: .bottom))
            .overlay(Circle().strokeBorder(.white.opacity(pressed ? 0.95 : 0.7), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
            .shadow(color: Theme.Color.accentDeep.opacity(pressed ? 0.5 : 0.35), radius: pressed ? 9 : 5)
    }
}

private extension Double {
    var clamped01: Double { Swift.min(1, Swift.max(0, self)) }
}

// MARK: - DisplayRow (simple popover)

/// A glanceable per-display row: name + method badge (plan §4.1).
struct DisplayRow: View {
    let display: DisplayState
    /// True when this display can ONLY be tinted — no true-warm path is available to it (gamma
    /// unsupported on this chip/OS AND not DDC-capable). Surfaced honestly so we never imply true
    /// warming where the hardware/OS can't deliver it. (§25.J — DRAFT, iterating with founder.)
    var tintOnly: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(display.name)
                    .font(Theme.Typography.ui(12.5))
                    .foregroundStyle(Theme.Color.textPrimary)
                HStack(spacing: 4) {
                    Text(subtitle)
                        .font(Theme.Typography.ui(10.5))
                        .foregroundStyle(tintOnly ? Theme.Color.accentHighlight : Theme.Color.textFaint)
                    if tintOnly {
                        Image(systemName: "exclamationmark.circle")
                            .font(Theme.Typography.ui(10))
                            .foregroundStyle(Theme.Color.accentHighlight)
                            .help("Your Mac can’t truly warm this display on this macOS version (a known limitation on some Apple-silicon chips). Abendrot is tinting it instead. If it’s an external monitor with on-screen brightness controls, try Hardware DDC in the per-display engine controls.")
                            .accessibilityLabel("Can only be tinted, not truly warmed")
                    }
                }
            }
            Spacer()
            MethodBadge(method: display.appliedMethod)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(Theme.Color.line.opacity(0.4), in: RoundedRectangle(cornerRadius: Theme.Radius.control - 1, style: .continuous))
    }

    private var subtitle: String {
        if tintOnly { return "Tint only — can’t truly warm" }
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
