import SwiftUI
import WarmthKit

// MARK: - PopoverView
//
// The everyday menu-bar surface (plan §4.1, §4.4, §21.3). Left-click shows the simple
// controls; ⌥-click / right-click expands the SAME glass to the advanced power rows
// (the "liquid expansion" of §21.3 — the popover grows, it does not open a new window).
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
                DisplayRow(display: display)
            }
        }
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

            Spacer()

            // Subtle reveal hint (plan §4.1 footer).
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
