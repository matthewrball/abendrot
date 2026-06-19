import SwiftUI
import AppKit
import WarmthKit

// MARK: - PopoverView
//
// The everyday menu-bar surface (plan §4.1, §4.4, §21.3). Left-click shows the simple
// controls; ⌥-click / right-click expands the SAME glass to the advanced power rows
// (the "liquid expansion" of §21.3 — the popover grows, it does not open a new window).
//
// Simple view (while warming): the global warmth slider, then the schedule Mode control —
// both reveal/hide with the master toggle. Per-display "Override" rows now live in the
// advanced (⌥-click) expansion, not here. The app-level "can only tint" banner stays at the
// top of the simple view.
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

            // Upfront honesty: if the whole Mac can't truly warm anything, say so. (§25.J)
            if allDisplaysTintOnly {
                IncompatibilityNotice()
                    .padding(.bottom, 16)
            }

            masterToggle
                // When collapsed, zero bottom padding so the lone toggle sits centered between the
                // header and footer dividers (each contributes 14pt) instead of bottom-heavy.
                .padding(.bottom, model.state.isEnabled ? 16 : 0)

            // The warmth slider + the schedule Mode control are only meaningful while warming is on
            // — the master toggle owns on/off — so they hide and re-reveal together with a soft
            // scale-fade. (Per-display "Override" rows live in the Advanced section now.)
            if model.state.isEnabled {
                VStack(alignment: .leading, spacing: 0) {
                    WarmSlider(strength: globalWarmthBinding, kelvin: model.globalKelvin)
                        .padding(.bottom, 16)
                    modeSection
                }
                .transition(.softReveal)
            }

            // Advanced "liquid expansion" — the glass grows to hold power rows.
            if model.isAdvancedExpanded {
                AdvancedExpansion(model: model)
                    // Match the breathing room the collapsed state has above the footer divider, so
                    // the gap above the advanced section's first divider isn't tight.
                    .padding(.top, 14)
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
            AppIconView()
                .frame(width: 22, height: 22)
            Text("Abendrot")
                .font(Theme.Typography.serif(15))
                .foregroundStyle(Theme.Color.textPrimary)
            Spacer()
            // Settings (top-right).
            Button {
                openSettings()
            } label: {
                Image(systemName: "gearshape")
                    .foregroundStyle(Theme.Color.textMuted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
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

    // MARK: Schedule mode

    /// The global schedule Mode, shown in the simple view directly under the warmth slider. Reveals
    /// and hides with the master toggle (it lives inside the `isEnabled` `.softReveal` group).
    /// Defaults to Sunset until the user picks here. Per-display "Override" rows live in the advanced
    /// (⌥-click) expansion now, not in the simple view.
    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mode")
                .font(Theme.Typography.ui(13, weight: .medium))
                .foregroundStyle(Theme.Color.textMuted)
            ModeControl(
                selection: Binding(
                    get: { ScheduleModeOption(model.state.scheduleMode) },
                    set: { model.setScheduleMode($0.toScheduleMode()) }
                ),
                onChange: { _ in }
            )
        }
    }

    // MARK: Incompatibility ("can only be tinted") detection — §25.J (DRAFT)

    /// True when there is ≥1 display and EVERY connected display can only be tinted — the whole
    /// Mac/OS can't truly warm anything, so we say so up front with a banner. The per-display
    /// tint-only test (`model.isTintOnly`) is shared with the moved per-display rows in the advanced
    /// expansion (DRY — single source of truth on `AppModel`).
    private var allDisplaysTintOnly: Bool {
        let displays = model.state.displays
        return !displays.isEmpty && displays.allSatisfy(model.isTintOnly)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 12) {
            // Quit — the ⎋ (escape) glyph, not a power symbol (which reads like an on/off switch and
            // gets confused with warming on/off). Routes through NSApp.terminate →
            // applicationShouldTerminate, which neutral-resets every display before exit (contract
            // §9). LSUIElement agents have no app menu, so this is the Quit affordance; ⌘Q also works.
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "escape")
                    .foregroundStyle(Theme.Color.textMuted)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q", modifiers: .command)
            .help("Quit Abendrot")
            .accessibilityLabel("Quit Abendrot")

            Spacer()

            // Subtle reveal hint — only while warming is on (reveal does nothing when off).
            if model.state.isEnabled {
                Text("Reveal True Color: ⌥⌘T (hold)")
                    .font(Theme.Typography.ui(10.5))
                    .foregroundStyle(Theme.Color.textFaint)
            }

            Spacer()

            // Advanced disclosure (bottom-right) — a chevron that rotates 180° when open.
            Button {
                withAnimation(Theme.Motion.warm(reduceMotion: reduceMotion)) {
                    model.isAdvancedExpanded.toggle()
                }
            } label: {
                Image(systemName: "chevron.down")
                    .rotationEffect(.degrees(model.isAdvancedExpanded ? 180 : 0))
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

    /// A soft, premium appear/disappear: a gentle scale-from-top + fade, used for the warmth group
    /// (slider + per-display rows) dropping in/out when warming toggles.
    static var softReveal: AnyTransition {
        .modifier(active: SoftRevealModifier(visible: false), identity: SoftRevealModifier(visible: true))
    }
}

/// The active/identity states `softReveal` interpolates between: a small scale-from-top + fade.
/// Deliberately NO blur — animating blur radius per frame over the slider + display rows is the main
/// source of jank; opacity + a light transform is GPU-cheap and reads as a smooth drop-down.
private struct SoftRevealModifier: ViewModifier {
    let visible: Bool
    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .scaleEffect(visible ? 1 : 0.98, anchor: .top)
    }
}

// MARK: - IncompatibilityNotice (§25.J)

/// The app-level "this Mac can only tint" notice, shown when EVERY connected display is tint-only.
/// Names the user's actual chip + macOS version (so the limitation is concrete, not vague) and offers
/// a tappable "Why?" that reveals a plain-language, non-medical explanation. Dark ink on the amber
/// fill for contrast. DRAFT copy/visual — pending founder design direction.
private struct IncompatibilityNotice: View {
    @State private var showWhy = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let ink = Theme.Color.groundIndigo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(Theme.Typography.ui(12))
                    .foregroundStyle(Theme.Color.accentPress)
                VStack(alignment: .leading, spacing: 6) {
                    Text("True warming isn’t available on this Mac, so your displays are being tinted rather than truly warmed — a known limitation on some Apple-silicon chips and macOS versions.")
                        .font(Theme.Typography.ui(11))
                        .foregroundStyle(ink)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        Text(SystemInfo.summary)
                            .font(Theme.Typography.ui(10, weight: .medium))
                            .foregroundStyle(ink.opacity(0.75))
                        Spacer()
                        Button {
                            withAnimation(Theme.Motion.controlReveal(reduceMotion: reduceMotion)) {
                                showWhy.toggle()
                            }
                        } label: {
                            Text(showWhy ? "Hide" : "Why?")
                                .font(Theme.Typography.ui(10, weight: .semibold))
                                .foregroundStyle(ink)
                                .underline()
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(showWhy ? "Hide explanation" : "Why is true warming unavailable?")
                    }
                }
            }

            if showWhy {
                Text("Some Apple-silicon Macs on newer macOS versions don’t let apps shift the display’s colour at the system level, so here Abendrot can only lay a warm tint over the screen — it can’t remove blue light the way it does on other Macs. Nothing is broken; it’s a macOS limitation. An external monitor with its own colour controls can still be truly warmed via Hardware control (Settings → Displays).")
                    .font(Theme.Typography.ui(10.5))
                    .foregroundStyle(ink.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Color.accentHi, in: RoundedRectangle(cornerRadius: Theme.Radius.control - 1, style: .continuous))
        .animation(Theme.Motion.controlReveal(reduceMotion: reduceMotion), value: showWhy)
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
