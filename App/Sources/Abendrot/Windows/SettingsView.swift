import SwiftUI
import ServiceManagement
import WarmthKit

// MARK: - SettingsTab

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, schedule, displays, advanced, privacy, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .schedule: return "Schedule"
        case .displays: return "Displays"
        case .advanced: return "Advanced"
        case .privacy: return "Privacy"
        case .about: return "About"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .schedule: return "sunset"
        case .displays: return "display.2"
        case .advanced: return "slider.horizontal.3"
        case .privacy: return "hand.raised"
        case .about: return "info.circle"
        }
    }
}

// MARK: - SettingsView
//
// The Settings window body (plan §4.4 tabs: General / Schedule / Displays / Shortcuts
// / Advanced / Privacy / About). Hosted by the programmatic `SettingsWindowController`
// so the "frosted ember" glass chrome actually renders (a SwiftUI `Window` scene
// resets `.fullSizeContentView`; see reference doc). Settings double as onboarding +
// trust-builder (CleanShot X pattern).
//
// This structural pass lays out the tab shell + representative controls per tab; the
// deep editors (custom-schedule picker, exclusion picker, shortcut recorder) are
// marked TODO and wired in a later milestone.
struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var selection: SettingsTab = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, selection: $selection) { tab in
                Label(tab.title, systemImage: tab.icon)
                    .tag(tab)
            }
            .navigationSplitViewColumnWidth(min: 172, ideal: 180)
            .scrollContentBackground(.hidden)
        } detail: {
            ScrollView {
                tabBody
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollContentBackground(.hidden)
        }
        .frame(minWidth: 680, minHeight: 420)
        .background(SettingsFrostBackground())
    }

    @ViewBuilder
    private var tabBody: some View {
        switch selection {
        case .general: GeneralTab(model: model)
        case .schedule: ScheduleTab(model: model)
        case .displays: DisplaysTab(model: model)
        case .advanced: AdvancedTab(model: model)
        case .privacy: PrivacyTab(model: model)
        case .about: AboutTab()
        }
    }
}

// MARK: - Frosted-ember background

/// The persistent "frosted ember" material for Settings (§21.3). Degrades to the
/// ember SOLID under Reduce Transparency via `GlassSurface`.
private struct SettingsFrostBackground: View {
    var body: some View {
        Color.clear
            .glassSurface(.frost, cornerRadius: 0)
            .ignoresSafeArea()
    }
}

// MARK: - Tab header

private struct TabHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.Typography.ui(16, weight: .semibold))
                .foregroundStyle(Theme.Color.textPrimary)
            Text(subtitle)
                .font(Theme.Typography.ui(12.5))
                .foregroundStyle(Theme.Color.textMuted)
        }
        .padding(.bottom, 20)
    }
}

// MARK: - General

private struct GeneralTab: View {
    @Bindable var model: AppModel
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("softConfirmationTone") private var softTone = false
    @State private var launchAtLoginError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            TabHeader(title: "General", subtitle: "How Abendrot behaves day to day.")

            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, isOn in
                    setLaunchAtLogin(isOn)
                }
            if let launchAtLoginError {
                Text(launchAtLoginError)
                    .font(Theme.Typography.ui(11.5))
                    .foregroundStyle(Theme.Color.textFaint)
            }
            // Show-in-menu-bar with clear re-entry (plan §4.3).
            Toggle("Show icon in menu bar", isOn: $model.showInMenuBar)
            if !model.showInMenuBar {
                Text("Hidden from the menu bar. Re-open with ⌥⌘T, or relaunch Abendrot to bring Settings back.")
                    .font(Theme.Typography.ui(11.5))
                    .foregroundStyle(Theme.Color.textFaint)
            }
            Toggle("Soft confirmation tone", isOn: $softTone)

            DividerLine()

            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("Default warmth")
                        .font(Theme.Typography.ui(13.5))
                    Spacer()
                    Text("\(model.globalKelvin.value) K")
                        .font(Theme.Typography.serif(14))
                        .monospacedDigit()
                        .foregroundStyle(Theme.Color.accentHighlight)
                }
                WarmSlider(
                    strength: Binding(
                        get: { model.state.globalWarmth.strength },
                        set: { model.setGlobalWarmth($0) }
                    )
                )
            }
        }
        .toggleStyle(.switch)
        .tint(Theme.Color.accent)
        .onAppear {
            // Reflect the real login-item state, which can change outside the app
            // (System Settings → General → Login Items), so the toggle never lies.
            launchAtLogin = SMAppService.mainApp.status == .enabled
            launchAtLoginError = nil
        }
    }

    /// Register/unregister the app as a login item via ServiceManagement. Reverts the
    /// stored toggle and surfaces a message if the system call fails (e.g. the user
    /// has the item disabled in System Settings, which requires their approval).
    private func setLaunchAtLogin(_ enable: Bool) {
        launchAtLoginError = nil
        do {
            if enable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Roll the toggle back to the system's actual state and explain why.
            launchAtLogin = SMAppService.mainApp.status == .enabled
            launchAtLoginError = "Couldn't \(enable ? "enable" : "disable") launch at login: \(error.localizedDescription)"
        }
    }
}

// MARK: - Schedule

private struct ScheduleTab: View {
    @Bindable var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            TabHeader(title: "Schedule", subtitle: "When Abendrot warms your displays.")
            ModeControl(
                selection: Binding(
                    get: { ScheduleModeOption(model.state.scheduleMode) },
                    set: { model.setScheduleMode($0.toScheduleMode()) }
                ),
                onChange: { _ in }
            )
            Text("Sunset warms automatically around your local sunset — easing in beforehand and holding through the night — using your time zone to estimate sunrise and sunset. No location permission required. Always on keeps warmth on around the clock.")
                .font(Theme.Typography.ui(12))
                .foregroundStyle(Theme.Color.textMuted)
        }
    }
}

// MARK: - Displays

private struct DisplaysTab: View {
    @Bindable var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            TabHeader(title: "Displays", subtitle: "Each connected display and how it's warmed.")
            VStack(spacing: 12) {
                ForEach(model.state.displays) { display in
                    DisplayConfigRow(display: display, model: model)
                }
            }
            DividerLine()
            Button(role: .destructive) {
                model.restoreAllDisplays()
            } label: {
                Label("Restore all displays to neutral", systemImage: "arrow.counterclockwise")
            }
            Text("Emergency reset: returns every display to true colour. Always available.")
                .font(Theme.Typography.ui(11.5))
                .foregroundStyle(Theme.Color.textFaint)
        }
    }
}

/// One display in Settings → Displays: its name, a plain-language status of whether it can be truly
/// warmed or only tinted, and a per-display "Advanced" disclosure revealing the warming-method
/// picker. This *is* the "Displays → Advanced" compatibility section — the engine/method jargon
/// (gamma / DDC / overlay badges) that used to sit on these rows is now expressed in plain language
/// here and nowhere else. (§26 Settings de-jargon.)
private struct DisplayConfigRow: View {
    let display: DisplayState
    @Bindable var model: AppModel
    @State private var showAdvanced = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(display.name)
                        .font(Theme.Typography.ui(13, weight: .medium))
                        .foregroundStyle(Theme.Color.textPrimary)
                    Text(statusLine)
                        .font(Theme.Typography.ui(11.5))
                        .foregroundStyle(canTrueWarm ? Theme.Color.textMuted : Theme.Color.accentHighlight)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button {
                    withAnimation(Theme.Motion.controlReveal(reduceMotion: reduceMotion)) {
                        showAdvanced.toggle()
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text("Advanced").font(Theme.Typography.ui(11))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .rotationEffect(.degrees(showAdvanced ? 180 : 0))
                    }
                    .foregroundStyle(Theme.Color.textMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showAdvanced
                    ? "Hide advanced options for \(display.name)"
                    : "Show advanced options for \(display.name)")
            }

            if showAdvanced {
                WarmingMethodPicker(display: display, model: model)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
        .background(Theme.Color.line.opacity(0.4),
                    in: RoundedRectangle(cornerRadius: Theme.Radius.control - 1, style: .continuous))
        .animation(Theme.Motion.controlReveal(reduceMotion: reduceMotion), value: showAdvanced)
    }

    /// A display can be *truly* warmed when a real white-point path is available — gamma or hardware
    /// DDC — with advanced methods enabled. Otherwise it can only be tinted. (Mirrors the popover's
    /// `isTintOnly`, §25.J.)
    private var canTrueWarm: Bool {
        let priv = model.state.privateAPIsEnabled
        return priv && (isSupported(display.capabilities.gamma) || isSupported(display.capabilities.hardware))
    }

    private var statusLine: String {
        canTrueWarm
            ? "Truly warmed — removes blue light"
            : "Can only be tinted on this Mac — true warming isn’t available for this display"
    }

    private func isSupported<T>(_ cap: Capability<T>) -> Bool {
        if case .supported = cap { return true }
        return false
    }
}

// MARK: - Warming-method picker (plain-language per-display layer choice)

/// The de-jargoned per-display warming-method control. Plain labels (Codex): **Automatic /
/// Standard / Screen tint / Hardware control** map onto the engine's `DisplayMethod` override.
/// Only methods actually usable for this display are offered, so the available options themselves
/// communicate what the hardware/OS supports (an incompatible display offers only Automatic +
/// Screen tint). (§26 Settings de-jargon.)
private struct WarmingMethodPicker: View {
    let display: DisplayState
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Warming method")
                .font(Theme.Typography.ui(11.5, weight: .medium))
                .foregroundStyle(Theme.Color.textMuted)

            Picker("Warming method", selection: choiceBinding) {
                ForEach(availableChoices) { choice in
                    Text(choice.label).tag(choice)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text(choiceBinding.wrappedValue.description)
                .font(Theme.Typography.ui(11))
                .foregroundStyle(Theme.Color.textFaint)
                .fixedSize(horizontal: false, vertical: true)

            if let note = unavailableNote {
                Text(note)
                    .font(Theme.Typography.ui(11))
                    .foregroundStyle(Theme.Color.textFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 2)
    }

    /// The methods offered for this display, in Codex's order, filtered to what's usable right now.
    private var availableChoices: [WarmingMethodChoice] {
        let priv = model.state.privateAPIsEnabled
        var choices: [WarmingMethodChoice] = [.automatic]
        if priv, isSupported(display.capabilities.gamma) { choices.append(.standard) }
        choices.append(.screenTint)                                     // overlay is always available
        if priv, isSupported(display.capabilities.hardware) { choices.append(.hardwareControl) }
        return choices
    }

    private var choiceBinding: Binding<WarmingMethodChoice> {
        Binding(
            get: {
                let current = WarmingMethodChoice(display.preferredMethod)
                return availableChoices.contains(current) ? current : .automatic
            },
            set: { apply($0) }
        )
    }

    /// "Hardware control" is the explicit DDC opt-in, so selecting it enables DDC for this display;
    /// every other choice turns DDC back off (DDC is opt-in per display — contract invariant #2).
    private func apply(_ choice: WarmingMethodChoice) {
        switch choice {
        case .hardwareControl:
            model.setHardwareDDCEnabled(true, for: display.id)
            model.setPreferredMethod(.hardware, for: display.id)
        default:
            model.setHardwareDDCEnabled(false, for: display.id)
            model.setPreferredMethod(choice.preferredMethod, for: display.id)
        }
    }

    private var unavailableNote: String? {
        let priv = model.state.privateAPIsEnabled
        if !priv {
            return "Advanced warming methods are turned off in Advanced, so only a screen tint is available."
        }
        if !isSupported(display.capabilities.gamma), !isSupported(display.capabilities.hardware) {
            return "This display can’t be truly warmed on this Mac — only a screen tint is available."
        }
        return nil
    }

    private func isSupported<T>(_ cap: Capability<T>) -> Bool {
        if case .supported = cap { return true }
        return false
    }
}

/// Plain-language names for the per-display warming method (Settings → Displays → Advanced). Maps to
/// the engine's `DisplayMethod` override: Automatic = best-available (nil), Standard = gamma (the OS
/// white-point true-warm), Screen tint = overlay, Hardware control = DDC.
private enum WarmingMethodChoice: String, CaseIterable, Identifiable {
    case automatic, standard, screenTint, hardwareControl
    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic: return "Automatic"
        case .standard: return "Standard"
        case .screenTint: return "Screen tint"
        case .hardwareControl: return "Hardware control"
        }
    }

    var description: String {
        switch self {
        case .automatic:
            return "Let Abendrot pick the best way to warm this display. Recommended."
        case .standard:
            return "Warm the whole display through macOS — truly removes blue light."
        case .screenTint:
            return "Lay a warm tint over the screen. Works everywhere, but it’s a tint, not true warming."
        case .hardwareControl:
            return "Adjust the monitor’s own colour over the cable. Only some external monitors support this."
        }
    }

    var preferredMethod: DisplayMethod? {
        switch self {
        case .automatic: return nil
        case .standard: return .gamma
        case .screenTint: return .overlay
        case .hardwareControl: return .hardware
        }
    }

    init(_ method: DisplayMethod?) {
        switch method {
        case .gamma: self = .standard
        case .overlay: self = .screenTint
        case .hardware: self = .hardwareControl
        default: self = .automatic        // nil or .off → automatic
        }
    }
}

// MARK: - Advanced

private struct AdvancedTab: View {
    @Bindable var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            TabHeader(title: "Advanced", subtitle: "Power controls for warming and compatibility.")

            MaximumWarmthControl(model: model)
            DividerLine()

            // Reveal True Color hotkey — moved here from the former Shortcuts tab, tucked under
            // Maximum warmth (founder). Click the field to rebind; default ⌥⌘T.
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Reveal True Color").font(Theme.Typography.ui(13.5))
                    Spacer()
                    RevealShortcutRecorder()
                }
                Text("Click the field and press a key combination to rebind (default ⌥⌘T). Hold the shortcut to reveal true colour; release to ease warmth back.")
                    .font(Theme.Typography.ui(12))
                    .foregroundStyle(Theme.Color.textMuted)
                // TODO(settings): a Hold/Toggle reveal-mode picker (RevealMode on HotkeyService).
            }
            DividerLine()

            // The private-API kill switch, in plain language. On = Abendrot can truly warm displays
            // (gamma / hardware) and follow Night Shift; off = the simplest, most compatible tint-only
            // mode everywhere. (§26 de-jargon — was "Enable private-API paths (DDC + Night Shift follow)".)
            Toggle("Use advanced warming methods", isOn: Binding(
                get: { model.state.privateAPIsEnabled },
                set: { model.setPrivateAPIsEnabled($0) }
            ))
            .toggleStyle(.switch)
            .tint(Theme.Color.accent)
            Text("Lets Abendrot truly warm your displays — removing blue light — and follow your Night Shift schedule. Turn this off to use the simplest, most compatible mode: a warm tint over every display.")
                .font(Theme.Typography.ui(12))
                .foregroundStyle(Theme.Color.textMuted)
            // TODO(settings): per-app exclusion picker → AppModel.setExcludedApps.
            Text("Per-app exclusions — picker coming in a later milestone.")
                .font(Theme.Typography.ui(11.5))
                .foregroundStyle(Theme.Color.textFaint)
        }
    }
}

// MARK: - Maximum warmth (warmest-point ceiling + opt-in expanded range)

/// Sets the slider's *warmest end* (the engine `warmestPoint`). The everyday maximum is 1900K —
/// the point where blue is fully removed (so "minimize blue light" is already 100% achieved). The
/// opt-in "Expanded range" unlocks deeper warmth toward pure red (~500K): a real but minimal
/// additional circadian reduction with a real legibility cost — see
/// docs/research/max-warmth-circadian-research.md (Brown et al. 2022; CIE S 026:2018). The slider
/// reads "right = warmer", matching the main warmth slider.
private struct MaximumWarmthControl: View {
    @Bindable var model: AppModel
    // Derived (not separately persisted) from the actual warmest point on appear, so the toggle can
    // never disagree with the value. The warmest point itself is what persists (via AppModel).
    @State private var expanded = false

    private var coolBound: Int { Kelvin.ceilingCoolBound.value }   // least-warm end of this control
    private var warmBound: Int { expanded ? Kelvin.warmestSupported.value : Kelvin.everydayWarmest.value }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Maximum warmth")
                    .font(Theme.Typography.ui(13.5))
                Spacer()
                Text("\(model.state.warmestPoint.value) K")
                    .font(Theme.Typography.serif(14))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Color.accentHighlight)
            }
            Text("The warmest your slider can reach. 1900 K already removes blue light entirely.")
                .font(Theme.Typography.ui(11.5))
                .foregroundStyle(Theme.Color.textMuted)

            WarmSlider(strength: warmestBinding)

            Toggle("Expanded range — reach candle & ember (below 1900 K)", isOn: $expanded)
                .toggleStyle(.switch)
                .tint(Theme.Color.accent)
                .onChange(of: expanded) { _, on in
                    // Leaving expanded range: pull a deeper-than-everyday pick back up to the 1900K cap.
                    if !on, model.state.warmestPoint.value < Kelvin.everydayWarmest.value {
                        model.setWarmestPoint(Kelvin.everydayWarmest)
                    }
                }

            if expanded {
                Text("Below ~1900 K, blue light is already fully removed — going warmer mainly removes green: deeper and more candle-like, but harder to read, with little additional circadian benefit. (See Brown et al. 2022; CIE S 026.)")
                    .font(Theme.Typography.ui(11))
                    .foregroundStyle(Theme.Color.textFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            // Single source of truth: a sub-1900K ceiling means the expanded range is in use.
            expanded = model.state.warmestPoint.value < Kelvin.everydayWarmest.value
        }
    }

    /// Maps the WarmSlider's 0…1 strength onto [warmBound … coolBound] Kelvin (1 = warmest).
    private var warmestBinding: Binding<Double> {
        Binding(
            get: {
                let span = Double(coolBound - warmBound)
                guard span > 0 else { return 0 }
                let s = (Double(coolBound) - Double(model.state.warmestPoint.value)) / span
                return min(1, max(0, s))
            },
            set: { s in
                let span = Double(coolBound - warmBound)
                let k = Int((Double(coolBound) - s * span).rounded())
                model.setWarmestPoint(Kelvin(k))
            }
        )
    }
}

// MARK: - Privacy

private struct PrivacyTab: View {
    @Bindable var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TabHeader(title: "Privacy", subtitle: "Local-first. No account, no telemetry by default.")
            privacyPoint("No Accessibility permission", "Hold-to-reveal uses a Carbon global hotkey — no Accessibility access required.")
            privacyPoint("No Screen Recording", "Display capabilities are classified, never measured by screen capture.")
            privacyPoint("No Sandbox surprises", "Warmth applies locally; nothing about your displays leaves the machine.")
            privacyPoint("Manual reveal during captures", "Auto screenshot/recording suspend is out of scope for v1.0; reveal true colour manually with the hotkey.")
        }
    }

    private func privacyPoint(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: "checkmark.shield")
                .font(Theme.Typography.ui(13, weight: .medium))
                .foregroundStyle(Theme.Color.textPrimary)
            Text(body)
                .font(Theme.Typography.ui(11.5))
                .foregroundStyle(Theme.Color.textMuted)
                .padding(.leading, 24)
        }
    }
}

// MARK: - About

private struct AboutTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header — the real app icon (not the menu-bar glyph) + wordmark.
            HStack(spacing: 12) {
                AppIconView().frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Abendrot")
                        .font(Theme.Typography.serif(24))
                        .foregroundStyle(Theme.Color.textPrimary)
                    Text("Soften into the evening.")
                        .font(Theme.Typography.ui(12.5))
                        .foregroundStyle(Theme.Color.textMuted)
                }
            }

            // Mission — what it is, framed as the input it changes (no promised sleep outcome, §13).
            Text("Abendrot warms your screen with the evening — on every display, built-in and external — so your screen gives off less blue light as the day winds down. It’s free, open source, and runs entirely on your Mac: no account, no telemetry.")
                .font(Theme.Typography.ui(12.5))
                .foregroundStyle(Theme.Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            // What makes it different (the marketing angle).
            VStack(alignment: .leading, spacing: 8) {
                aboutPoint("Every display", "Real warmth on built-in and external monitors — including buttonless Apple displays — where Night Shift and f.lux quietly give up.")
                aboutPoint("Free & open source", "MIT-licensed. Read every line of the engine that touches your screen.")
                aboutPoint("Private by default", "No account, no tracking, no telemetry. Nothing about your displays leaves your Mac.")
                aboutPoint("Built for the newest Macs", "Uses the best warming method each display supports — and says so plainly when macOS only allows a tint, not true warming.")
            }

            DividerLine()

            // The science — hedged, general-wellness only (§13 binding; grounded in evidence-base.md).
            VStack(alignment: .leading, spacing: 6) {
                Text("The science")
                    .font(Theme.Typography.ui(13, weight: .semibold))
                    .foregroundStyle(Theme.Color.textPrimary)
                Text("Your body clock is set mainly by short-wavelength blue light (around 480 nm), sensed by a dedicated set of cells in the eye. Abendrot warms the display by removing that blue first — reaching zero blue output at its everyday warmest (~1900 K). For the calmest evening light, pair warming with lower screen brightness: the effect is driven by intensity as much as colour, and people’s sensitivity to evening light varies widely.")
                    .font(Theme.Typography.ui(11.5))
                    .foregroundStyle(Theme.Color.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Abendrot reduces your blue-light exposure at night — a small, sensible nudge toward healthier evening light habits. It’s a general-wellness tool, not a medical device, and not a sleep treatment. The peer-reviewed research behind it is open for anyone to read.")
                    .font(Theme.Typography.ui(11))
                    .foregroundStyle(Theme.Color.textFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func aboutPoint(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(Theme.Typography.ui(12.5, weight: .medium))
                .foregroundStyle(Theme.Color.textPrimary)
            Text(body)
                .font(Theme.Typography.ui(11))
                .foregroundStyle(Theme.Color.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Preview

#Preview("Settings") {
    SettingsView(model: AppModel(previewState: MockWarmthState.warming))
}
