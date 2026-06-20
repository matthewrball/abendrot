import SwiftUI
import WarmthKit

// MARK: - OnboardingStep

private enum OnboardingStep: Int, CaseIterable {
    case welcome, warmth, schedule, allSet

    /// The numbered position shown in "Step X of 3" — nil for the closing `allSet` screen, which is a
    /// completion confirmation, not a numbered setup step (keeps the "3 clicks to warmth" framing).
    var numberedIndex: Int? {
        switch self {
        case .welcome: return 1
        case .warmth: return 2
        case .schedule: return 3
        case .allSet: return nil
        }
    }
    static let numberedTotal = 3
}

// MARK: - OnboardingView
//
// "3 clicks to warmth" (plan §21.3, §4.6): welcome → set your warmth → confirm the schedule — three
// numbered setup steps, then a brief UNNUMBERED "you're all set" confirmation that carries the privacy
// reassurance. Calm glass; everything else lives in Settings. The app needs no permissions, so onboarding
// asks for none — it just orients the user (a menu-bar agent launches invisibly) and lands them on warmth.
// The schedule step enables warming (the "to warmth" payoff) and advances to the closing screen.
struct OnboardingView: View {
    @Bindable var model: AppModel
    var onFinish: () -> Void

    @State private var step: OnboardingStep = .welcome
    @State private var scheduleOption: ScheduleModeOption = .followSunset
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 18) {
            stepIndicator

            Group {
                switch step {
                case .welcome: welcomeStep
                case .warmth: warmthStep
                case .schedule: scheduleStep
                case .allSet: allSetStep
                }
            }
            .frame(maxHeight: .infinity)   // step content fills + centers, so the card height is stable
            .transition(.opacity)
        }
        .padding(24)
        .frame(width: 320, height: 520)    // fixed card: steps don't resize the window (tall enough for
                                           // step 3's science card + location picker). The picker dropdown
                                           // floats, so it needn't fit in-flow. Mirror this height in
                                           // OnboardingWindowController's contentRect.
        .glassSurface(.popover)
        .animation(Theme.Motion.warm(reduceMotion: reduceMotion), value: step)
    }

    // MARK: Step indicator

    @ViewBuilder
    private var stepIndicator: some View {
        if let n = step.numberedIndex {
            Text("Step \(n) of \(OnboardingStep.numberedTotal)")
                .font(Theme.Typography.ui(11, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(Theme.Color.accent)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: Step 1 — welcome / orientation
    //
    // A menu-bar agent launches with no Dock icon and no window, so a brand-new user can miss that
    // anything happened. This first step is that "here I am" moment: the icon, what Abendrot does in
    // one line, and where it lives. No permission prompt — the app needs none — just an invitation.
    private var welcomeStep: some View {
        VStack(spacing: 14) {
            AppIconView()
                .frame(width: 60, height: 60)

            Text("Welcome to Abendrot")
                .font(Theme.Typography.serif(20))
                .foregroundStyle(Theme.Color.textPrimary)
            Text("Abendrot warms your screen as the day winds down — on every display, built-in and external. It lives quietly in your menu bar: no dock icon, no account.")
                .font(Theme.Typography.ui(12.5))
                .foregroundStyle(Theme.Color.textMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            PrimaryButton(title: "Get started") { advance() }
        }
    }

    // MARK: Step 2 — max warmth

    private var warmthStep: some View {
        VStack(spacing: 14) {
            Text("Set your warmest")
                .font(Theme.Typography.serif(19))
                .foregroundStyle(Theme.Color.textPrimary)
            Text("Drag until your screen feels like candlelight. This is your night maximum.")
                .font(Theme.Typography.ui(12.5))
                .foregroundStyle(Theme.Color.textMuted)
                .multilineTextAlignment(.center)

            // Live applied Kelvin — the slider drives the engine directly (below), so this number and
            // the screen warm together as you drag, instead of only committing on "Looks right".
            Text("\(model.globalKelvin.displayValue) K")
                .font(Theme.Typography.serif(30))
                .monospacedDigit()
                .foregroundStyle(Theme.Color.accentHighlight)

            // Same science-backed accent metric as the popover ticker (instant updates here).
            BlueLightReductionLabel(kelvin: model.globalKelvin, animated: false)

            // Bind STRAIGHT to the engine so dragging warms the screen live (mirrors the popover's global
            // slider). Sets the nightly warmth STRENGTH within the warmest-point ceiling (default 1900K);
            // power users can push the ceiling lower later via Settings → Advanced.
            WarmSlider(strength: Binding(
                get: { model.state.globalWarmth.strength },
                set: { model.setGlobalWarmth($0) }
            ))

            PrimaryButton(title: "Looks right") { advance() }   // warmth is already applied live
        }
        // The live preview is only visible while warming is ON; a fresh install starts disabled, so turn
        // it on here — now WITH the warm-on confirmation tone (gated by the sound pref) — when the user reaches this
        // step. (NOTE: in daytime Sunset mode the schedule still gates the screen to neutral; the live
        // preview shows in the evening/at night or in Always-on mode.)
        .onAppear { model.setEnabled(true, userInitiated: true) }
    }

    // MARK: Step 3 — confirm schedule

    private var scheduleStep: some View {
        VStack(spacing: 13) {
            Text("When should it warm?")
                .font(Theme.Typography.serif(19))
                .foregroundStyle(Theme.Color.textPrimary)

            // Tick the mode tone on each toggle (same as the popover), gated by the sound pref.
            ModeControl(selection: $scheduleOption) { option in model.playSoftModeTone(option.toScheduleMode()) }

            if scheduleOption == .followSunset {
                VStack(alignment: .leading, spacing: 11) {
                    sunsetScienceCard
                    // Sunset needs a location to time the sunset. Reuse the Settings liquid-glass city
                    // picker — "Auto (from time zone)" is pre-selected, so the user can simply continue.
                    VStack(alignment: .leading, spacing: 6) {
                        CityAutocomplete(model: model, opensUpward: true)
                        Text(sunsetReadout)
                            .font(Theme.Typography.ui(11))
                            .foregroundStyle(Theme.Color.textFaint)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
            } else {
                Text("Warmth stays on around the clock.")
                    .font(Theme.Typography.ui(12.5))
                    .foregroundStyle(Theme.Color.textMuted)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }

            PrimaryButton(title: scheduleOption == .followSunset ? "Soften into the evening" : "Start warming") {
                model.setScheduleMode(scheduleOption.toScheduleMode(), userInitiated: false)   // toggle already ticked
                model.setEnabled(true, userInitiated: false)
                advance()   // → the closing "You're all set" screen
            }
        }
        .animation(Theme.Motion.warm(reduceMotion: reduceMotion), value: scheduleOption)
    }

    // MARK: Step 4 — closing confirmation (not numbered) — privacy reassurance lives here now
    private var allSetStep: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(Theme.Color.accentHighlight)
                .shadow(color: Theme.Color.accentPress.opacity(0.3), radius: 14, y: 5)
                .accessibilityHidden(true)

            Text("You’re all set")
                .font(Theme.Typography.serif(22))
                .foregroundStyle(Theme.Color.textPrimary)
            Text("Abendrot is now configured. Adjust anything anytime from the menu bar.")
                .font(Theme.Typography.ui(12.5))
                .foregroundStyle(Theme.Color.textMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            privacyNote
                .padding(.top, 6)

            PrimaryButton(title: "Done") { onFinish() }
                .padding(.top, 2)
        }
    }

    // §13-safe science nudge toward Sunset. Cites the expert EVENING-LIGHT consensus (an input/habit
    // recommendation, NOT a sleep-outcome promise) and states only what the engine does (eases off blue in
    // the evening) — the approved "supports healthy evening light habits" framing. NO medical/sleep claim,
    // no "improves sleep". Wording from docs/marketing/evidence-base.md claim #5 (Brown et al. 2022).
    private var sunsetScienceCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Why we recommend Sunset", systemImage: "moon.stars.fill")
                .font(Theme.Typography.ui(11.5, weight: .semibold))
                .foregroundStyle(Theme.Color.accentHighlight)
            Text("An international expert consensus recommends keeping evening light low in blue in the hours before bed. Sunset eases your screen off blue automatically as evening falls.")
                .font(Theme.Typography.ui(11))
                .foregroundStyle(Theme.Color.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            Link(destination: URL(string: "https://doi.org/10.1371/journal.pbio.3001571")!) {
                HStack(spacing: 4) {
                    Text("Brown et al. · PLoS Biology · 2022")
                    Image(systemName: "arrow.up.right").font(.system(size: 8, weight: .semibold)).accessibilityHidden(true)
                }
                .font(Theme.Typography.ui(10, weight: .medium))
                .foregroundStyle(Theme.Color.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(.frost, cornerRadius: Theme.Radius.control)
    }

    // Brief, beautiful privacy reassurance — the closing note. Reuses the Privacy settings page's
    // checkmark.shield icon. A general promise (not just location), since it's the parting word.
    private var privacyNote: some View {
        VStack(spacing: 9) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(Theme.Color.accentHighlight)
                .accessibilityHidden(true)
            Text("Private by default. Nothing about you or your displays ever leaves this Mac — no account, no tracking, no telemetry.")
                .font(Theme.Typography.ui(11))
                .foregroundStyle(Theme.Color.textMuted)
                .multilineTextAlignment(.center)
                .lineSpacing(2.5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .glassSurface(.frost, cornerRadius: Theme.Radius.card)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.Color.line.opacity(0.6), lineWidth: 0.5)
        )
    }

    /// Live "Today's sunset ≈ h:mm a" for the chosen (or auto) location — same logic as Settings →
    /// Schedule, so the picked city feels real. Zero permission, zero network (time-zone coordinates).
    private var sunsetReadout: String {
        let coordinate = model.userCoordinate ?? TimeZoneCoordinates.current()
        guard let sunset = ScheduleResolver.sunsetTime(forCoordinate: coordinate, on: Date()) else {
            return "Today's sunset: —"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.timeZone = .current
        return "Today's sunset ≈ \(formatter.string(from: sunset))"
    }

    // MARK: Helpers

    private func advance() {
        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else {
            onFinish()
            return
        }
        step = next
    }
}

// MARK: - PrimaryButton

/// The warm primary CTA used across onboarding (and reusable elsewhere).
struct PrimaryButton: View {
    let title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Typography.ui(13, weight: .semibold))
                .foregroundStyle(Theme.Color.inkOnAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    LinearGradient(
                        colors: [Theme.Color.accentHighlight, Theme.Color.accent],
                        startPoint: .top, endPoint: .bottom
                    ),
                    in: RoundedRectangle(cornerRadius: Theme.Radius.control - 1, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview("Onboarding") {
    OnboardingView(model: AppModel(previewState: MockWarmthState.idleSingleDisplay)) {}
        .padding(40)
        .background(Theme.Color.groundIndigo)
}
