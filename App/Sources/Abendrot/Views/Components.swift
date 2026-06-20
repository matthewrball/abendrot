import SwiftUI
import AppKit
import WarmthKit

// MARK: - Shared Abendrot UI components
//
// Mirrors brand/explorations/components.html: warm slider, segmented mode control,
// per-display rows. Provisional structure — final motion polish + the "wet glass"
// specular/lens treatment are deferred to the /design-motion-principles + brand-lock
// pass (§21.3). Hooks/TODOs are left explicit, not faked.
//
// The old engine "method badge" (Hardware / Gamma / Overlay) was removed from the UI in the
// §26 de-jargon pass — warming method is now expressed in plain language in the popover rows and
// Settings → Displays → Advanced, never as a raw badge.

// MARK: - WarmSlider

/// The signature warm-tinted "Softer ⟷ Warmer" strength slider (plan §4.1). Strength is the
/// canonical control; the Kelvin readout now lives only in the popover header (one animated
/// number), not beside the slider. Wraps the system `Slider` for accessibility + keyboard,
/// restyled with the ember track.
struct WarmSlider: View {
    @Binding var strength: Double
    var compact: Bool = false
    /// When provided (the popover's main slider), the Warmth row shows this Kelvin readout inline,
    /// with an info tooltip. Other callers pass nil (they have their own readouts).
    var kelvin: Kelvin?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// True while the thumb is being pressed/dragged — drives the Liquid-Glass "grab" feedback
    /// (a springy scale-up + brighter glow), mirroring the master toggle's press effect.
    @GestureState private var isPressing = false
    /// Drives the Kelvin info tooltip (shown on hover of the ⓘ).
    @State private var showKelvinInfo = false

    private var trackHeight: CGFloat { compact ? 5 : 7 }
    private var thumbSize: CGFloat { compact ? 15 : 20 }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 9) {
            if !compact {
                warmthHeaderRow
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
        .overlay(alignment: .topTrailing) {
            if showKelvinInfo, kelvin != nil {
                kelvinTooltip
                    .offset(y: 24)
                    .transition(.scale(scale: 0.9, anchor: .topTrailing).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .animation(.spring(response: 0.30, dampingFraction: 0.82), value: showKelvinInfo)
    }

    // MARK: Warmth header (label + inline Kelvin + info tooltip)

    private var warmthHeaderRow: some View {
        HStack(spacing: 6) {
            Text("Warmth")
                .font(Theme.Typography.ui(13, weight: .medium))
                .foregroundStyle(Theme.Color.textMuted)
            Spacer()
            if let kelvin {
                Text("\(kelvin.displayValue)K")
                    .font(Theme.Typography.serif(13))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Color.accentHighlight)
                    .contentTransition(.numericText(value: Double(kelvin.displayValue)))
                    .animation(Theme.Motion.warm(reduceMotion: reduceMotion), value: kelvin.displayValue)
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(showKelvinInfo ? Theme.Color.accentHighlight : Theme.Color.textFaint)
                    .onHover { showKelvinInfo = $0 }
                    .accessibilityLabel("What is Kelvin?")
                    .accessibilityHint(kelvinInfoText)
            }
        }
    }

    private var kelvinInfoText: String {
        "Kelvin is colour temperature — lower numbers are warmer and give off less blue light."
    }

    /// A small frosted-glass card explaining the Kelvin readout, animated in on hover.
    private var kelvinTooltip: some View {
        Text(kelvinInfoText)
            .font(Theme.Typography.ui(11))
            .foregroundStyle(Theme.Color.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: 188, alignment: .leading)
            .padding(11)
            .glassSurface(.frost, cornerRadius: 12)
            .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
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
    @Bindable var model: AppModel
    let display: DisplayState
    /// True when this display can ONLY be tinted — no true-warm path is available to it. Surfaced
    /// honestly (plain language, no jargon) so we never imply true warming where the hardware/OS
    /// can't deliver it. (§25.J)
    var tintOnly: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(display.name)
                        .font(Theme.Typography.ui(12.5))
                        .foregroundStyle(Theme.Color.textPrimary)
                    HStack(spacing: 4) {
                        // Small warning glyph (matches the §25.J banner) so the tint-only tooltip is
                        // discoverable, not just hover-anywhere. Hovering either icon or text shows it.
                        if tintOnly {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(Theme.Typography.ui(8.5))
                                .foregroundStyle(Theme.Color.accentHighlight)
                        }
                        Text(subtitle)
                            .font(Theme.Typography.ui(10.5))
                            .foregroundStyle(tintOnly ? Theme.Color.accentHighlight : Theme.Color.textFaint)
                    }
                    .help(tintOnlyExplanation)
                }
                Spacer()
                Text("Override")
                    .font(Theme.Typography.ui(11.5))
                    .foregroundStyle(Theme.Color.textMuted)
                // Per-display override toggle — off = follows global warmth.
                Toggle("", isOn: overrideBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .tint(Theme.Color.accent)
                    .accessibilityLabel("Override warmth for \(display.name)")
            }

            // The per-display slider exists only while the override is on, revealed calmly below.
            if display.warmthOverridden {
                WarmSlider(strength: warmthBinding, compact: true)
                    .padding(.top, 10)
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(Theme.Color.line.opacity(0.4), in: RoundedRectangle(cornerRadius: Theme.Radius.control - 1, style: .continuous))
        .animation(Theme.Motion.controlReveal(reduceMotion: reduceMotion), value: display.warmthOverridden)
    }

    private var subtitle: String {
        if tintOnly { return "Tint only" }
        return display.warmthOverridden ? "Custom warmth" : "Follows global warmth"
    }

    private var tintOnlyExplanation: String {
        tintOnly
            ? "Abendrot can only add a warm colour tint to this display on this Mac — true warming (removing blue light) isn’t available for it."
            : subtitle
    }

    private var overrideBinding: Binding<Bool> {
        Binding(
            get: { display.warmthOverridden },
            set: { model.setWarmthOverride($0, for: display.id) }
        )
    }

    private var warmthBinding: Binding<Double> {
        Binding(
            get: { display.warmth.strength },
            set: { model.setWarmth($0, for: display.id) }
        )
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

// MARK: - AppIconView

/// The real app icon (the sunset squircle from `AppIcon`), matching the Dock/Finder icon. Falls back
/// to the vector `SunsetArcGlyph` if the icon image can't be loaded. Used in the popover header and
/// Settings → About (the menu-bar status item keeps the monochrome template glyph).
struct AppIconView: View {
    var body: some View {
        if let icon = NSImage(named: NSImage.applicationIconName) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        } else {
            SunsetArcGlyph()
        }
    }
}
