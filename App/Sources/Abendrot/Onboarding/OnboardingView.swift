import SwiftUI
import AppKit
import WarmthKit

// MARK: - OnboardingStep

private enum OnboardingStep: Int, CaseIterable {
    // Mode FIRST, then the warmth preview: the schedule is the cheap decision a new user can actually
    // reason about, and putting warmth last lands onboarding on its strongest sensory beat — the screen
    // blooming warm under the user's finger.
    case welcome, schedule, warmth, allSet

    /// The numbered position shown in "Step X of 3" — nil for the closing `allSet` screen, which is a
    /// completion confirmation, not a numbered setup step (keeps the "3 clicks to warmth" framing).
    var numberedIndex: Int? {
        switch self {
        case .welcome: return 1
        case .schedule: return 2
        case .warmth: return 3
        case .allSet: return nil
        }
    }
    static let numberedTotal = 3
}

// MARK: - OnboardingView
//
// "3 clicks to warmth" (plan §21.3, §4.6): welcome → choose the schedule → set your warmth — three
// numbered setup steps, then a brief UNNUMBERED "you're all set" confirmation that carries the privacy
// reassurance. Calm glass; everything else lives in Settings. The app needs no permissions, so onboarding
// asks for none — it just orients the user (a menu-bar agent launches invisibly) and lands them on warmth.
// Mode comes FIRST, applied LIVE so its effect is visible (Always-on warms now; Sunset stays neutral in
// daylight and says exactly when it will kick in); the warmth step then forces a "preview of your evening"
// so the screen blooms regardless of the chosen mode/time — the guaranteed payoff beat.
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
        // Drag the card from any empty area — the thin transparent title-bar strip alone was too easy to
        // miss. `performDrag` only fires for clicks that fall THROUGH to this background, so interactive
        // controls (slider, buttons, mode control, city picker) keep their own drags. (This is why we keep
        // `isMovableByWindowBackground` off — it would steal the WarmSlider's drag.)
        .background(WindowDraggableBackground())
        // Fill the window with the frosted-ember glass (same as Settings/About) so the OS rounds the
        // corners and the traffic-light buttons sit cleanly in the transparent title bar — no detached
        // floating-card border.
        .background(FrostBackground())
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

    // MARK: Step 3 — set the warmth (a live "preview of your evening")

    private var warmthStep: some View {
        VStack(spacing: 14) {
            Text("How warm should it get?")
                .font(Theme.Typography.serif(19))
                .foregroundStyle(Theme.Color.textPrimary)
            // Honest framing (fixes the old "set your maximum" copy — the slider sets everyday warmth, not
            // the ceiling). For Sunset users the forced preview is explicitly "your evening" so the cool-down
            // on finish reads as intended, not a glitch.
            Text(scheduleOption == .followSunset
                 ? "A preview of your evening — drag to set how warm. You can change it anytime."
                 : "Drag to set how warm. You can change it anytime.")
                .font(Theme.Typography.ui(12.5))
                .foregroundStyle(Theme.Color.textMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            // Live applied Kelvin — the slider drives the engine directly, so this number and the screen
            // warm together as you drag.
            Text("\(model.globalKelvin.displayValue) K")
                .font(Theme.Typography.serif(30))
                .monospacedDigit()
                .foregroundStyle(Theme.Color.accentHighlight)

            // Same science-backed accent metric as the popover ticker (instant updates here).
            BlueLightReductionLabel(kelvin: model.globalKelvin, animated: false)

            WarmSlider(strength: Binding(
                get: { model.state.globalWarmth.strength },
                set: { model.setGlobalWarmth($0) }
            ), model: model)

            PrimaryButton(title: "Looks right") {
                // Restore the schedule chosen in step 2 (this step forced Always-on so the screen could
                // bloom regardless of time). Sunset users ease back to neutral in daylight — expected,
                // because this step was framed as "a preview of your evening".
                model.setScheduleMode(scheduleOption.toScheduleMode(), userInitiated: false)
                advance()
            }
        }
        // Force the warm preview so the screen blooms regardless of the chosen mode/time — the one
        // guaranteed "this is what warm looks like" moment, starting at the warmest. Warming is already
        // on (from step 2), so this is a silent override; the "Looks right" button restores the real mode.
        .onAppear {
            model.setScheduleMode(.alwaysOn, userInitiated: false)
            model.setGlobalWarmth(1.0)
            model.setEnabled(true, userInitiated: false)
        }
    }

    // MARK: Step 2 — choose the schedule (mode FIRST, applied live so its effect is visible)

    private var scheduleStep: some View {
        VStack(spacing: 13) {
            Text("When should it warm?")
                .font(Theme.Typography.serif(19))
                .foregroundStyle(Theme.Color.textPrimary)

            // Apply the mode LIVE on each toggle so the user feels the difference immediately: Always-on
            // warms the screen now; Sunset (in daylight) eases back to neutral. `setScheduleMode` also
            // plays the soft mode tick (gated by the sound pref).
            ModeControl(selection: $scheduleOption) { option in
                model.setScheduleMode(option.toScheduleMode())
            }

            if scheduleOption == .followSunset {
                VStack(alignment: .leading, spacing: 11) {
                    sunsetScienceCard
                    VStack(alignment: .leading, spacing: 6) {
                        // It's not broken — it's armed. Say what's happening AND exactly when, so the
                        // neutral daytime screen never reads as "nothing happened".
                        Text(model.isWarmingActive
                             ? "The sun has set — your screen is warming now."
                             : "It’s daytime, so your screen stays neutral for now. Warmth eases in around your local sunset:")
                            .font(Theme.Typography.ui(11.5))
                            .foregroundStyle(Theme.Color.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                        CityAutocomplete(model: model, opensUpward: true)
                        Text(model.todaysSunsetReadout)
                            .font(Theme.Typography.ui(12, weight: .semibold))
                            .foregroundStyle(Theme.Color.accentHighlight)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
            } else {
                Text("Warmth starts now and stays on — day and night.")
                    .font(Theme.Typography.ui(12.5))
                    .foregroundStyle(Theme.Color.textMuted)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }

            PrimaryButton(title: "Continue") { advance() }   // → the warmth preview (step 3)
        }
        .animation(Theme.Motion.warm(reduceMotion: reduceMotion), value: scheduleOption)
        // Turn warming on + reflect the pre-selected mode the moment this step appears, so Always-on warms
        // live and Sunset honours the gate. Enabling here plays the warm-on chime (gated by the sound pref)
        // — "Abendrot is now active"; the mode tick then plays on each toggle.
        .onAppear {
            // Default to MAX warmth so picking Always-on here shows the FULL warm effect immediately
            // (Sunset stays gated to neutral in daylight; the warmth step lets either mode dial it back).
            model.setEnabled(true, userInitiated: true)
            model.setGlobalWarmth(1.0)
            model.setScheduleMode(scheduleOption.toScheduleMode(), userInitiated: false)
        }
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

// MARK: - WindowDraggableBackground
//
// A transparent NSView that lets the user drag the whole onboarding card from any empty area, not just the
// thin transparent title-bar strip. It only starts a window drag on mouse-downs that fall THROUGH to it —
// interactive SwiftUI controls consume their own events first — so it never steals a control's drag. Used
// instead of `isMovableByWindowBackground`, which steals the custom WarmSlider's drag.
private struct WindowDraggableBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
}

// MARK: - Preview

#Preview("Onboarding") {
    OnboardingView(model: AppModel(previewState: MockWarmthState.idleSingleDisplay)) {}
        .padding(40)
        .background(Theme.Color.groundIndigo)
}
