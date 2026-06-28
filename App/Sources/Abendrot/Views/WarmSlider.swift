import SwiftUI
import WarmthKit

// MARK: - WarmSlider

/// The signature warm-tinted "Softer ⟷ Warmer" strength slider. Strength is the
/// canonical control; the Kelvin readout lives above the track as one animated number. Wraps
/// the system `Slider` for accessibility + keyboard, restyled with the ember track.
struct WarmSlider: View {
    @Binding var strength: Double
    /// The view-model. (Slider click sounds were removed; kept for callers + any future view-model needs.)
    var model: AppModel
    var compact: Bool = false
    /// Header/accessibility label for this slider. Settings uses the same control for the Sunset peak.
    var headerTitle: String = "Warmth"
    /// When provided (the popover's main slider), the Warmth row shows this Kelvin readout inline,
    /// with an info tooltip. Other callers pass nil (they have their own readouts).
    var kelvin: Kelvin?
    /// Show the header row above the slider (the "Warmth" label + any Kelvin ticker). Onboarding passes
    /// false — its step already shows a big Kelvin readout + a "Set your warmth" heading, so the label is
    /// redundant — while keeping the full-size (non-compact) track + thumb.
    var showsHeader: Bool = true
    /// Show the draggable track. The popover hides it in Sunset mode because the clock owns warmth then,
    /// but still reuses the live Kelvin readout.
    var showsTrack: Bool = true
    /// Cozy mode active — the thumb crossfades into a glowing fireball and the warm end reads "Warmest"
    /// Set live by the onboarding warmth step; the popover/Settings sliders leave it false.
    var cozy: Bool = false
    /// Locked (read-only): Sunset mode sets warmth automatically by time of day, so the popover slider
    /// shows the live value but can't be dragged. The track keeps its full warm colour (the value must
    /// stay honest); a lock badge rides the thumb and a hover tooltip explains why. Editable elsewhere.
    var isLocked: Bool = false
    /// Reports the press/drag state outward (onboarding suppresses the blue-light % roll during a live
    /// drag but lets it animate on discrete changes like Cozy on→99). Default no-op for other callers.
    var onPressingChanged: (Bool) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// True while the thumb is being pressed/dragged — drives the Liquid-Glass "grab" feedback
    /// (a springy scale-up + brighter glow), mirroring the master toggle's press effect.
    @GestureState private var isPressing = false
    /// Drives the Kelvin info tooltip (shown on hover of the ⓘ).
    @State private var showKelvinInfo = false
    /// Last detent index the value crossed during a drag — drives the dial tick + thumb pop (one per
    /// detent), reset between presses. nil = not mid-manipulation.
    @State private var lastDetent: Int? = nil
    /// Local interaction value that owns the thumb while the user is dragging. Engine snapshots can trail
    /// behind rapid writes; this keeps the control from replaying those stale values under the pointer.
    @State private var interactionStrength: Double? = nil
    @State private var interactionReleaseTask: Task<Void, Never>? = nil
    /// Bumped on each detent crossing to fire the thumb's "pop" keyframe — the visual half of the click.
    @State private var popTrigger = 0

    private var trackHeight: CGFloat { compact ? 5 : 7 }
    private var thumbSize: CGFloat { compact ? 15 : 20 }
    /// Detents spanning the track — the notch count AND the click cadence, kept in one place so the
    /// marks you see line up exactly with the clicks you hear. More = finer/denser mini ticks.
    private let detentCount = 110
    /// Left edge of the visible slider: still soft, not true off. True off lives in the master toggle.
    private let minimumSoftStrength = 0.12

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 12) {
            if !compact && showsHeader {
                warmthTicker
            }

            if showsTrack {
                // "Softer" / "Warmer" flank the slider inline instead of sitting beneath it —
                // tighter, and the words read as the two ends of the track. `fixedSize` keeps the labels
                // intact so the slider takes the middle.
                HStack(spacing: 10) {
                    Text("Softer")
                        .font(Theme.Typography.ui(11.5))
                        .foregroundStyle(Theme.Color.textMuted)
                        .fixedSize()
                    gradientSlider
                    // Cozy unlocks the deepest end, so the warm label glows up to "Warmest" . Fixed
                    // width (fits "Warmest") so swapping the word never resizes the slider — only a crossfade.
                    Text(cozy ? "Warmest" : "Warmer")
                        .font(Theme.Typography.ui(11.5, weight: cozy ? .semibold : .regular))
                        .foregroundStyle(cozy ? Theme.Color.accentHighlight : Theme.Color.textMuted)
                        .contentTransition(.opacity)
                        .frame(width: 58, alignment: .leading)
                        .animation(Theme.Motion.warm(reduceMotion: reduceMotion), value: cozy)
                }
            }
        }
        .overlay(alignment: .topLeading) {
            if showKelvinInfo, kelvin != nil {
                kelvinTooltip
                    .offset(y: 88)
                    .transition(.scale(scale: 0.9, anchor: .topLeading).combined(with: .opacity))
            }
        }
        .zIndex(showKelvinInfo ? 10 : 0)
        .animation(.spring(response: 0.30, dampingFraction: 0.82), value: showKelvinInfo)
        // Surface the press/drag state so callers can gate animations (onboarding silences the
        // blue-light % roll during a live drag, but lets it animate on discrete changes like Cozy on→99).
        .onChange(of: isPressing) { _, pressing in onPressingChanged(pressing) }
    }

    // MARK: Warmth ticker (big "gas-price" Kelvin readout + info tooltip, above the slider)

    private var warmthTicker: some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionLabel(headerTitle)
            if let kelvin {
                let displayKelvin = interactionStrength
                    .map { WarmthLevel(strength: $0).kelvin(warmestPoint: model.state.warmestPoint) }
                    ?? kelvin
                // Big lit "price-board" numerals — tabular so the value ticks cleanly as you drag. The
                // "what is Kelvin?" ⓘ sits to the RIGHT of the K, with the readout it explains.
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(displayKelvin.displayValue.formatted(.number))
                        .font(Theme.Typography.serif(42))
                        .monospacedDigit()
                        .contentTransition(isPressing ? .identity : .numericText(value: Double(displayKelvin.displayValue)))
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
                .animation(isPressing ? nil : Theme.Motion.warm(reduceMotion: reduceMotion), value: displayKelvin.displayValue)
                .accessibilityElement()
                .accessibilityLabel("\(headerTitle) \(displayKelvin.displayValue) Kelvin")

                // Accent metric: estimated blue-light reduction (instant during a live drag).
                BlueLightReductionLabel(kelvin: displayKelvin, cozy: cozy, animated: !isPressing)
                    .padding(.top, 3)
            }
        }
    }

    private var kelvinInfoText: String { KelvinInfoButton.explanation }

    /// A solid card explaining the Kelvin readout, animated in on hover.
    private var kelvinTooltip: some View {
        AbendrotTooltipText(kelvinInfoText, width: 188)
    }

    // MARK: Custom gradient slider
    //
    // The system `Slider` can't wear a gradient, so the track is custom: the brand sunset ramp —
    // gold at "Softer", deep ember toward "Warmer" — under a glassy thumb. Tap-anywhere to set, and
    // ←/→ + VoiceOver (adjustable) keep keyboard/a11y parity with the control it replaces.
    private var gradientSlider: some View {
        GeometryReader { geo in
            let usable = max(geo.size.width - thumbSize, 1)
            let displayStrength = interactionStrength ?? strength
            let thumbX = CGFloat(thumbPosition(forStrength: displayStrength)) * usable

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
                    // Lock badge rides the thumb in Sunset mode (read-only). Dark plum reads on the
                    // cream glass thumb; crossfades in so toggling modes doesn't pop.
                    .overlay {
                        if isLocked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: thumbSize * 0.46, weight: .bold))
                                .foregroundStyle(Theme.Color.inkOnAccent)
                                .transition(.opacity)
                        }
                    }
                    .scaleEffect((isPressing && !isLocked) ? 1.12 : 1.0)
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
            .animation(reduceMotion ? nil : .smooth(duration: 0.16), value: displayStrength)
            .contentShape(Rectangle())
            // Visual "dial" feedback: a thumb pop each time the thumb crosses a notch. Driven here (not
            // via onChange) so a 1:1 drag and a glide-on-tap are told apart. (Slider click sounds removed.)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isPressing) { _, state, _ in state = true }
                    .onChanged { value in
                        guard !isLocked else { return }   // Sunset: read-only, warmth is set by time of day
                        let target = Double((value.location.x - thumbSize / 2) / usable).clamped01
                        let nextStrength = engineStrength(forPosition: target)
                        // Detent = which notch line the thumb has PASSED (floor, not round): the thumb pop
                        // fires the instant the thumb CENTER crosses a notch, exactly in line with the marks.
                        let toDetent = Int((target * Double(detentCount)).rounded(.down))
                        interactionReleaseTask?.cancel()
                        if hypot(value.translation.width, value.translation.height) > 2 {
                            var tx = Transaction(); tx.disablesAnimations = true   // drag: follow finger 1:1
                            withTransaction(tx) {
                                interactionStrength = nextStrength
                                strength = nextStrength
                            }
                            // Thumb pop per notch the thumb crosses (the visual detent — no sound).
                            if let last = lastDetent, toDetent != last, !reduceMotion { popTrigger &+= 1 }
                        } else {
                            // Tap / press-down: the thumb GLIDES to target via .smooth(0.16) above.
                            let fromDetent = Int((thumbPosition(forStrength: displayStrength) * Double(detentCount)).rounded(.down))
                            interactionStrength = nextStrength
                            strength = nextStrength
                            let movedNotches = lastDetent == nil && abs(toDetent - fromDetent) >= 1
                            if movedNotches, !reduceMotion { popTrigger &+= 1 }
                        }
                        lastDetent = toDetent
                    }
                    .onEnded { _ in
                        lastDetent = nil
                        settleInteractionStrength()
                    }
            )
        }
        .frame(height: max(thumbSize, 22))
        // Native hover tooltip explaining the lock (reinforces the popover's visible caption).
        .help(isLocked ? "In Sunset mode, Abendrot sets your warmth automatically by time of day. Adjust your maximum in Settings." : "")
        // No `.focusable()`: a menu-bar NSPopover doesn't do tab-traversal, so it only produced a
        // stray focus ring on click. VoiceOver still adjusts via the action below.
        .accessibilityElement()
        .accessibilityLabel(headerTitle)
        .accessibilityValue(isLocked
            ? "\(Int(((interactionStrength ?? strength).clamped01 * 100).rounded())) percent, locked — set automatically in Sunset mode"
            : "\(Int(((interactionStrength ?? strength).clamped01 * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            guard !isLocked else { return }   // Sunset: read-only
            switch direction {
            case .increment: nudge(0.05)
            case .decrement: nudge(-0.05)
            default: break
            }
        }
    }

    private func settleInteractionStrength() {
        guard interactionStrength != nil else { return }
        interactionReleaseTask?.cancel()
        interactionReleaseTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            interactionStrength = nil
            interactionReleaseTask = nil
        }
    }

    private func nudge(_ delta: Double) {
        // Nudge in THUMB-POSITION space so ←/→ steps feel even in Cozy too (identity when not cozy).
        let p = thumbPosition(forStrength: strength)
        strength = engineStrength(forPosition: (p + delta).clamped01)
    }

    // MARK: Cozy perceptual distribution
    //
    // In Cozy the warmest point drops below ~1900K, but blue light is already 0 by ~1900K — below that ONLY
    // green changes, slowly, so a mired-linear thumb spends most of its travel in a near-flat deep-red region
    // (~89% of the visible warming is done by the halfway point). To make equal travel ≈ equal VISIBLE change,
    // the thumb is distributed by perceptual progress (how far the white point has actually shifted) rather
    // than by mired. The engine's strength↔Kelvin curve is untouched — only where the thumb sits and how a
    // drag maps to strength changes, and only when `cozy`. Non-cozy stays a plain 1:1 slider.
    // ponytail: the green/blue weighting is a simple proxy — tune by eye.

    /// How far the white point has shifted toward the warmest point, 0 (neutral) … 1 (warmest). Blue is gone
    /// by ~1900K, so below that this is carried by green — exactly the band mired over-stretches. Green is
    /// weighted a little above blue (0.62/0.38) so the deep sub-1900K band gets more of the slider's travel
    /// (~32% vs ~26% at equal weight). ponytail: tune the 0.62 by eye for how spread the deep end feels.
    private func warmthProgress(_ k: Kelvin) -> Double {
        let g = rgbGain(for: k)
        return 1 - (0.62 * g.green + 0.38 * g.blue)
    }

    /// Thumb position (0…1) for an engine strength, with the soft floor folded into the scale.
    private func thumbPosition(forStrength s: Double) -> Double {
        guard cozy else { return sliderPosition(forStrength: s) }
        let wp = model.state.warmestPoint
        let floor = warmthProgress(WarmthLevel(strength: minimumSoftStrength).kelvin(warmestPoint: wp))
        let full = warmthProgress(wp)
        guard full > floor else { return sliderPosition(forStrength: s) }
        let k = WarmthLevel(strength: s.clamped01).kelvin(warmestPoint: wp)
        return ((warmthProgress(k) - floor) / (full - floor)).clamped01
    }

    /// Engine strength for a thumb position (0…1) — the inverse of `thumbPosition(forStrength:)`.
    private func engineStrength(forPosition p: Double) -> Double {
        guard cozy else { return strength(forSliderPosition: p) }
        let wp = model.state.warmestPoint
        let floor = warmthProgress(WarmthLevel(strength: minimumSoftStrength).kelvin(warmestPoint: wp))
        let full = warmthProgress(wp)
        guard full > floor else { return strength(forSliderPosition: p) }
        let target = floor + p.clamped01 * (full - floor)
        // Bisect the Kelvin whose progress matches (progress falls monotonically as K rises), then map that
        // Kelvin back to strength through the engine's own mired curve so the slider and engine never drift.
        var loK = Double(wp.value), hiK = Double(Kelvin.neutral.value)
        for _ in 0..<24 {
            let midK = (loK + hiK) / 2
            if warmthProgress(Kelvin(Int(midK.rounded()))) >= target { loK = midK } else { hiK = midK }
        }
        let k = Kelvin(Int(((loK + hiK) / 2).rounded()))
        let neutralMired = 1_000_000.0 / Double(Kelvin.neutral.value)
        let warmestMired = 1_000_000.0 / Double(wp.value)
        let mired = 1_000_000.0 / Double(k.value)
        guard warmestMired != neutralMired else { return 0 }
        return ((mired - neutralMired) / (warmestMired - neutralMired)).clamped01
    }

    private func sliderPosition(forStrength s: Double) -> Double {
        ((s.clamped01 - minimumSoftStrength) / (1 - minimumSoftStrength)).clamped01
    }

    private func strength(forSliderPosition p: Double) -> Double {
        minimumSoftStrength + p.clamped01 * (1 - minimumSoftStrength)
    }

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
    /// the user slides into the warmest . The glow extends past the thumb frame for presence.
    private func fireballThumb(pressed: Bool) -> some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [Theme.Color.accentHi, Theme.Color.accent, Theme.Color.accentDeep],
                    center: .init(x: 0.5, y: 0.34), startRadius: 0, endRadius: thumbSize * 0.78))
            Image(systemName: "flame.fill")
                .font(.system(size: thumbSize * 0.6, weight: .bold))
                // Match the Cozy-toggle flame (CozyModeControl): the dark ground ink, not a light gradient.
                .foregroundStyle(Theme.Color.groundIndigo)
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
