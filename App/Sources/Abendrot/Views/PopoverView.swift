import SwiftUI
import AppKit
import WarmthKit

// MARK: - PopoverView
//
// The everyday menu-bar surface. Left-click shows the simple
// controls; ⌥-click / right-click expands the SAME glass to the advanced power rows
// (the "liquid expansion" — the popover grows, it does not open a new window).
//
// Renders entirely from `AppModel.state` (a contract `WarmthState`). All mutations go
// back through `AppModel` → `WarmthEngine`.
struct PopoverView: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            DividerLine().padding(.vertical, 14)

            // Upfront honesty: if the whole Mac can't truly warm anything, say so.
            if allDisplaysTintOnly {
                incompatibilityBanner
                    .padding(.bottom, 16)
            }

            masterToggle
                .padding(.bottom, 16)

            WarmSlider(
                strength: globalWarmthBinding,
                kelvin: model.globalKelvin
            )
            .padding(.bottom, 14)

            DividerLine().padding(.bottom, 14)

            ModeControl(selection: modeBinding) { option in
                model.setScheduleMode(option.toScheduleMode())
            }
            .padding(.bottom, 16)

            displaySection

            // Advanced "liquid expansion" — the glass grows to hold power rows.
            if model.isAdvancedExpanded {
                AdvancedExpansion(model: model)
                    .padding(.top, 4)
                    .transition(.advancedExpansion)
            }

            DividerLine().padding(.vertical, 14)
            footer
        }
        .padding(20)
        .frame(width: 330)
        .animation(Theme.Motion.warm(reduceMotion: reduceMotion), value: model.isAdvancedExpanded)
        .glassSurface(.popover)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            SunsetArcGlyph()
                .frame(width: 22, height: 22)
            Text("Abendrot")
                .font(Theme.Typography.serif(15))
                .foregroundStyle(Theme.Color.textPrimary)
            Spacer()
            Text(model.statusSummary)
                .font(Theme.Typography.ui(11.5))
                .monospacedDigit()
                .foregroundStyle(Theme.Color.accentHighlight)
        }
    }

    // MARK: Master toggle

    private var masterToggle: some View {
        HStack {
            Text("Warm my displays")
                .font(Theme.Typography.ui(13, weight: .semibold))
                .foregroundStyle(Theme.Color.textPrimary)
            Spacer()
            Toggle("", isOn: enabledBinding)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Theme.Color.accent)
        }
    }

    // MARK: Displays

    private var displaySection: some View {
        VStack(spacing: 8) {
            ForEach(model.state.displays) { display in
                DisplayRow(display: display, tintOnly: isTintOnly(display))
            }
        }
    }

    // MARK: Incompatibility ("can only be tinted") detection

    /// A display can only be TINTED when no true-warm path is available to it: gamma is not
    /// supported on this chip/OS (or private APIs are off) AND it is not DDC-capable. Capability-
    /// based, so it reads honestly even before warming is enabled.
    private func isTintOnly(_ display: DisplayState) -> Bool {
        let priv = model.state.privateAPIsEnabled
        let gammaPossible = priv && isSupported(display.capabilities.gamma)
        let ddcPossible = priv && isSupported(display.capabilities.hardware)
        return !(gammaPossible || ddcPossible)
    }

    private func isSupported<T>(_ cap: Capability<T>) -> Bool {
        if case .supported = cap { return true }
        return false
    }

    /// True when there is ≥1 display and EVERY connected display can only be tinted — the whole
    /// Mac/OS can't truly warm anything, so we say so up front with a banner.
    private var allDisplaysTintOnly: Bool {
        let displays = model.state.displays
        return !displays.isEmpty && displays.allSatisfy(isTintOnly)
    }

    private var incompatibilityBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(Theme.Typography.ui(12))
                .foregroundStyle(Theme.Color.accentPress)
            Text("True warming isn’t available on this Mac, so your displays are being tinted rather than truly warmed — a known limitation on some Apple-silicon chips and macOS versions.")
                .font(Theme.Typography.ui(11))
                // Dark ink on the light-amber fill (same contrast convention as the method badges),
                // so the banner is legible.
                .foregroundStyle(Theme.Color.groundIndigo)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Color.accentHi, in: RoundedRectangle(cornerRadius: Theme.Radius.control - 1, style: .continuous))
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button {
                openSettings()
            } label: {
                Image(systemName: "gearshape")
                    .foregroundStyle(Theme.Color.textMuted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")

            // Quit. Routes through NSApp.terminate → applicationShouldTerminate, which
            // neutral-resets every display before exit. An LSUIElement agent
            // has no app menu, so this is the user's Quit affordance; ⌘Q also works when the
            // popover is focused.
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .foregroundStyle(Theme.Color.textMuted)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q", modifiers: .command)
            .help("Quit Abendrot")
            .accessibilityLabel("Quit Abendrot")

            Spacer()

            // Subtle reveal hint.
            Text("Reveal True Color: ⌥⌘T (hold)")
                .font(Theme.Typography.ui(10.5))
                .foregroundStyle(Theme.Color.textFaint)

            Spacer()

            Button {
                withAnimation(Theme.Motion.warm(reduceMotion: reduceMotion)) {
                    model.isAdvancedExpanded.toggle()
                }
            } label: {
                Image(systemName: model.isAdvancedExpanded ? "chevron.up" : "slider.horizontal.3")
                    .foregroundStyle(Theme.Color.textMuted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.isAdvancedExpanded ? "Collapse advanced" : "Show advanced")
        }
    }

    // MARK: Bindings (view ↔ AppModel intents)

    private var enabledBinding: Binding<Bool> {
        Binding(get: { model.state.isEnabled }, set: { model.setEnabled($0) })
    }

    private var globalWarmthBinding: Binding<Double> {
        Binding(get: { model.state.globalWarmth.strength }, set: { model.setGlobalWarmth($0) })
    }

    private var modeBinding: Binding<ScheduleModeOption> {
        Binding(
            get: { ScheduleModeOption(model.state.scheduleMode) },
            set: { model.setScheduleMode($0.toScheduleMode()) }
        )
    }
}

// MARK: - Advanced expansion transition

private extension AnyTransition {
    /// The glass "grows": new rows fade up + expand from the top.
    static var advancedExpansion: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .opacity
        )
    }
}

// MARK: - Previews

#Preview("Simple — warming") {
    PopoverView(model: AppModel(previewState: MockWarmthState.warming))
        .padding(40)
        .background(Theme.Color.groundPlum)
}

#Preview("Simple — idle (fresh install)") {
    PopoverView(model: AppModel(previewState: MockWarmthState.idleSingleDisplay))
        .padding(40)
        .background(Theme.Color.groundPlum)
}
