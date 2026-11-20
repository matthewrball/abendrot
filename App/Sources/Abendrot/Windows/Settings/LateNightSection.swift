import SwiftUI
import WarmthKit

// MARK: - LateNightSection

/// Sunset mode's opt-in second stage, in General under Location: the evening still arrives with
/// the real sunset, then deepens by a bedtime the user picks and holds until sunrise.
///
/// The strip explains the night; the stepper and slider set it. Off by default, and off shows
/// only the one row.
struct LateNightSection: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Deepen late at night")
                        .font(Theme.Typography.ui(13))
                        .foregroundStyle(Theme.Color.textPrimary)
                    Text("Ease warmer before bed, then hold until sunrise.")
                        .font(Theme.Typography.ui(11.5))
                        .foregroundStyle(Theme.Color.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Toggle("Deepen late at night", isOn: Binding(
                    get: { model.lateNightEnabled },
                    set: { model.setLateNightEnabled($0) }
                ))
                .labelsHidden()
            }

            if model.lateNightEnabled {
                VStack(alignment: .leading, spacing: 14) {
                    NightAnchorsStrip(
                        timeline: model.nightTimeline,
                        clock: model.nightClock,
                        bedtimeMinutes: model.bedtimeMinutes,
                        eveningKelvin: model.eveningKelvin,
                        setBedtime: model.setBedtime(minutes:)
                    )

                    HStack {
                        Text("Bedtime").font(Theme.Typography.ui(13))
                        Spacer()
                        BedtimeStepper(
                            eveningMinutes: model.eveningBedtimeMinutes,
                            setBedtime: model.setBedtime(minutes:)
                        )
                    }

                    HStack {
                        Text("Ease in over").font(Theme.Typography.ui(13))
                        Spacer()
                        EaseStepper(
                            easeMinutes: model.lateNightEaseMinutes,
                            setEase: model.setLateNightEase(minutes:)
                        )
                    }

                    HStack {
                        Text("Switch to Cozy at bedtime").font(Theme.Typography.ui(13))
                        Spacer()
                        Toggle("Switch to Cozy at bedtime", isOn: Binding(
                            get: { model.lateNightCozy },
                            set: { model.setLateNightCozy($0) }
                        ))
                        .labelsHidden()
                    }

                    if !model.lateNightCozy {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("Late-night warmth").font(Theme.Typography.ui(13))
                                Spacer()
                                KelvinReadout(kelvin: model.lateNightKelvin, size: 17)
                            }
                            WarmSlider(
                                strength: Binding(
                                    get: { model.lateNightWarmth.strength },
                                    set: { model.setLateNightWarmth($0) }
                                ),
                                model: model,
                                compact: true,
                                headerTitle: "Late-night warmth"
                            )
                        }
                        .transition(.opacity)
                    }

                    Text(summary)
                        .font(Theme.Typography.ui(11.5))
                        .foregroundStyle(Theme.Color.textFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
        .animation(Theme.Motion.controlReveal(reduceMotion: reduceMotion), value: model.lateNightEnabled)
        .animation(Theme.Motion.warm(reduceMotion: reduceMotion), value: model.lateNightCozy)
    }

    /// The stage only ever warms: a late-night level cooler than the evening leaves the evening alone.
    private var deepens: Bool { model.lateNightKelvin < model.eveningKelvin }

    /// One line saying what tonight will do, for each kind of night that reads differently.
    private var summary: String {
        let night = model.nightTimeline
        func clock(_ date: Date) -> String { NightClock.text(date, on: model.nightClock) }
        func kelvin(_ kelvin: Kelvin) -> String { "\(kelvin.displayValue.formatted(.number))K" }
        let onThisClock = model.sunsetLocationKeepsAnotherClock ? " Times are on this Mac's clock." : ""

        guard let sunset = night.sunset else {
            return "The sun stays up tonight, so there is no evening to deepen."
        }
        // Only a night the clocks go back in can miss a bedtime: it is an hour short on the clock.
        guard let bedtime = night.bedtime, let from = night.deepeningStart, let to = night.deepeningEnd else {
            return "The clocks change tonight and skip this bedtime, so nothing changes tonight.\(onThisClock)"
        }
        let evening = kelvin(model.eveningKelvin)
        guard deepens else {
            return "Your evening is already \(evening), at least as warm as this, so nothing changes at bedtime."
        }
        if let sunrise = night.sunrise, sunrise <= from {
            return "The sun is up again before the ease into this bedtime begins, so nothing changes tonight.\(onThisClock)"
        }
        guard let held = night.heldKelvin else {
            return "The sun is up again before this bedtime's ease finishes, so tonight only gets part of the way to \(kelvin(model.lateNightKelvin)).\(onThisClock)"
        }
        let ease = "to \(kelvin(held)) between \(clock(from)) and \(clock(to))"
        guard sunset > night.start else {
            return "The sun stays down today: \(evening), easing \(ease) and holding until midday."
        }
        let release = night.sunrise.map { ", then back to day after sunrise at \(clock($0))" } ?? ""
        guard to <= bedtime else {
            return "Sunset is too close to this bedtime for the full ease, so it starts at sunset: easing \(ease)\(release).\(onThisClock)"
        }
        return "Tonight: \(evening) from sunset, easing \(ease)\(release).\(onThisClock)"
    }
}

// MARK: - BedtimeStepper

/// Bedtime in half-hour steps. The precise, keyboard-reachable way to set what the strip's
/// handle drags.
private struct BedtimeStepper: View {
    /// Bedtime counted from the evening's midnight, so the range is one unbroken span.
    let eveningMinutes: Int
    let setBedtime: (Int) -> Void

    var body: some View {
        MinusPlusStepper(
            text: clockText,
            valueLabel: "Bedtime \(clockText)",
            minusLabel: "Earlier bedtime",
            plusLabel: "Later bedtime",
            canDecrease: eveningMinutes > AppModel.bedtimeRange.lowerBound,
            canIncrease: eveningMinutes < AppModel.bedtimeRange.upperBound,
            decrease: { setBedtime(eveningMinutes - AppModel.bedtimeStep) },
            increase: { setBedtime(eveningMinutes + AppModel.bedtimeStep) }
        )
    }

    private var clockText: String { NightClock.text(minutes: eveningMinutes) }
}

// MARK: - EaseStepper

/// How long the ease before bedtime takes, stepping through the lengths the core allows.
private struct EaseStepper: View {
    let easeMinutes: Int
    let setEase: (Int) -> Void

    var body: some View {
        let shorter = LateNightStage.easeMinutes(stepping: easeMinutes, by: -1)
        let longer = LateNightStage.easeMinutes(stepping: easeMinutes, by: 1)
        MinusPlusStepper(
            text: LateNightStage.easeText(minutes: easeMinutes),
            valueLabel: "Ease in over \(LateNightStage.easeSpokenText(minutes: easeMinutes))",
            minusLabel: "Shorter ease",
            plusLabel: "Longer ease",
            canDecrease: shorter != easeMinutes,
            canIncrease: longer != easeMinutes,
            decrease: { setEase(shorter) },
            increase: { setEase(longer) }
        )
    }
}

// MARK: - MinusPlusStepper

/// The section's one stepper look: minus, a fixed-width value, plus. Bedtime and the ease
/// length share it so the two rows line up and read as one control family.
private struct MinusPlusStepper: View {
    let text: String
    let valueLabel: String
    let minusLabel: String
    let plusLabel: String
    let canDecrease: Bool
    let canIncrease: Bool
    let decrease: () -> Void
    let increase: () -> Void

    private let height: CGFloat = 28

    var body: some View {
        HStack(spacing: 0) {
            stepButton("minus", label: minusLabel, isEnabled: canDecrease, action: decrease)
            Rectangle().fill(Theme.Color.line).frame(width: 0.5)
            Text(text)
                .font(Theme.Typography.ui(12.5, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.Color.textPrimary)
                .lineLimit(1)
                .frame(width: 86)
                .accessibilityLabel(valueLabel)
            Rectangle().fill(Theme.Color.line).frame(width: 0.5)
            stepButton("plus", label: plusLabel, isEnabled: canIncrease, action: increase)
        }
        .frame(height: height)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.black.opacity(0.18))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Theme.Color.lineStrong, lineWidth: 0.5)
        )
    }

    private func stepButton(
        _ symbol: String, label: String, isEnabled: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.Color.textMuted)
                .frame(width: height, height: height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .accessibilityLabel(label)
    }
}
