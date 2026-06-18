import SwiftUI
import WarmthKit

// MARK: - OnboardingStep

private enum OnboardingStep: Int, CaseIterable {
    case notifications, warmth, schedule

    var index: Int { rawValue + 1 }
    static var total: Int { allCases.count }
}

// MARK: - OnboardingView
//
// "3 clicks to warmth" (plan §21.3, §4.6): permit notifications → set max warmth →
// confirm schedule. Three calm steps on glass; everything else lives in Settings.
// No account, no wall of permissions.
//
// Structural pass: the notification-permission request and the warmth selection are wired
// through `AppModel`; the actual `UNUserNotificationCenter` request is left as a TODO hook
// (it needs the bundled app + entitlement, not previewable here).
struct OnboardingView: View {
    @Bindable var model: AppModel
    var onFinish: () -> Void

    @State private var step: OnboardingStep = .notifications
    @State private var warmestStrength: Double = 0.7
    @State private var scheduleOption: ScheduleModeOption = .followSunset
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 18) {
            stepIndicator

            Group {
                switch step {
                case .notifications: notificationsStep
                case .warmth: warmthStep
                case .schedule: scheduleStep
                }
            }
            .transition(.opacity)
        }
        .padding(24)
        .frame(width: 320)
        .glassSurface(.popover)
        .animation(Theme.Motion.warm(reduceMotion: reduceMotion), value: step)
    }

    // MARK: Step indicator

    private var stepIndicator: some View {
        Text("Step \(step.index) of \(OnboardingStep.total)")
            .font(Theme.Typography.ui(11, weight: .semibold))
            .tracking(1.4)
            .foregroundStyle(Theme.Color.accent)
            .frame(maxWidth: .infinity)
    }

    // MARK: Step 1 — notifications

    private var notificationsStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "bell.badge")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.Color.accentHighlight)
                .frame(width: 54, height: 54)
                .background(Theme.Color.groundTwilight, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text("Stay gently informed")
                .font(Theme.Typography.serif(19))
                .foregroundStyle(Theme.Color.textPrimary)
            Text("A quiet nudge at sunset, nothing more. You can turn this off anytime.")
                .font(Theme.Typography.ui(12.5))
                .foregroundStyle(Theme.Color.textMuted)
                .multilineTextAlignment(.center)

            PrimaryButton(title: "Allow notifications") {
                // TODO(milestone): UNUserNotificationCenter.requestAuthorization here
                // (needs the bundled app + notification entitlement).
                advance()
            }
            Button("Skip") { advance() }
                .buttonStyle(.plain)
                .font(Theme.Typography.ui(12))
                .foregroundStyle(Theme.Color.textMuted)
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

            Text("\(previewKelvin) K")
                .font(Theme.Typography.serif(30))
                .monospacedDigit()
                .foregroundStyle(Theme.Color.accentHighlight)

            WarmSlider(strength: $warmestStrength, kelvin: nil)

            PrimaryButton(title: "Looks right") {
                // Set the user's chosen evening warmth STRENGTH (their nightly level), not the
                // warmest-point ceiling. The ceiling stays at the research-backed everyday max
                // (1900K); this slider picks how warm within that range, and `previewKelvin` is
                // computed against exactly that 1900K range so the preview matches what's applied.
                // (Power users can later push the ceiling below 1900K via Settings → Advanced.)
                model.setGlobalWarmth(warmestStrength)
                advance()
            }
        }
    }

    // MARK: Step 3 — confirm schedule

    private var scheduleStep: some View {
        VStack(spacing: 14) {
            Text("When should it warm?")
                .font(Theme.Typography.serif(19))
                .foregroundStyle(Theme.Color.textPrimary)
            Text("We follow your local sunset and sunrise. Change it anytime in Settings.")
                .font(Theme.Typography.ui(12.5))
                .foregroundStyle(Theme.Color.textMuted)
                .multilineTextAlignment(.center)

            ModeControl(selection: $scheduleOption) { _ in }

            PrimaryButton(title: "Soften into the evening") {
                model.setScheduleMode(scheduleOption.toScheduleMode())
                model.setEnabled(true)
                onFinish()
            }
        }
    }

    // MARK: Helpers

    /// Map the onboarding strength to a Kelvin preview against a neutral warmest range.
    private var previewKelvin: Int {
        WarmthLevel(strength: warmestStrength).kelvin(warmestPoint: Kelvin(1900)).value
    }

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
                .foregroundStyle(Theme.Color.groundIndigo)
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
