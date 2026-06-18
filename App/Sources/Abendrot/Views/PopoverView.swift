import SwiftUI
import AppKit
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

            // Upfront honesty: if the whole Mac can't truly warm anything, say so. (§25.J DRAFT)
            if allDisplaysTintOnly {
                incompatibilityBanner
                    .padding(.bottom, 16)
            }

            masterToggle
                .padding(.bottom, 16)

            WarmSlider(strength: globalWarmthBinding)
                .padding(.bottom, 14)

            // The schedule mode control AND its leading divider are only meaningful while warming is
            // on — the master toggle owns on/off. The whole group hides (and re-reveals) with a soft
            // blur-scale-fade, so the divider disappears with it instead of leaving two stacked
            // dividers with a gap when off.
            if model.state.isEnabled {
                VStack(alignment: .leading, spacing: 0) {
                    DividerLine().padding(.bottom, 14)
                    ModeControl(selection: modeBinding) { option in
                        model.setScheduleMode(option.toScheduleMode())
                    }
                    .padding(.bottom, 16)
                }
                .transition(.softReveal)
            }

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
            appIcon
                .frame(width: 22, height: 22)
            Text("Abendrot")
                .font(Theme.Typography.serif(15))
                .foregroundStyle(Theme.Color.textPrimary)
            Spacer()
            statusReadout
        }
    }

    /// The real app icon (the sunset squircle), so the dropdown header matches the Dock/Finder icon
    /// instead of the simplified menu-bar glyph. Falls back to the vector glyph if the icon image
    /// can't be loaded. (The menu-bar status item keeps the template glyph — a full-colour squircle
    /// there would break the monochrome menu-bar convention.)
    @ViewBuilder private var appIcon: some View {
        if let icon = NSImage(named: NSImage.applicationIconName) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        } else {
            SunsetArcGlyph()
        }
    }

    /// The top-right status readout. In the warming phase the Kelvin number animates with a
    /// sliding-digit transition (`.numericText`) as the warmth changes — lightweight (one GPU text
    /// transition, no per-digit views) and it honours Reduce Motion (the number just snaps). Other
    /// phases ("Off" / "True color" / "Idle") are plain text.
    @ViewBuilder private var statusReadout: some View {
        Group {
            if model.statusPhase == .warming {
                let kelvin = model.globalKelvin.value
                HStack(spacing: 4) {
                    Text("Warming ·")
                    Text("\(kelvin)K")
                        .contentTransition(.numericText(value: Double(kelvin)))
                        // Slides the changed digits whenever the Kelvin changes — live during a
                        // slider drag included. Reduce Motion → nil (the number just snaps).
                        .animation(Theme.Motion.warm(reduceMotion: reduceMotion), value: kelvin)
                }
            } else {
                Text(model.statusSummary)
            }
        }
        .font(Theme.Typography.ui(11.5))
        .monospacedDigit()
        .foregroundStyle(Theme.Color.accentHighlight)
    }

    // MARK: Master toggle

    private var masterToggle: some View {
        HStack {
            // Singular when there's a single screen (no external monitors), plural otherwise.
            Text(model.state.displays.count == 1 ? "Warm my display" : "Warm my displays")
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

    /// Per-display rows in the simple view, shown ONLY with 2+ displays — a lone screen needs no
    /// row (nothing to disambiguate, and its method badge is just noise here). Power users still get
    /// per-display controls in the advanced (⌥-click) expansion, and the app-level "can only tint"
    /// banner above still fires for a single incompatible display.
    @ViewBuilder private var displaySection: some View {
        if model.state.displays.count > 1 {
            VStack(spacing: 8) {
                ForEach(model.state.displays) { display in
                    DisplayRow(display: display, tintOnly: isTintOnly(display))
                }
            }
        }
    }

    // MARK: Incompatibility ("can only be tinted") detection — §25.J (DRAFT)

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
                // so the banner is legible. (§25.J — readability fix.)
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
            // neutral-resets every display before exit (contract §9). An LSUIElement agent
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
        Binding(
            get: { model.state.isEnabled },
            // Animate so the schedule mode control reveals/hides with the soft spring (the optimistic
            // `state.isEnabled` flips synchronously inside this transaction → the transition plays).
            set: { newValue in
                withAnimation(Theme.Motion.controlReveal(reduceMotion: reduceMotion)) {
                    model.setEnabled(newValue)
                }
            }
        )
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

    /// A soft, premium appear/disappear: blur + slight scale-from-top + fade. Used for the schedule
    /// mode control revealing when warming is enabled.
    static var softReveal: AnyTransition {
        .modifier(active: SoftRevealModifier(visible: false), identity: SoftRevealModifier(visible: true))
    }
}

/// The active/identity states `softReveal` interpolates between (blur out + scale down + fade).
private struct SoftRevealModifier: ViewModifier {
    let visible: Bool
    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .blur(radius: visible ? 0 : 6)
            .scaleEffect(visible ? 1 : 0.95, anchor: .top)
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
