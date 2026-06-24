import SwiftUI
import AppKit
import WarmthKit

// MARK: - OnboardingStep

// `internal` (not `private`) so the screenshot harness in AbendrotApp can deep-link a start step.
enum OnboardingStep: Int, CaseIterable {
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

enum OnboardingLayout {
    static let contentWidth: CGFloat = 320
    static let welcomeHeight: CGFloat = 395
    static let scheduleAlwaysOnHeight: CGFloat = 380
    static let scheduleSunsetHeight: CGFloat = 570
    static let scheduleHeaderHeight: CGFloat = 210
    static let scheduleDetailHeight: CGFloat = 215
    static let warmthHeight: CGFloat = 520
    static let allSetHeight: CGFloat = 516
    static let minimumContentHeight: CGFloat = 300
    static let maximumContentHeight: CGFloat = 665

    static let initialContentSize = NSSize(width: contentWidth, height: welcomeHeight)
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
    var onHeightChange: (CGFloat, Bool) -> Void

    init(
        model: AppModel,
        onFinish: @escaping () -> Void,
        initialStep: OnboardingStep = .welcome,
        initialScheduleOption: ScheduleModeOption = .followSunset,
        onHeightChange: @escaping (CGFloat, Bool) -> Void = { _, _ in }
    ) {
        self._model = Bindable(wrappedValue: model)
        self.onFinish = onFinish
        self.onHeightChange = onHeightChange
        self._step = State(initialValue: initialStep)
        self._scheduleOption = State(initialValue: initialScheduleOption)
    }

    @State private var step: OnboardingStep
    @State private var scheduleOption: ScheduleModeOption = .followSunset
    // Warmth defaults to the warmest ONCE (first time the schedule step appears), so a return visit doesn't
    // wipe an Always-on user's dialed warmth. The warmth step then re-primes to warmest on EACH entry for
    // Sunset (a "preview of your evening"); Always-on keeps what the user set. See the two onAppears.
    @State private var hasInitializedWarmth = false
    /// The "You're all set" CTA is two-step: first "Open menu bar" (reveals the popover so the user sees
    /// where Abendrot lives), then "Done" (finishes). Flips true after the first tap.
    @State private var didOpenMenuBar = false
    /// Mirrors the warmth slider's press state: the blue-light % rolls on discrete changes (Cozy on→99)
    /// but stays silent during a live drag, where rapid numericText changes glitch. Fed by WarmSlider.
    @State private var sliderPressing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 38) {
            // Skip the top bar on the closing all-set step — it has no stepper or chevron there, so the
            // empty slot plus the stack spacing would leave a dead gap above the checkmark.
            if step != .allSet { topBar }

            Group {
                switch step {
                case .welcome: welcomeStep
                case .warmth: warmthStep
                case .schedule: scheduleStep
                case .allSet: allSetStep
                }
            }
            .transition(.opacity)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(24)
        // The NSWindow owns the resize. SwiftUI fills the live AppKit host height, so controls move with
        // the actual window edge instead of jumping straight to the final target height.
        .frame(width: OnboardingLayout.contentWidth, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .clipped()
        // Drag the card from any empty area — the thin transparent title-bar strip alone was too easy to
        // miss. `performDrag` only fires for clicks that fall THROUGH to this background, so interactive
        // controls (slider, buttons, mode control, city picker) keep their own drags. (This is why we keep
        // `isMovableByWindowBackground` off — it would steal the WarmSlider's drag.)
        .background(WindowDraggableBackground())
        // The frosted-ember glass (same as Settings/About): now full-window, so the OS rounds the corners,
        // the traffic-light buttons sit cleanly on the frost in the transparent title bar, and there is no
        // detached floating-card border and no gray bar.
        .background(FrostBackground())
        .onAppear {
            onHeightChange(targetContentHeight, false)
        }
        .onChange(of: targetContentHeight) { _, height in
            onHeightChange(height, !reduceMotion)
        }
        .animation(Theme.Motion.warm(reduceMotion: reduceMotion), value: step)
    }

    // MARK: Step indicator

    @ViewBuilder
    private var stepIndicator: some View {
        if let n = step.numberedIndex {
            OnboardingStepper(current: n, total: OnboardingStep.numberedTotal)
                .frame(maxWidth: .infinity)
        }
    }

    // A leading back chevron, shown only on the warmth step, layered over the centered stepper, so users
    // can return to step 2 and change their mode. Earlier steps need no back (welcome is the entry; the
    // mode step's onAppear re-applies the chosen mode on return); the closing all-set step has none.
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

            Spacer(minLength: 0)

            PrimaryButton(title: "Get started") { advance() }
                .padding(.bottom, 20)
        }
    }

    // MARK: Step 3 — set the warmth (a live "preview of your evening")

    private var warmthStep: some View {
        VStack(spacing: 14) {
            HStack(spacing: 6) {
                Text("How warm should we get?")
                    .font(Theme.Typography.serif(19))
                    .foregroundStyle(Theme.Color.textPrimary)
                // Ported from the popover Warmth header (founder) — the "what is Kelvin?" helper beside
                // the step title, since this step no longer shows the slider's own "Warmth" header.
                KelvinInfoButton()
            }
            // Lift the heading (and its hover tooltip) above the rows below, so the tooltip renders ON TOP
            // of the subtitle / Kelvin readout instead of those later VStack siblings painting over it.
            .zIndex(1)
            // The slider sets everyday warmth STRENGTH (not the Advanced "Maximum warmth" ceiling /
            // warmestPoint). Sunset shows "maximum warmth once the sun begins to set" — it names the peak the
            // evening ramp climbs to AND explains the cool-down on finish (daytime → neutral until sunset),
            // so the restore doesn't read as a glitch. Always-on needs no subtitle (the big Kelvin readout +
            // slider are self-explanatory).
            if scheduleOption == .followSunset {
                Text("Set your maximum warmth level.")
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
            BlueLightReductionLabel(kelvin: model.globalKelvin, cozy: isCozy, animated: !sliderPressing)

            WarmSlider(strength: Binding(
                get: { model.state.globalWarmth.strength },
                set: { model.setGlobalWarmth($0) }
            ), model: model, showsHeader: false, cozy: isCozy,
            onPressingChanged: { sliderPressing = $0 })

            // Cozy mode (the warmest candle & ember, below 1900 K) offered right here — the Settings →
            // Advanced control, compact (no section header / science caption). Enabling runs the slider all
            // the way to the warmest + ignites the fireball thumb (the deepest ember); the choice
            // (warmestPoint) persists past onboarding.
            CozyModeControl(model: model, showsSectionLabel: false, showsExplanation: false,
                            enablesAtWarmest: true)

            Spacer(minLength: 0)

            PrimaryButton(title: "Looks right") {
                // Restore the schedule chosen in step 2 (this step forced Always-on so the screen could
                // bloom regardless of time). Sunset users ease back to neutral in daylight — expected,
                // because this step was framed as "a preview of your evening".
                model.setScheduleMode(scheduleOption.toScheduleMode(), userInitiated: false)
                advance()
            }
            .padding(.bottom, 20)
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
        ZStack(alignment: .top) {
            scheduleHeader
                .frame(height: OnboardingLayout.scheduleHeaderHeight, alignment: .top)
                .transaction { $0.animation = nil }

            VStack(spacing: 0) {
                Color.clear.frame(height: OnboardingLayout.scheduleHeaderHeight + 13)

            ZStack(alignment: .top) {
                sunsetDetail
                    .opacity(isShowingSunsetDetail ? 1 : 0)
                    .allowsHitTesting(isShowingSunsetDetail)
                    .accessibilityHidden(!isShowingSunsetDetail)

                manualDetail
                    .opacity(isShowingSunsetDetail ? 0 : 1)
                    .allowsHitTesting(!isShowingSunsetDetail)
                    .accessibilityHidden(isShowingSunsetDetail)
            }
            .frame(
                height: 240,
                alignment: .top
            )
            .clipped()
            .animation(Theme.Motion.controlReveal(reduceMotion: reduceMotion), value: isShowingSunsetDetail)

            Spacer(minLength: 0)

            PrimaryButton(title: isShowingSunsetDetail ? "Continue" : "Looks right") { advance() }
                .padding(.bottom, 20)
        }
    }
    .frame(maxHeight: .infinity, alignment: .top)
    .onAppear {
        model.setEnabled(true, userInitiated: false)
        if !hasInitializedWarmth {
            model.setGlobalWarmth(1.0)
            hasInitializedWarmth = true
        }
        model.setScheduleMode(scheduleOption.toScheduleMode(), userInitiated: false)
    }
}

private var manualDetail: some View {
    VStack(spacing: 14) {
        HStack(spacing: 6) {
            Text("\(model.globalKelvin.displayValue) K")
                .font(Theme.Typography.serif(30))
                .monospacedDigit()
                .foregroundStyle(Theme.Color.accentHighlight)
            
            KelvinInfoButton()
        }
        .zIndex(1)

        BlueLightReductionLabel(kelvin: model.globalKelvin, cozy: isCozy, animated: !sliderPressing)

        WarmSlider(strength: Binding(
            get: { model.state.globalWarmth.strength },
            set: { model.setGlobalWarmth($0) }
        ), model: model, showsHeader: false, cozy: isCozy,
        onPressingChanged: { sliderPressing = $0 })

        CozyModeControl(model: model, showsSectionLabel: false, showsExplanation: false,
                        enablesAtWarmest: true)
    }
}

    private var scheduleHeader: some View {
        VStack(spacing: 13) {
            Text("When should we warm?")
                .font(Theme.Typography.serif(19))
                .foregroundStyle(Theme.Color.textPrimary)

            Text(scheduleSubtitle)
                .font(Theme.Typography.ui(11.5))
                .foregroundStyle(Theme.Color.textMuted)
                .multilineTextAlignment(.center)
                .frame(height: 40)
                .frame(maxWidth: .infinity)

            ModeControl(selection: scheduleSelection, animatesSelection: false) { _ in }
        }
    }

    // MARK: Step 4 — closing confirmation (not numbered) — privacy reassurance lives here now
    private var allSetStep: some View {
        VStack(spacing: 18) {
            ZStack {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 46, weight: .light))
                    .foregroundStyle(Theme.Color.accentHighlight)
                    .shadow(color: Theme.Color.accentPress.opacity(0.3), radius: 14, y: 5)
                    .accessibilityHidden(true)
                
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

            Text("You’re all set")
                .font(Theme.Typography.serif(22))
                .foregroundStyle(Theme.Color.textPrimary)
            Text("Make adjustments in the menu bar.")
                .font(Theme.Typography.ui(12.5))
                .foregroundStyle(Theme.Color.textMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            privacyNote
                .padding(.top, 6)

            Spacer(minLength: 0)

            // Two-step CTA: first reveal the menu-bar popover (so the user SEES where Abendrot lives), then
            // finish (founder). The title swaps to "Done" after the first tap.
            VStack(spacing: 10) {
                SecondaryButton(title: "Star on GitHub", icon: "star") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/matthewrball/abendrot")!)
                }

                PrimaryButton(title: didOpenMenuBar ? "Done" : "Open menu bar") {
                    if didOpenMenuBar {
                        onFinish()
                    } else {
                        openMenuBarPopover()
                        didOpenMenuBar = true
                    }
                }
            }
            .padding(.top, 2)
            .padding(.bottom, 20)
        }
    }

    // §13-safe science nudge toward Sunset. Cites the expert EVENING-LIGHT consensus (an input/habit
    // recommendation, NOT a sleep-outcome promise) and states only what the engine does (eases off blue in
    // the evening) — the approved "supports healthy evening light habits" framing. NO medical/sleep claim,
    // no "improves sleep". Wording from docs/marketing/evidence-base.md claim #5 (Brown et al. 2022).
    private var sunsetScienceCard: some View {
        sunsetScienceCardContent
            .glassSurface(.frost, cornerRadius: Theme.Radius.control)
    }

    private var sunsetScienceCardContent: some View {
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
    }

    // Brief, beautiful privacy reassurance — the closing note. Reuses the Privacy settings page's
    // checkmark.shield icon. A general promise (not just location), since it's the parting word.
    private var privacyNote: some View {
        VStack(spacing: 4) {
            Text("Private by default")
                .font(Theme.Typography.ui(11.5, weight: .semibold))
                .foregroundStyle(Theme.Color.textPrimary)
            
            Text("Nothing about you or your displays ever leaves this Mac — no account, no tracking, no telemetry.")
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

    private var scheduleSubtitle: String {
        if scheduleOption == .alwaysOn { return "Warms continuously, day\u{00A0}and\u{00A0}night." }
        return model.isWarmingActive
            ? "The sun has set — your screen is warming now."
            : "It’s daytime, so your screen stays neutral for now — warmth eases in around your local sunset."
    }

    private var scheduleSelection: Binding<ScheduleModeOption> {
        Binding(
            get: { scheduleOption },
            set: { applyScheduleOption($0) }
        )
    }

    private var targetContentHeight: CGFloat {
        switch step {
        case .welcome:
            return OnboardingLayout.welcomeHeight
        case .schedule:
            return OnboardingLayout.scheduleSunsetHeight
        case .warmth:
            return OnboardingLayout.warmthHeight
        case .allSet:
            return OnboardingLayout.allSetHeight
        }
    }

    private var isShowingSunsetDetail: Bool {
        scheduleOption == .followSunset
    }

    private var sunsetDetail: some View {
        VStack(alignment: .leading, spacing: 11) {
            sunsetScienceCard
            sunsetLocationFields
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sunsetLocationFields: some View {
        VStack(alignment: .leading, spacing: 6) {
            CityAutocomplete(model: model, opensUpward: true)
            Text(model.todaysSunsetReadout)
                .font(Theme.Typography.ui(12, weight: .semibold))
                .foregroundStyle(Theme.Color.accentHighlight)
        }
    }

    private func applyScheduleOption(_ option: ScheduleModeOption) {
        guard option != scheduleOption else { return }
        scheduleOption = option
        model.setScheduleMode(option.toScheduleMode())
    }

    private func advance() {
        if step == .schedule && scheduleOption == .alwaysOn {
            step = .allSet
            return
        }
        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else {
            onFinish()
            return
        }
        step = next
    }

    private func goBack() {
        if step == .allSet && scheduleOption == .alwaysOn {
            step = .schedule
            return
        }
        guard let prev = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        // The warmth step forces an Always-on PREVIEW so the screen blooms regardless of time. Undo it on
        // the way back too — the "Looks right" forward path already restores the real mode — so a Sunset
        // user eases back to neutral in daylight instead of the preview warming lingering on the mode step.
        // (Back only ever shows on the warmth and allSet steps.)
        if step == .warmth {
            model.setScheduleMode(scheduleOption.toScheduleMode(), userInitiated: false)
        }
        step = prev
    }

    /// Reveal the menu-bar popover so the user sees where Abendrot lives. SwiftUI's `MenuBarExtra(.window)`
    /// has no public "present" API, so we find its `NSStatusBarButton` in the app's windows and click it.
    /// Best-effort — a no-op if the button can't be located (the user still has the "Done" tap to finish).
    private func openMenuBarPopover() {
        func find(in view: NSView) -> NSStatusBarButton? {
            if let button = view as? NSStatusBarButton { return button }
            for sub in view.subviews { if let button = find(in: sub) { return button } }
            return nil
        }
        for window in NSApp.windows {
            if let content = window.contentView, let button = find(in: content) {
                button.performClick(nil)
                return
            }
        }
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

// MARK: - SecondaryButton

/// A secondary CTA with a frosted glass background and optional icon.
struct SecondaryButton: View {
    let title: String
    var icon: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                }
                Text(title)
            }
            .font(Theme.Typography.ui(13, weight: .medium))
            .foregroundStyle(Theme.Color.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .glassSurface(.frost, cornerRadius: Theme.Radius.control - 1)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.control - 1, style: .continuous)
                    .strokeBorder(Theme.Color.line.opacity(0.5), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - OnboardingStepper
//
// A minimal, animated progress indicator that replaces "Step N of 3". Instead of per-dot capsules that
// each resize in place (which read as a teleport, with the gradient fill popping mid-spring), it's a
// FIXED dim-dot rail with a SINGLE ember pill — the brand's sunset gradient + a specular glass sheen +
// a soft ember glow, the same Liquid-Glass language as the ModeControl pill and the WarmSlider thumb —
// that GLIDES from dot to dot. As it travels it squash-stretches along the axis and settles with a faint
// overshoot (the liquid-glass "blob"), so advancing feels fluid and alive rather than abrupt. Completed
// dots read a touch brighter than upcoming ones. Reduce-Motion drops both the glide and the stretch (the
// filled pill still marks the active step). Onboarding is seen only a few times, so the bounce never tires.
private struct OnboardingStepper: View {
    let current: Int        // 1-based
    let total: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let dot: CGFloat = 7        // inactive dot diameter
    private let gap: CGFloat = 13       // gap between dots — roomy enough the pill never crowds the next dot
    private let pillW: CGFloat = 20     // the traveling ember lozenge (a gentle elongation, not a bar)
    private let pillH: CGFloat = 8
    private var stride: CGFloat { dot + gap }
    private var overhang: CGFloat { (pillW - dot) / 2 }   // keeps the pill in-bounds at both ends
    private var pillOffset: CGFloat { CGFloat(current - 1) * stride }

    var body: some View {
        ZStack(alignment: .leading) {
            // The rail — dim dots that never reflow; completed ones read a touch brighter.
            HStack(spacing: gap) {
                ForEach(1...total, id: \.self) { i in
                    Circle()
                        .fill(Theme.Color.textFaint.opacity(i < current ? 0.5 : 0.25))
                        .frame(width: dot, height: dot)
                }
            }
            .padding(.horizontal, overhang)

            // The ember pill — gradient + sheen + glow ride as ONE view, so nothing pops.
            emberPill
                .frame(width: pillW, height: pillH)
                .offset(x: pillOffset)
                .animation(travel, value: current)   // springy, faintly-overshooting glide
                // Squash-stretch along the travel axis on each step change, then settle — the liquid delight.
                .keyframeAnimator(initialValue: Stretch(), trigger: reduceMotion ? 0 : current) { pill, s in
                    pill.scaleEffect(x: s.x, y: s.y, anchor: .center)
                } keyframes: { _ in
                    KeyframeTrack(\.x) {
                        CubicKeyframe(1.25, duration: 0.20)
                        SpringKeyframe(1.0, duration: 0.36, spring: .snappy)
                    }
                    KeyframeTrack(\.y) {
                        CubicKeyframe(0.82, duration: 0.20)
                        SpringKeyframe(1.0, duration: 0.36, spring: .snappy)
                    }
                }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(current) of \(total)")
    }

    private var travel: Animation? {
        reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.66)
    }

    private var emberPill: some View {
        Capsule(style: .continuous)
            .fill(Theme.Gradient.sunsetHorizontal)
            .overlay {
                // Specular highlight — the liquid-glass sheen (matches the WarmSlider thumb).
                Capsule(style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.06), .clear],
                                         startPoint: .top, endPoint: .bottom))
                    .blendMode(.softLight)
            }
            .shadow(color: Theme.Color.accent.opacity(0.55), radius: 6)   // ember glow travels with it
    }

    /// Horizontal/vertical scale for the travel squash-stretch (settles back to 1×1).
    private struct Stretch { var x: CGFloat = 1; var y: CGFloat = 1 }
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
