import SwiftUI
import WarmthKit

// MARK: - MaximumWarmthControl
//
// A SEPARATE "Maximum warmth" ticker for Settings → General, shown in Sunset — where the main warmth
// slider is the live, clock-LOCKED current value. This control represents (and lets you drag) your
// evening PEAK: how warm the screen climbs to at its warmest, i.e. `globalWarmth` / `globalKelvin`. It is
// exactly what the popover's "Change your maximum in Settings" points at. The main slider is left
// untouched; this is an addition, not a rework.
//
// Its own slim track sits on an ABSOLUTE perceptual-warmth axis (neutral → the deepest supported ember).
// Not raw mired — a mired-linear absolute axis crushes the everyday band into the cool corner (1900K at
// ~20%); the same green/blue progress weighting the popover slider uses in Cozy puts 1900K near ~⅔ and
// 500K at the end. The band past the Cozy ceiling (`warmestPoint`) is dimmed "off-limits"; Cozy unlocks it.
struct MaximumWarmthControl: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var dragging = false

    private let neutral = Kelvin.neutral
    private let deepest = Kelvin.warmestSupported

    private var isCozy: Bool { model.state.warmestPoint.value < Kelvin.everydayWarmest.value }
    /// Your evening peak — the warmth the Sunset ramp climbs to at full night.
    private var peak: Kelvin { model.globalKelvin }
    /// The Cozy ceiling — the deepest the peak may travel until Cozy unlocks the rest.
    private var ceiling: Kelvin { model.state.warmestPoint }

    private let trackHeight: CGFloat = 7
    private let markerWidth: CGFloat = 9
    private let markerHeight: CGFloat = 26

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel("Maximum warmth")
                Spacer()
                Text("\(peak.displayValue) K")
                    .font(Theme.Typography.ui(13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Color.accentHighlight)
                    .contentTransition(dragging ? .identity : .numericText(value: Double(peak.displayValue)))
                    .animation(dragging ? nil : Theme.Motion.warm(reduceMotion: reduceMotion), value: peak.displayValue)
            }

            HStack(spacing: 10) {
                Text("Softer")
                    .font(Theme.Typography.ui(11.5)).foregroundStyle(Theme.Color.textMuted).fixedSize()
                track
                Text("Warmest")
                    .font(Theme.Typography.ui(11.5)).foregroundStyle(Theme.Color.textMuted).fixedSize()
            }
            .frame(height: max(markerHeight, 24))

            Text("How warm your screen gets at its warmest each evening. Drag the marker to set your peak.")
                .font(Theme.Typography.ui(11.5))
                .foregroundStyle(Theme.Color.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement()
        .accessibilityLabel("Maximum warmth")
        .accessibilityValue("\(peak.displayValue) Kelvin")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: nudge(+1)   // cooler / less warm
            case .decrement: nudge(-1)   // warmer
            default: break
            }
        }
    }

    // MARK: The ticker track

    private var track: some View {
        GeometryReader { geo in
            let usable = max(geo.size.width - markerWidth, 1)
            let markerX = pos(peak) * usable
            let ceilingX = pos(ceiling) * usable
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Theme.Color.line.opacity(0.55))
                    .frame(height: trackHeight)

                Capsule(style: .continuous)
                    .fill(Theme.Gradient.sunsetHorizontal)
                    .frame(height: trackHeight)
                    .mask(alignment: .leading) {
                        Capsule(style: .continuous)
                            .frame(width: markerX + markerWidth / 2, height: trackHeight)
                    }

                // Off-limits band past the Cozy ceiling — dimmed + hatched. Hidden once Cozy opens the full range.
                if pos(ceiling) < 0.999 {
                    offLimitsBand(from: ceilingX + markerWidth / 2, width: usable - ceilingX)
                }

                marker
                    .scaleEffect(dragging ? 1.08 : 1.0)
                    .animation(.spring(response: 0.2, dampingFraction: 0.86), value: dragging)
                    .offset(x: markerX)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .animation(reduceMotion ? nil : .smooth(duration: 0.16), value: markerX)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($dragging) { _, state, _ in state = true }
                    .onChanged { value in
                        let p = Double((value.location.x - markerWidth / 2) / usable)
                        var tx = Transaction(); tx.disablesAnimations = true   // follow the finger 1:1
                        withTransaction(tx) { model.setGlobalWarmthToKelvin(kelvin(atPos: p)) }
                    }
            )
        }
    }

    /// The draggable maximum "ticker": a slim ember bar — sunset gradient, specular sheen, hairline rim,
    /// soft ember glow — taller than the track so it reads as a distinct marker.
    private var marker: some View {
        RoundedRectangle(cornerRadius: markerWidth / 2, style: .continuous)
            .fill(Theme.Gradient.sunset)
            .overlay(
                RoundedRectangle(cornerRadius: markerWidth / 2, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.06), .clear],
                                         startPoint: .top, endPoint: .bottom))
                    .blendMode(.softLight)
            )
            .overlay(RoundedRectangle(cornerRadius: markerWidth / 2, style: .continuous)
                .strokeBorder(.white.opacity(dragging ? 0.95 : 0.7), lineWidth: 0.5))
            .frame(width: markerWidth, height: markerHeight)
            .shadow(color: Theme.Color.accentDeep.opacity(0.45), radius: 3, y: 1)
            .shadow(color: Theme.Color.accent.opacity(dragging ? 0.6 : 0.4), radius: dragging ? 12 : 7)
    }

    private func offLimitsBand(from x: CGFloat, width: CGFloat) -> some View {
        Capsule(style: .continuous)
            .fill(Theme.Color.line.opacity(0.28))
            .overlay(
                Canvas { ctx, size in
                    var p = Path()
                    var start: CGFloat = -size.height
                    while start < size.width {
                        p.move(to: CGPoint(x: start, y: size.height))
                        p.addLine(to: CGPoint(x: start + size.height, y: 0))
                        start += 6
                    }
                    ctx.stroke(p, with: .color(.white.opacity(0.10)), lineWidth: 0.7)
                }
                .mask(Capsule(style: .continuous))
            )
            .frame(width: max(width, 0), height: trackHeight)
            .offset(x: x)
            .allowsHitTesting(false)
            .transition(.opacity)
    }

    // MARK: Perceptual absolute-warmth axis (reuses the Cozy progress weighting)

    private func progress(_ k: Kelvin) -> Double {
        let g = rgbGain(for: k)
        return 1 - (0.62 * g.green + 0.38 * g.blue)
    }
    private var fullProgress: Double { max(progress(deepest), 0.0001) }

    /// Track position 0…1 for a Kelvin (0 = neutral/Softer, 1 = deepest/Warmest).
    private func pos(_ k: Kelvin) -> Double { (progress(k) / fullProgress).clamped01 }

    /// The Kelvin at a track position — the inverse of `pos`, by bisection (progress is monotonic in K).
    private func kelvin(atPos p: Double) -> Kelvin {
        let target = p.clamped01 * fullProgress
        var loK = Double(deepest.value), hiK = Double(neutral.value)
        for _ in 0..<24 {
            let mid = (loK + hiK) / 2
            if progress(Kelvin(Int(mid.rounded()))) >= target { loK = mid } else { hiK = mid }
        }
        return Kelvin(Int(((loK + hiK) / 2).rounded()))
    }

    /// Keyboard / VoiceOver nudge in track-position space (one ~5% step), warmer or cooler.
    private func nudge(_ sign: Int) {
        let p = (pos(peak) + Double(sign) * 0.05).clamped01
        model.setGlobalWarmthToKelvin(kelvin(atPos: p))
    }
}

private extension Double {
    var clamped01: Double { Swift.min(1, Swift.max(0, self)) }
}
