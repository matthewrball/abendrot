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
    // Warmth defaults to the warmest ONCE (first time the schedule step appears), so a return visit doesn't
    // wipe an Always-on user's dialed warmth. The warmth step then re-primes to warmest on EACH entry for
    // Sunset (a "preview of your evening"); Always-on keeps what the user set. See the two onAppears.
    @State private var hasInitializedWarmth = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 18) {
            topBar

            Group {
                switch step {
                case .welcome: welcomeStep
                case .warmth: warmthStep
                case .schedule: scheduleStep
                case .allSet: allSetStep
                }
            }
            .transition(.opacity)
        }
        .padding(24)
        .frame(width: 320)                 // fixed WIDTH; the height hugs each step/mode's content and the
        .fixedSize(horizontal: false, vertical: true)   // window self-sizes to it (top edge fixed — see
                                           // OnboardingWindowController.fitContentHeight), so Always-on
                                           // compresses and the heading + switcher stay put at the top.
        // Drag the card from any empty area — the thin transparent title-bar strip alone was too easy to
        // miss. `performDrag` only fires for clicks that fall THROUGH to this background, so interactive
        // controls (slider, buttons, mode control, city picker) keep their own drags. (This is why we keep
        // `isMovableByWindowBackground` off — it would steal the WarmSlider's drag.)
        .background(WindowDraggableBackground())
        // Fill the window with the frosted-ember glass (same as Settings/About) so the OS rounds the
        // corners and the traffic-light buttons sit cleanly in the transparent title bar — no detached
        // floating-card border.
        .background(FrostBackground())
        // Report the natural content height so the window hugs each step/mode (top edge fixed): Always-on
        // compresses, Sunset grows, the heading stays put. Mirrors the self-sizing Settings window.
        .background(GeometryReader { proxy in
            Color.clear.preference(key: OnboardingHeightKey.self, value: proxy.size.height)
        })
        .onPreferenceChange(OnboardingHeightKey.self) { OnboardingWindowController.fitContentHeight($0) }
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

    // A leading back chevron, shown only on the warmth step, layered over the centered step indicator,
    // so users can return to step 2 and change their mode. Earlier steps need no back (welcome is the
    // entry; the mode step's onAppear re-applies the chosen mode on return).
    @ViewBuilder
    private var topBar: some View {
        ZStack {
            stepIndicator
            if step == .warmth {
                HStack {
                    Button { goBack() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.Color.textMuted)
                            .padding(.vertical, 4)
                            .padding(.trailing, 10)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")
                    Spacer()
                }
            }
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
            HStack(spacing: 6) {
                Text(scheduleOption == .followSunset ? "How warm should it get?" : "Set your warmth")
                    .font(Theme.Typography.serif(19))
                    .foregroundStyle(Theme.Color.textPrimary)
                // Ported from the popover Warmth header (founder) — the "what is Kelvin?" helper beside
                // the step title, since this step no longer shows the slider's own "Warmth" header.
                KelvinInfoButton()
            }
            // The slider sets everyday warmth STRENGTH (not the Advanced "Maximum warmth" ceiling /
            // warmestPoint). Sunset shows "maximum warmth once the sun begins to set" — it names the peak the
            // evening ramp climbs to AND explains the cool-down on finish (daytime → neutral until sunset),
            // so the restore doesn't read as a glitch. Always-on needs no subtitle (the big Kelvin readout +
            // slider are self-explanatory).
            if scheduleOption == .followSunset {
                Text("Set your maximum warmth once the sun begins to set.")
                    .font(Theme.Typography.ui(12.5))
                    .foregroundStyle(Theme.Color.textMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

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
            ), model: model, showsHeader: false, cozy: isCozy)

            // Cozy mode (the warmest candle & ember, below 1900 K) offered right here — the Settings →
            // Advanced control, compact (no section header / science caption). Enabling animates the slider
            // to halfway + ignites the fireball thumb so the user slides up into the deepest warmth; the
            // choice (warmestPoint) persists past onboarding.
            CozyModeControl(model: model, showsSectionLabel: false, showsExplanation: false,
                            keepsSliderInPlace: true)

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
            // Re-prime to the warmest "preview of your evening" on EVERY entry for Sunset — showing the peak
            // the evening ramp climbs to is this step's whole job. EXCEPTION: for Always-on the slider sets
            // the user's REAL everyday warmth, so re-slamming 1.0 on back-nav would discard what they dialed
            // — keep it.
            if scheduleOption != .alwaysOn {
                model.setGlobalWarmth(1.0)
            }
            model.setEnabled(true, userInitiated: false)
        }
    }

    // MARK: Step 2 — choose the schedule (mode FIRST, applied live so its effect is visible)

    private var scheduleStep: some View {
        VStack(spacing: 13) {
            Text("When should it warm?")
                .font(Theme.Typography.serif(19))
                .foregroundStyle(Theme.Color.textPrimary)

            // A FIXED-HEIGHT subtitle slot under the heading, crossfading the Sunset status line and the
            // Always-on description, so the switcher below NEVER moves when toggling modes (founder: the
            // switcher must stay put). Both modes fill the same slot.
            ZStack {
                if scheduleOption == .followSunset {
                    Text(model.isWarmingActive
                         ? "The sun has set — your screen is warming now."
                         : "It’s daytime, so your screen stays neutral for now — warmth eases in around your local sunset.")
                        .transition(.opacity)
                } else {
                    Text("Warms continuously, day\u{00A0}and\u{00A0}night.")
                        .transition(.opacity)
                }
            }
            .font(Theme.Typography.ui(11.5))
            .foregroundStyle(Theme.Color.textMuted)
            .multilineTextAlignment(.center)
            .frame(height: 40)
            .frame(maxWidth: .infinity)

            // Apply the mode LIVE on each toggle so the user feels the difference immediately: Always-on
            // warms the screen now; Sunset (in daylight) eases back to neutral. `setScheduleMode` also
            // plays the soft mode tick (gated by the sound pref). The switcher sits at a CONSTANT y — the
            // heading + fixed subtitle slot above it never change height.
            ModeControl(selection: $scheduleOption) { option in
                model.setScheduleMode(option.toScheduleMode())
            }

            // Sunset-only detail BELOW the switcher; its presence/absence can't move the switcher above it.
            if scheduleOption == .followSunset {
                VStack(alignment: .leading, spacing: 11) {
                    sunsetScienceCard
                    VStack(alignment: .leading, spacing: 6) {
                        CityAutocomplete(model: model, opensUpward: true)
                        Text(model.todaysSunsetReadout)
                            .font(Theme.Typography.ui(12, weight: .semibold))
                            .foregroundStyle(Theme.Color.accentHighlight)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
            // ONCE only — on a return visit (back from the warmth step) we must NOT re-slam 1.0, or an
            // Always-on user's dialed warmth would be lost the moment they step back to change the mode.
            model.setEnabled(true, userInitiated: true)
            if !hasInitializedWarmth {
                model.setGlobalWarmth(1.0)
                hasInitializedWarmth = true
            }
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
            Text("International expert consensus recommends keeping evening light low in blue in the hours before bed. Sunset eases your screen off blue automatically as evening falls.")
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

    /// Cozy mode (deepest warmth) is on when the warmest point is below the everyday 1900K ceiling — drives
    /// the fireball thumb + "Warmest" label on the step-3 slider.
    private var isCozy: Bool { model.state.warmestPoint.value < Kelvin.everydayWarmest.value }

    private func advance() {
        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else {
            onFinish()
            return
        }
        step = next
    }

    private func goBack() {
        guard let prev = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        // The warmth step forces an Always-on PREVIEW so the screen blooms regardless of time. Undo it on
        // the way back too — the "Looks right" forward path already restores the real mode — so a Sunset
        // user eases back to neutral in daylight instead of the preview warming lingering on the mode step.
        // (Back only ever shows on the warmth step.)
        if step == .warmth {
            model.setScheduleMode(scheduleOption.toScheduleMode(), userInitiated: false)
        }
        step = prev
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

// MARK: - OnboardingHeightKey

/// The onboarding card's natural content height, so the window can hug each step/mode — see
/// `OnboardingWindowController.fitContentHeight`.
private struct OnboardingHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

// MARK: - Preview

#Preview("Onboarding") {
    OnboardingView(model: AppModel(previewState: MockWarmthState.idleSingleDisplay)) {}
        .padding(40)
        .background(Theme.Color.groundIndigo)
}
