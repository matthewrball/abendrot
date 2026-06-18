import SwiftUI
import ServiceManagement
import WarmthKit

// MARK: - SettingsTab

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, schedule, displays, shortcuts, advanced, privacy, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .schedule: return "Schedule"
        case .displays: return "Displays"
        case .shortcuts: return "Shortcuts"
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
        case .shortcuts: return "keyboard"
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
        case .shortcuts: ShortcutsTab()
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
                    ),
                    kelvin: nil
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
            Text("Follow sunset mirrors your system Night Shift schedule when available, and falls back to a built-in solar calculation otherwise. Abendrot never writes to Night Shift.")
                .font(Theme.Typography.ui(12))
                .foregroundStyle(Theme.Color.textMuted)
            // TODO(settings): custom from/to + warmth target editor for .custom schedules.
            Text("Custom schedule editor — coming in a later milestone.")
                .font(Theme.Typography.ui(11.5))
                .foregroundStyle(Theme.Color.textFaint)
        }
    }
}

// MARK: - Displays

private struct DisplaysTab: View {
    @Bindable var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            TabHeader(title: "Displays", subtitle: "Each connected display and how it's warmed.")
            ForEach(model.state.displays) { display in
                AdvancedDisplayRowProxy(display: display, model: model)
            }
            DividerLine()
            Button(role: .destructive) {
                model.restoreAllDisplays()
            } label: {
                Label("Restore all displays to neutral", systemImage: "arrow.counterclockwise")
            }
            Text("Emergency reset: returns every display to true colour via every layer. Always available.")
                .font(Theme.Typography.ui(11.5))
                .foregroundStyle(Theme.Color.textFaint)
        }
    }
}

/// Reuses the advanced per-display row idiom inside Settings → Displays.
private struct AdvancedDisplayRowProxy: View {
    let display: DisplayState
    @Bindable var model: AppModel
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(display.name).font(Theme.Typography.ui(13))
                    .foregroundStyle(Theme.Color.textPrimary)
                Text("Recommended: \(display.capabilities.recommendedMethod.badge)")
                    .font(Theme.Typography.ui(11))
                    .foregroundStyle(Theme.Color.textFaint)
            }
            Spacer()
            MethodBadge(method: display.appliedMethod)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Shortcuts

private struct ShortcutsTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            TabHeader(title: "Shortcuts", subtitle: "Reveal True Color and other hotkeys.")
            HStack {
                Text("Reveal True Color").font(Theme.Typography.ui(13.5))
                Spacer()
                Text("⌥⌘T")
                    .font(Theme.Typography.ui(13, weight: .medium))
                    .foregroundStyle(Theme.Color.accentHighlight)
            }
            // TODO(settings): embed KeyboardShortcuts.Recorder + a Hold/Toggle mode picker.
            Text("Hold to reveal true colour; release to ease warmth back. Switch to Toggle, or rebind, here — recorder lands in a later milestone.")
                .font(Theme.Typography.ui(12))
                .foregroundStyle(Theme.Color.textMuted)
        }
    }
}

// MARK: - Advanced

private struct AdvancedTab: View {
    @Bindable var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            TabHeader(title: "Advanced", subtitle: "Power controls and the private-API kill switch.")

            MaximumWarmthControl(model: model)
            DividerLine()

            Toggle("Enable private-API paths (DDC + Night Shift follow)", isOn: Binding(
                get: { model.state.privateAPIsEnabled },
                set: { model.setPrivateAPIsEnabled($0) }
            ))
            .toggleStyle(.switch)
            .tint(Theme.Color.accent)
            Text("Off = overlay-only. Abendrot drops the hardware-DDC and Night-Shift-follow paths and warms every display via the universal Metal overlay.")
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

            WarmSlider(strength: warmestBinding, kelvin: nil)

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
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                SunsetArcGlyph().frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Abendrot")
                        .font(Theme.Typography.serif(22))
                        .foregroundStyle(Theme.Color.textPrimary)
                    Text("Soften into the evening.")
                        .font(Theme.Typography.ui(12.5))
                        .foregroundStyle(Theme.Color.textMuted)
                }
            }
            DividerLine()
            // TODO(settings): "The Science" easter-egg panel (plan §4.7) — cited,
            // general-wellness framing only.
            Text("The Science — a tasteful, cited panel about evening light — lands in a later milestone.")
                .font(Theme.Typography.ui(11.5))
                .foregroundStyle(Theme.Color.textFaint)
        }
    }
}

// MARK: - Preview

#Preview("Settings") {
    SettingsView(model: AppModel(previewState: MockWarmthState.warming))
}
