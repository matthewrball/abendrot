import SwiftUI
import ServiceManagement
import WarmthKit

struct GeneralTab: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("softConfirmationTone") private var softTone = true
    @State private var launchAtLoginError: String?
    @State private var showsMaximumWarmthFocusCue = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            TabHeader(title: "General", subtitle: "How Abendrot behaves day to day.")

            // The primary control, first and consistent with the menu-bar popover: the
            // master toggle + the SAME liquid-glass WarmSlider. In Sunset this edits the evening
            // maximum; the menu bar only shows the live, clock-owned warmth.
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Warm my displays")
                        .font(Theme.Typography.ui(13, weight: .semibold))
                        .foregroundStyle(Theme.Color.textPrimary)
                    Spacer()
                    WarmthPowerSwitch(isOn: enabledBinding, accessibilityLabel: "Warm my displays")
                }
                if model.state.isEnabled {
                    WarmSlider(
                        strength: Binding(
                            get: { model.state.globalWarmth.strength },
                            set: { model.setGlobalWarmth($0) }
                        ),
                        model: model,
                        headerTitle: ScheduleModeOption(model.state.scheduleMode) == .alwaysOn ? "Warmth" : "Maximum warmth",
                        kelvin: model.globalKelvin,
                        cozy: isCozy
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                }
            }
            .animation(Theme.Motion.controlReveal(reduceMotion: reduceMotion), value: model.state.isEnabled)
            .animation(Theme.Motion.warm(reduceMotion: reduceMotion), value: ScheduleModeOption(model.state.scheduleMode))
            .background(maximumWarmthFocusCueFill)
            .overlay(maximumWarmthFocusCueStroke)
            .task(id: model.maximumWarmthFocusRequest) {
                guard let request = model.maximumWarmthFocusRequest else { return }
                await runMaximumWarmthFocusCue(request)
            }

            // Schedule MODE lives here: the menu-bar popover groups on/off + warmth + mode as
            // one "how it warms" unit, so General is its full desktop twin. The Mode selector and Location
            // now hide with the master toggle.
            VStack(alignment: .leading, spacing: 12) {
                // Mode selector hides when warming is off (popover parity — on/off + warmth + mode are one
                // unit). Location also hides when warming is off.
                if model.state.isEnabled {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel("Mode")
                        ModeControl(
                            selection: Binding(
                                get: { ScheduleModeOption(model.state.scheduleMode) },
                                set: { model.setScheduleMode($0.toScheduleMode()) }
                            ),
                            onChange: { _ in }
                        )
                        // Shared `ScheduleModeOption.subtitle` — the same one-liner as the popover.
                        Text(ScheduleModeOption(model.state.scheduleMode).subtitle)
                            .font(Theme.Typography.ui(12))
                            .foregroundStyle(Theme.Color.textMuted)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                }

                // Location only matters for Sunset (it estimates your sunset time); hidden for Manual.
                // Hides when warming is off.
                if model.state.isEnabled && ScheduleModeOption(model.state.scheduleMode) == .followSunset {
                    VStack(alignment: .leading, spacing: 7) {
                        SectionLabel("Location")
                        Text("Used to estimate your sunset. No location permission required.")
                            .font(Theme.Typography.ui(11.5))
                            .foregroundStyle(Theme.Color.textMuted)
                        CityAutocomplete(model: model, opensUpward: true)
                            .frame(width: 300, alignment: .leading)
                        Text(model.todaysSunsetReadout)
                            .font(Theme.Typography.ui(11))
                            .foregroundStyle(Theme.Color.textFaint)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                }
            }
            .animation(Theme.Motion.warm(reduceMotion: reduceMotion), value: ScheduleModeOption(model.state.scheduleMode))
            .animation(Theme.Motion.controlReveal(reduceMotion: reduceMotion), value: model.state.isEnabled)

            DividerLine()

            // Far-right switches (label left, control trailing) to match the master toggle and the
            // standard macOS settings layout .
            HStack {
                Text("Launch at login").font(Theme.Typography.ui(13))
                Spacer()
                Toggle("", isOn: launchAtLoginBinding)
                    .labelsHidden()
            }
            if let launchAtLoginError {
                Text(launchAtLoginError)
                    .font(Theme.Typography.ui(11.5))
                    .foregroundStyle(Theme.Color.textFaint)
            }
            // Show-in-menu-bar with clear re-entry.
            HStack {
                Text("Show icon in menu bar").font(Theme.Typography.ui(13))
                Spacer()
                Toggle("", isOn: showInMenuBarBinding).labelsHidden()
            }

            HStack {
                Text("Sounds").font(Theme.Typography.ui(13))
                Spacer()
                Toggle("", isOn: soundsBinding).labelsHidden()
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
            model.playSoftToggleTone(on: enable)
        } catch {
            // Roll the toggle back to the system's actual state and explain why.
            launchAtLogin = SMAppService.mainApp.status == .enabled
            launchAtLoginError = "Couldn't \(enable ? "enable" : "disable") launch at login: \(error.localizedDescription)"
        }
    }

    private var isCozy: Bool {
        model.state.warmestPoint.value < Kelvin.everydayWarmest.value
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { model.state.isEnabled },
            set: { model.setEnabled($0) }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(get: { launchAtLogin }, set: { newValue in
            guard newValue != launchAtLogin else { return }
            launchAtLogin = newValue
            setLaunchAtLogin(newValue)
        })
    }

    private var showInMenuBarBinding: Binding<Bool> {
        Binding(get: { model.showInMenuBar }, set: { newValue in
            guard newValue != model.showInMenuBar else { return }
            model.showInMenuBar = newValue
            model.playSoftToggleTone(on: newValue)
        })
    }

    private var soundsBinding: Binding<Bool> {
        Binding(get: { softTone }, set: { newValue in
            guard newValue != softTone else { return }
            if !newValue { model.playSoftToggleTone(on: false) }
            softTone = newValue
            if newValue { model.playSoftToggleTone(on: true) }
        })
    }

    private var maximumWarmthFocusCueFill: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.control + 4, style: .continuous)
            .fill(Theme.Color.accent.opacity(0.12))
            .opacity(showsMaximumWarmthFocusCue ? 1 : 0)
            .padding(-10)
    }

    private var maximumWarmthFocusCueStroke: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.control + 4, style: .continuous)
            .stroke(Theme.Color.accent.opacity(0.7), lineWidth: 1)
            .shadow(color: Theme.Color.accent.opacity(0.45), radius: 12)
            .opacity(showsMaximumWarmthFocusCue ? 1 : 0)
            .padding(-10)
    }

    @MainActor
    private func runMaximumWarmthFocusCue(_ request: UUID) async {
        if showsMaximumWarmthFocusCue {
            withAnimation(nil) { showsMaximumWarmthFocusCue = false }
            await Task.yield()
        }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.18)) {
            showsMaximumWarmthFocusCue = true
        }
        do {
            try await Task.sleep(nanoseconds: 700_000_000)
        } catch {
            return
        }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.42)) {
            showsMaximumWarmthFocusCue = false
        }
        do {
            try await Task.sleep(nanoseconds: reduceMotion ? 0 : 420_000_000)
        } catch {
            return
        }
        if model.maximumWarmthFocusRequest == request {
            model.maximumWarmthFocusRequest = nil
        }
    }
}
