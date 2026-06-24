import SwiftUI
import WarmthKit

/// "Cozy mode" — the maximum-warmth control, reframed as one delightful toggle (no granular slider,
/// founder). Off, the warmest the General slider reaches is 1900K — where blue is already fully removed.
/// On, it unlocks the deepest candle & ember glow: the engine `warmestPoint` drops to `warmestSupported`
/// (~500K), the card ignites into the sunset gradient, and the screen eases warmer immediately. Below
/// 1900K is a real but minimal extra circadian reduction at a real legibility cost — see
/// docs/research/max-warmth-circadian-research.md (Brown et al. 2022; CIE S 026:2018).
struct CozyModeControl: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Hide the "Maximum warmth" section header (onboarding shows the card bare, under its own title).
    var showsSectionLabel: Bool = true
    /// Hide the when-on science caption (onboarding keeps it compact; the detail lives in Settings).
    var showsExplanation: Bool = true
    /// Onboarding behaviour: turning Cozy ON unlocks the deepest ember AND runs the slider all the way to
    /// the warmest, so the screen blooms to the maximum (rather than holding a mid-slider spot); OFF restores
    /// the everyday 1900K ceiling. (Settings keeps the richer "preserve current warmth, unlock headroom".)
    var enablesAtWarmest: Bool = false

    /// Derived from the actual warmest point so the toggle can never disagree with the engine.
    private var isCozy: Bool { model.state.warmestPoint.value < Kelvin.everydayWarmest.value }
    private var cardShape: RoundedRectangle { RoundedRectangle(cornerRadius: 16, style: .continuous) }

    /// The §13-safe note with both citations as tappable links. Built as an AttributedString so the body
    /// stays faint while the links read as links — accent-coloured + underlined + clickable. (A blanket
    /// `.foregroundStyle` on a markdown Text flattens the link colour, so they didn't look tappable.)
    private var scienceNote: AttributedString {
        let md = "Below ~1900 K blue light is already gone, so going warmer mainly removes green — a deeper, candle-like glow that's lovely at night but harder to read, with little extra circadian benefit. ([Brown et al. 2022](https://journals.plos.org/plosbiology/article?id=10.1371/journal.pbio.3001571); [CIE S 026](https://cie.co.at/publications/cie-system-metrology-optical-radiation-iprgc-influenced-responses-light-0).)"
        var note = (try? AttributedString(markdown: md)) ?? AttributedString(md)
        note.foregroundColor = Theme.Color.textFaint
        for run in note.runs where run.link != nil {
            note[run.range].foregroundColor = Theme.Color.accent
            note[run.range].underlineStyle = .single
        }
        return note
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsSectionLabel {
                SectionLabel("Maximum warmth")
            }

            Button(action: toggle) { card }
                .buttonStyle(.plain)
                .accessibilityElement()
                .accessibilityLabel("Cozy mode")
                .accessibilityValue(isCozy ? "On" : "Off")
                .accessibilityHint("Unlocks the warmest candle and ember glow, below 1900 Kelvin.")
                .accessibilityAddTraits(.isButton)

            if isCozy && showsExplanation {
                Text(scienceNote)
                    .font(Theme.Typography.ui(11))
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .animation(Theme.Motion.warm(reduceMotion: reduceMotion), value: isCozy)
    }

    private var card: some View {
        HStack(spacing: 14) {
            SparkingFlameIcon(isCozy: isCozy)

            VStack(alignment: .leading, spacing: 3) {
                Text("Cozy mode")
                    .font(Theme.Typography.ui(14, weight: .semibold))
                    .foregroundStyle(isCozy ? Theme.Color.groundIndigo : Theme.Color.textPrimary)
                Text("The warmest setting.")
                    .font(Theme.Typography.ui(11.5))
                    .foregroundStyle(isCozy ? Theme.Color.groundIndigo.opacity(0.82) : Theme.Color.textMuted)
                    .fixedSize(horizontal: true, vertical: true)
            }

            Spacer(minLength: 8)

            // Display-only switch — the whole card is the hit target; it just mirrors + animates state.
            Toggle("", isOn: .constant(isCozy))
                .toggleStyle(.switch)
                .tint(isCozy ? Theme.Color.groundIndigo : Theme.Color.accent)
                .labelsHidden()
                .allowsHitTesting(false)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                if isCozy {
                    cardShape.fill(Theme.Gradient.sunset)
                    cardShape
                        .fill(LinearGradient(colors: [.white.opacity(0.32), .white.opacity(0.04), .clear],
                                             startPoint: .top, endPoint: .bottom))
                        .blendMode(.softLight)
                } else {
                    cardShape.fill(Color.white.opacity(0.04))
                }
                cardShape.strokeBorder(isCozy ? Color.white.opacity(0.18) : Theme.Color.lineStrong, lineWidth: 0.5)
            }
        }
        .shadow(color: isCozy ? Theme.Color.accentDeep.opacity(0.38) : .clear, radius: 8, y: 2)
        .shadow(color: isCozy ? Theme.Color.accent.opacity(0.28) : .clear, radius: 18)   // ember glow
        .contentShape(cardShape)
    }

    private func toggle() {
        if enablesAtWarmest {
            // Onboarding: Cozy means "give me the coziest." Turning ON unlocks the deepest ember AND runs the
            // slider all the way to the warmest, so the screen blooms to the maximum instead of holding a
            // mid-slider spot; OFF restores the everyday 1900K ceiling. Animated so the thumb glides to the end.
            model.playCozyFireSound(starting: !isCozy)
            withAnimation(Theme.Motion.warm(reduceMotion: reduceMotion)) {
                if isCozy {
                    model.setWarmestPoint(Kelvin.everydayWarmest)
                } else {
                    model.setWarmestPoint(Kelvin.warmestSupported)
                    model.setGlobalWarmth(1.0)
                }
            }
            return
        }
        // Settings: the richer behaviour — preserve the user's warmth and just unlock headroom, animated.
        // The actual ceiling + warmth move lives in `model.setCozy`, the ONE path the CLI shares, so the
        // card, onboarding's "Looks right", and `abendrot cozy on|off` can never drift.
        withAnimation(Theme.Motion.warm(reduceMotion: reduceMotion)) {
            model.setCozy(!isCozy)
        }
    }
}

private struct SparkingFlameIcon: View {
    var isCozy: Bool
    
    @State private var sparkTrigger = 0
    
    struct Spark: Identifiable {
        let id: Int
        let angle: Double
        let distance: Double
        let delay: Double
    }
    
    let sparks: [Spark] = [
        Spark(id: 0, angle: 105, distance: 16, delay: 0.0),
        Spark(id: 1, angle: 90, distance: 22, delay: 0.05),
        Spark(id: 2, angle: 75, distance: 16, delay: 0.1)
    ]
    
    var body: some View {
        ZStack {
            // Sparks shooting out
            ForEach(sparks) { spark in
                Circle()
                    .fill(Theme.Color.accentHighlight)
                    .frame(width: 3.5, height: 3.5)
                    .keyframeAnimator(initialValue: SparkAnimState(), trigger: sparkTrigger) { content, value in
                        content
                            .offset(x: value.travel * cos(spark.angle * .pi / 180),
                                    y: -value.travel * sin(spark.angle * .pi / 180))
                            .scaleEffect(value.scale)
                            .opacity(value.opacity)
                            .blur(radius: value.blur)
                    } keyframes: { _ in
                        KeyframeTrack(\.travel) {
                            CubicKeyframe(0, duration: spark.delay)
                            SpringKeyframe(spark.distance, duration: 0.5, spring: .smooth)
                        }
                        KeyframeTrack(\.scale) {
                            CubicKeyframe(0, duration: spark.delay)
                            CubicKeyframe(1.2, duration: 0.1)
                            CubicKeyframe(0.0, duration: 0.4)
                        }
                        KeyframeTrack(\.opacity) {
                            CubicKeyframe(0, duration: spark.delay)
                            CubicKeyframe(1.0, duration: 0.1)
                            CubicKeyframe(0.0, duration: 0.4)
                        }
                        KeyframeTrack(\.blur) {
                            CubicKeyframe(0, duration: spark.delay)
                            CubicKeyframe(0, duration: 0.2)
                            CubicKeyframe(2.0, duration: 0.3)
                        }
                    }
            }
            
            // The Flame itself
            Image(systemName: isCozy ? "flame.fill" : "flame")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(isCozy ? Theme.Color.groundIndigo : Theme.Color.textMuted)
                .contentTransition(.symbolEffect(.replace))
                .keyframeAnimator(initialValue: FlameAnimState(scale: isCozy ? 1 : 0.9, glow: isCozy ? 0.55 : 0), trigger: sparkTrigger) { content, value in
                    content
                        .scaleEffect(value.scale)
                        .shadow(color: Theme.Color.accentHighlight.opacity(value.glow), radius: value.glow * 15)
                } keyframes: { _ in
                    KeyframeTrack(\.scale) {
                        if isCozy {
                            SpringKeyframe(1.15, duration: 0.2, spring: .smooth)
                            SpringKeyframe(1.0, duration: 0.4, spring: .smooth)
                        } else {
                            SpringKeyframe(0.9, duration: 0.3, spring: .smooth)
                        }
                    }
                    KeyframeTrack(\.glow) {
                        if isCozy {
                            CubicKeyframe(1.0, duration: 0.2)
                            CubicKeyframe(0.55, duration: 0.5)
                        } else {
                            CubicKeyframe(0.0, duration: 0.3)
                        }
                    }
                }
        }
        .frame(width: 28)
        .onChange(of: isCozy) { _, new in
            if new {
                sparkTrigger += 1
            }
        }
    }
}

private struct SparkAnimState {
    var travel: Double = 0
    var scale: Double = 0
    var opacity: Double = 0
    var blur: Double = 0
}

private struct FlameAnimState {
    var scale: Double = 0.9
    var glow: Double = 0.0
}
