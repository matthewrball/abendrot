import SwiftUI
import AppKit
import AVFoundation
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
    /// The view-model. (Slider click sounds were removed; kept for callers + any future view-model needs.)
    var model: AppModel
    var compact: Bool = false
    /// When provided (the popover's main slider), the Warmth row shows this Kelvin readout inline,
    /// with an info tooltip. Other callers pass nil (they have their own readouts).
    var kelvin: Kelvin?
    /// Show the header row above the slider (the "Warmth" label + any Kelvin ticker). Onboarding passes
    /// false — its step already shows a big Kelvin readout + a "Set your warmth" heading, so the label is
    /// redundant — while keeping the full-size (non-compact) track + thumb.
    var showsHeader: Bool = true
    /// Cozy mode active — the thumb crossfades into a glowing fireball and the warm end reads "Warmest"
    /// (founder). Set live by the onboarding warmth step; the popover/Settings sliders leave it false.
    var cozy: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// True while the thumb is being pressed/dragged — drives the Liquid-Glass "grab" feedback
    /// (a springy scale-up + brighter glow), mirroring the master toggle's press effect.
    @GestureState private var isPressing = false
    /// Drives the Kelvin info tooltip (shown on hover of the ⓘ).
    @State private var showKelvinInfo = false
    /// Last detent index the value crossed during a drag — drives the dial tick + thumb pop (one per
    /// detent), reset between presses. nil = not mid-manipulation.
    @State private var lastDetent: Int? = nil
    /// Bumped on each detent crossing to fire the thumb's "pop" keyframe — the visual half of the click.
    @State private var popTrigger = 0

    private var trackHeight: CGFloat { compact ? 5 : 7 }
    private var thumbSize: CGFloat { compact ? 15 : 20 }
    /// Detents spanning the track — the notch count AND the click cadence, kept in one place so the
    /// marks you see line up exactly with the clicks you hear. More = finer/denser mini ticks.
    private let detentCount = 110

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 12) {
            if !compact && showsHeader {
                warmthTicker
            }

            // "Softer" / "Warmer" flank the slider inline (founder) instead of sitting beneath it —
            // tighter, and the words read as the two ends of the track. `fixedSize` keeps the labels
            // intact so the slider takes the middle.
            HStack(spacing: 10) {
                Text("Softer")
                    .font(Theme.Typography.ui(11.5))
                    .foregroundStyle(Theme.Color.textMuted)
                    .fixedSize()
                gradientSlider
                // Cozy unlocks the deepest end, so the warm label glows up to "Warmest" (founder). Fixed
                // width (fits "Warmest") so swapping the word never resizes the slider — only a crossfade.
                Text(cozy ? "Warmest" : "Warmer")
                    .font(Theme.Typography.ui(11.5, weight: cozy ? .semibold : .regular))
                    .foregroundStyle(cozy ? Theme.Color.accentHighlight : Theme.Color.textMuted)
                    .contentTransition(.opacity)
                    .frame(width: 58, alignment: .leading)
                    .animation(Theme.Motion.warm(reduceMotion: reduceMotion), value: cozy)
            }
        }
        .overlay(alignment: .topLeading) {
            if showKelvinInfo, kelvin != nil {
                kelvinTooltip
                    .offset(y: 88)
                    .transition(.scale(scale: 0.9, anchor: .topLeading).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .animation(.spring(response: 0.30, dampingFraction: 0.82), value: showKelvinInfo)
    }

    // MARK: Warmth ticker (big "gas-price" Kelvin readout + info tooltip, above the slider)

    private var warmthTicker: some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionLabel("Warmth")
            if let kelvin {
                // Big lit "price-board" numerals — tabular so the value ticks cleanly as you drag. The
                // "what is Kelvin?" ⓘ sits to the RIGHT of the K (founder), with the readout it explains.
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(kelvin.displayValue.formatted(.number))
                        .font(Theme.Typography.serif(42))
                        .monospacedDigit()
                        .contentTransition(isPressing ? .identity : .numericText(value: Double(kelvin.displayValue)))
                    Text("K")
                        .font(Theme.Typography.serif(23))
                        .foregroundStyle(Theme.Color.accentHighlight.opacity(0.7))
                    Image(systemName: "info.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(showKelvinInfo ? Theme.Color.accentHighlight : Theme.Color.textFaint)
                        .onHover { showKelvinInfo = $0 }
                        .accessibilityLabel("What is Kelvin?")
                        .accessibilityHint(kelvinInfoText)
                        .padding(.leading, 6)
                }
                .foregroundStyle(Theme.Color.accentHighlight)
                .shadow(color: Theme.Color.accent.opacity(0.35), radius: 12, y: 1)   // lit-sign glow
                // Instant while dragging (rapid changes otherwise glitch the digit-roll); smooth roll otherwise.
                .animation(isPressing ? nil : Theme.Motion.warm(reduceMotion: reduceMotion), value: kelvin.displayValue)
                .accessibilityElement()
                .accessibilityLabel("Warmth \(kelvin.displayValue) Kelvin")

                // Accent metric: estimated blue-light reduction (instant during a live drag).
                BlueLightReductionLabel(kelvin: kelvin, animated: !isPressing)
                    .padding(.top, 3)
            }
        }
    }

    private var kelvinInfoText: String { KelvinInfoButton.explanation }

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

                // Faint dial graduations — one notch per detent, brighter majors every 10 — over the
                // track so the thumb visibly clicks past them (it covers the notch it sits on). White at
                // low opacity reads on the dark groove ahead and as a soft highlight on the filled ramp.
                Canvas { ctx, size in
                    let cy = size.height / 2
                    for i in 0...detentCount {
                        let x = CGFloat(i) / CGFloat(detentCount) * usable + thumbSize / 2
                        let major = i % 10 == 0
                        let half = (trackHeight + (major ? 5 : 2)) / 2
                        var p = Path()
                        p.move(to: CGPoint(x: x, y: cy - half))
                        p.addLine(to: CGPoint(x: x, y: cy + half))
                        ctx.stroke(p, with: .color(.white.opacity(major ? 0.28 : 0.14)),
                                   lineWidth: major ? 1 : 0.6)
                    }
                }
                .allowsHitTesting(false)

                thumbView
                    .frame(width: thumbSize, height: thumbSize)
                    .scaleEffect(isPressing ? 1.12 : 1.0)
                    // Snappy, well-damped press feedback — settles fast so rapid clicks don't throb.
                    .animation(.spring(response: 0.2, dampingFraction: 0.86), value: isPressing)
                    // Visual "click": a quick scale pop on each detent (multiplies with the press scale
                    // above). Re-fires when `popTrigger` bumps; settles back to 1.0 between clicks.
                    .keyframeAnimator(initialValue: 1.0, trigger: popTrigger) { view, scale in
                        view.scaleEffect(scale)
                    } keyframes: { _ in
                        KeyframeTrack {
                            CubicKeyframe(1.12, duration: 0.05)
                            CubicKeyframe(1.0, duration: 0.13)
                        }
                    }
                    .offset(x: thumbX)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            // Thumb + fill glide to a tapped position; during an actual drag the per-update transaction
            // (below) disables this so the thumb tracks the finger 1:1 — no lag, no jitter.
            .animation(reduceMotion ? nil : .smooth(duration: 0.16), value: strength)
            .contentShape(Rectangle())
            // Visual "dial" feedback: a thumb pop each time the thumb crosses a notch. Driven here (not
            // via onChange) so a 1:1 drag and a glide-on-tap are told apart. (Slider click sounds removed.)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isPressing) { _, state, _ in state = true }
                    .onChanged { value in
                        let target = Double((value.location.x - thumbSize / 2) / usable).clamped01
                        // Detent = which notch line the thumb has PASSED (floor, not round): the thumb pop
                        // fires the instant the thumb CENTER crosses a notch, exactly in line with the marks.
                        let toDetent = Int((target * Double(detentCount)).rounded(.down))
                        if abs(value.translation.width) > 2 {
                            var tx = Transaction(); tx.disablesAnimations = true   // drag: follow finger 1:1
                            withTransaction(tx) { strength = target }
                            // Thumb pop per notch the thumb crosses (the visual detent — no sound).
                            if let last = lastDetent, toDetent != last, !reduceMotion { popTrigger &+= 1 }
                        } else {
                            // Tap / press-down: the thumb GLIDES to target via .smooth(0.16) above.
                            let fromDetent = Int((strength.clamped01 * Double(detentCount)).rounded(.down))
                            strength = target
                            let movedNotches = lastDetent == nil && abs(toDetent - fromDetent) >= 1
                            if movedNotches, !reduceMotion { popTrigger &+= 1 }
                        }
                        lastDetent = toDetent
                    }
                    .onEnded { _ in lastDetent = nil }
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

    /// The thumb: the glassy default, crossfading to the Cozy fireball when `cozy` is on.
    @ViewBuilder private var thumbView: some View {
        ZStack {
            glassThumb(pressed: isPressing).opacity(cozy ? 0 : 1)
            fireballThumb(pressed: isPressing).opacity(cozy ? 1 : 0)
        }
        .animation(Theme.Motion.warm(reduceMotion: reduceMotion), value: cozy)
    }

    /// The Cozy-mode thumb: a molten ember core behind a flame, wrapped in a warm bloom — the "fireball"
    /// the user slides into the warmest (founder). The glow extends past the thumb frame for presence.
    private func fireballThumb(pressed: Bool) -> some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [Theme.Color.accentHi, Theme.Color.accent, Theme.Color.accentDeep],
                    center: .init(x: 0.5, y: 0.34), startRadius: 0, endRadius: thumbSize * 0.78))
            Image(systemName: "flame.fill")
                .font(.system(size: thumbSize * 0.6, weight: .bold))
                .foregroundStyle(LinearGradient(colors: [.white, Theme.Color.accentHi],
                                                startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.18), radius: 0.5)
        }
        .overlay(Circle().strokeBorder(.white.opacity(pressed ? 0.95 : 0.7), lineWidth: 0.5))
        .shadow(color: Theme.Color.accent.opacity(0.75), radius: pressed ? 16 : 11)        // ember bloom
        .shadow(color: Theme.Color.accentDeep.opacity(0.55), radius: pressed ? 10 : 6, y: 1)
    }
}

private extension Double {
    var clamped01: Double { Swift.min(1, Swift.max(0, self)) }
}

// MARK: - KelvinInfoButton

/// A small ⓘ button that reveals a frosted "what is Kelvin?" explainer on hover — the popover Warmth
/// header's helper, made reusable so the onboarding warmth step can show it beside its title. The
/// tooltip opens down-and-left (trailing-anchored) so it stays on-screen even when the icon sits to the
/// right of a centered title.
struct KelvinInfoButton: View {
    static let explanation = "Kelvin is colour temperature — lower numbers are warmer and give off less blue light."
    @State private var show = false

    var body: some View {
        Image(systemName: "info.circle")
            .font(.system(size: 11))
            .foregroundStyle(show ? Theme.Color.accentHighlight : Theme.Color.textFaint)
            .onHover { show = $0 }
            .accessibilityLabel("What is Kelvin?")
            .accessibilityHint(Self.explanation)
            .overlay(alignment: .topTrailing) {
                if show {
                    Text(Self.explanation)
                        .font(Theme.Typography.ui(11))
                        .foregroundStyle(Theme.Color.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: 200, alignment: .leading)
                        .padding(11)
                        // OPAQUE ember surface (the app's frost-fallback gradient), not translucent glass:
                        // over the onboarding's transparent window + bright Kelvin text, .glassSurface(.frost)
                        // let the content behind bleed through and made the tooltip unreadable (founder).
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(LinearGradient(colors: [Theme.Color.frostTop, Theme.Color.frostBottom],
                                                     startPoint: .top, endPoint: .bottom))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Theme.Color.lineStrong, lineWidth: 0.5)
                        )
                        .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
                        .offset(y: 26)
                        .transition(.scale(scale: 0.9, anchor: .top).combined(with: .opacity))
                        .zIndex(2)
                }
            }
            .animation(.spring(response: 0.30, dampingFraction: 0.82), value: show)
    }
}

// MARK: - BlueLightReductionLabel
//
// The "≈X% less blue light" accent metric, shared by the Warmth ticker and onboarding. Sound basis:
// the EXACT attenuation the app applies to the blue channel vs the neutral 6500K white point —
// `rgbGain(for:).blue` is 1.0 at 6500K and falls toward 0 as it warms, so (1 − blueGain) is the
// fraction of blue-channel light removed — already ~1.0 by ~1900K (blue hits 0 there), so the everyday
// warmest setting AND all of Cozy sit at the cap. Capped at 0.99 to keep a 1% nod to residual blue
// (backlight / panel leakage) — never a claim of TOTAL elimination. An estimate of emitted blue vs the standard
// white point, NOT a measured melanopic/circadian dose (that needs the panel's spectrum, which we
// don't have).
struct BlueLightReductionLabel: View {
    let kelvin: Kelvin
    /// When false (e.g. live-dragging), the value updates instantly instead of rolling — rapid
    /// changes otherwise glitch the numericText transition.
    var animated: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var percent: Int {
        let reduction = min(0.99, max(0, 1 - rgbGain(for: kelvin).blue))
        return Int((reduction * 100).rounded())
    }

    private var infoText: String {
        "Estimated reduction in your display's blue-channel light versus its standard 6500 K white point. Warmer settings emit less short-wavelength (blue) light. This is an estimate from the colour shift applied — not a measured melanopic dose."
    }

    var body: some View {
        Text("≈\(percent)% less blue light")
            .font(Theme.Typography.ui(11.5, weight: .semibold))
            .foregroundStyle(Theme.Color.accentHighlight.opacity(0.85))
            .contentTransition(animated ? .numericText(value: Double(percent)) : .identity)
            .animation(animated ? Theme.Motion.warm(reduceMotion: reduceMotion) : nil, value: percent)
            .help(infoText)
            .accessibilityElement()
            .accessibilityLabel("Approximately \(percent) percent less blue light")
    }
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
                WarmSlider(strength: warmthBinding, model: model, compact: true)
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
    init(_ text: String) { self.text = text }
    var body: some View {
        // The app's one section-heading style: sentence case · 13pt semibold · secondary — native
        // macOS System Settings (founder). Route every popover + Settings section title through here so
        // they never drift apart again.
        Text(text)
            .font(Theme.Typography.ui(13, weight: .semibold))
            .foregroundStyle(Theme.Color.textMuted)
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

// MARK: - FrostBackground

/// The persistent "frosted ember" material backing the Settings and About windows (§21.3). Full-bleed
/// (cornerRadius 0 — the window supplies the rounded corners) and degrades to the ember SOLID under
/// Reduce Transparency via `GlassSurface`. Shared so the two windows can't drift.
struct FrostBackground: View {
    var body: some View {
        Color.clear
            .glassSurface(.frost, cornerRadius: 0)
            .ignoresSafeArea()
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
