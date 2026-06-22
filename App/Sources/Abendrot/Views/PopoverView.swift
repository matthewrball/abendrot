import SwiftUI
import AppKit
import WarmthKit

// MARK: - PopoverView
//
// The everyday menu-bar surface. Left-click shows the simple
// controls; ⌥-click / right-click expands the SAME glass to the advanced power rows
// (the "liquid expansion" — the popover grows, it does not open a new window).
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            DividerLine().padding(.vertical, 14)

            // Upfront honesty: if the whole Mac can't truly warm anything, say so.
            if allDisplaysTintOnly {
                IncompatibilityNotice()
                    .padding(.bottom, 16)
            }

            masterToggle
                // When collapsed, zero bottom padding so the lone toggle sits centered between the
                // header and footer dividers (each contributes 14pt) instead of bottom-heavy.
                .padding(.bottom, model.state.isEnabled ? 16 : 0)

            // The warmth readout + the schedule Mode control are only meaningful while warming is on
            // the master toggle owns on/off — so they hide and re-reveal together with a soft
            // scale-fade. (Per-display "Override" rows live in the Advanced section now.)
            if model.state.isEnabled {
                let locked = model.isWarmthLockedInSunset
                VStack(alignment: .leading, spacing: 0) {
                    // In Sunset mode the readout stays LIVE but the slider disappears: the clock owns
                    // the current warmth, and Settings owns the maximum. Always-on keeps it editable.
                    WarmSlider(
                        strength: locked ? sunsetLiveBinding : globalWarmthBinding,
                        model: model,
                        kelvin: locked ? model.liveKelvin : model.globalKelvin,
                        showsTrack: !locked,
                        cozy: isCozy
                    )
                    .zIndex(1)
                    // Always-on's slider path is 7pt shorter than Sunset's caption path; reserve it here
                    // so Mode, Cozy mode, and the footer share one y-position across modes.
                    .padding(.bottom, locked ? 0 : 7)
                    if locked {
                        sunsetLockCaption
                            .padding(.top, 10)
                            .transition(.opacity)
                    }
                    modeSection
                        .padding(.top, 16)
                    // Cozy mode (the maximum-warmth control) right under Mode — the bare card, no section
                    // header / science note (those live in Settings). Shares `model.setCozy`, so it can
                    // never disagree with the Settings card, onboarding, or the `abendrot cozy` CLI.
                    CozyModeControl(model: model, showsSectionLabel: false, showsExplanation: false)
                        .padding(.top, 16)
                }
                .transition(.softReveal)
                // Caption crossfades while the popover shell keeps a steady natural height.
                .animation(Theme.Motion.controlReveal(reduceMotion: reduceMotion), value: locked)
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
        // Big corner hit targets: the whole TOP-RIGHT corner opens Settings; the whole
        // BOTTOM-RIGHT corner toggles the advanced expansion. Overlays pinned to the card's actual
        // corners (added after `.padding(20)`, so they reach the real edges, over the padding) and they
        // keep the header/footer rows at their natural height. The visible glyphs live in `header`/
        // `footer`. The Quit ⎋ (bottom-LEFT) is deliberately NOT enlarged — an intentional, hard-to-undo
        // action we must not invite by accident.
        .overlay(alignment: .topTrailing) {
            Button { SettingsWindowController.show(model: model, tab: .general) } label: {
                Color.clear.frame(width: 96, height: 52).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .overlay(alignment: .bottomTrailing) {
            Button {
                withAnimation(Theme.Motion.warm(reduceMotion: reduceMotion)) {
                    model.toggleAdvanced()
                }
            } label: {
                Color.clear.frame(width: 104, height: 56).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.isAdvancedExpanded ? "Collapse advanced" : "Show advanced")
        }
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
            // Settings indicator (top-right). The whole top-right CORNER is the hit target — an overlay
            // on the card (see `body`) that reaches the card edges and opens Settings DIRECTLY via
            // `SettingsWindowController` (not SwiftUI `openSettings()`, which routes through a hidden 1×1
            // scene window that lingers and breaks reopen). This is just the visual glyph.
            Image(systemName: "gearshape")
                .foregroundStyle(Theme.Color.textMuted)
                .accessibilityHidden(true)
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
            SectionLabel("Mode")
            ModeControl(
                selection: Binding(
                    get: { ScheduleModeOption(model.state.scheduleMode) },
                    set: { model.setScheduleMode($0.toScheduleMode()) }
                ),
                compact: true,
                onChange: { _ in }
            )
        }
    }

    /// Cozy mode on when the warmest point dips below the everyday 1900K ceiling — drives the slider's
    /// fireball thumb / "Warmest" label / 99% reading so the slider agrees with the Cozy card below it.
    private var isCozy: Bool { model.state.warmestPoint.value < Kelvin.everydayWarmest.value }

    // MARK: Incompatibility ("can only be tinted") detection

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
            //). LSUIElement agents have no app menu, so this is the Quit affordance; ⌘Q also works.
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
                Text("Reveal True Color: ⌥⌘T (\(model.revealMode.rawValue))")
                    .font(Theme.Typography.ui(10.5))
                    .foregroundStyle(Theme.Color.textFaint)
            }

            Spacer()

            // Advanced disclosure indicator (bottom-right). The whole bottom-right CORNER is the hit
            // target — an overlay on the card (see `body`); this is just the visual chevron, rotating
            // 180° when open.
            Image(systemName: "chevron.down")
                .rotationEffect(.degrees(model.isAdvancedExpanded ? 180 : 0))
                .foregroundStyle(Theme.Color.textMuted)
                .accessibilityHidden(true)
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

    /// Read-only binding for the locked Sunset slider — tracks the warmth being applied right now
    /// (the time-of-day ramp). The setter is a no-op: warmth isn't hand-set from the popover in Sunset.
    private var sunsetLiveBinding: Binding<Double> {
        Binding(get: { model.state.resolvedWarmth.strength }, set: { _ in })
    }

    /// Explains the locked slider and links to the editable maximum (Settings → General). Leads with the
    /// live state (warming now vs. eases in at sunset) so the daytime "neutral now" reading isn't a puzzle.
    private var sunsetLockCaption: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(model.isWarmingActive
                 ? "Sunset is setting your warmth automatically."
                 : "Warmth eases in around your local sunset.")
                .font(Theme.Typography.ui(11))
                .foregroundStyle(Theme.Color.textFaint)
                .fixedSize(horizontal: false, vertical: true)
            Button { SettingsWindowController.show(model: model) } label: {
                HStack(spacing: 3) {
                    Text("Change your maximum in Settings")
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 8, weight: .semibold))
                        .accessibilityHidden(true)
                }
                .font(Theme.Typography.ui(11, weight: .medium))
                .foregroundStyle(Theme.Color.accent)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens Settings to change your maximum warmth")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

// MARK: - IncompatibilityNotice

/// The app-level "this Mac can only tint" notice, shown when EVERY connected display is tint-only.
/// Names the user's actual chip + macOS version (so the limitation is concrete, not vague) and offers
/// a tappable "Why?" that reveals a plain-language, non-medical explanation. Dark ink on the amber
/// fill for contrast. DRAFT copy/visual — pending final design direction.
private struct IncompatibilityNotice: View {
    @State private var showWhy = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let ink = Theme.Color.inkOnAccent
    private let summary = "This Mac can only tint your displays"
    private let explanation = "True warming isn’t available on this Mac, so Abendrot can only add a warm color tint to your displays — a known limitation on some Apple-silicon chips and macOS versions."

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(Theme.Typography.ui(12))
                    .foregroundStyle(Theme.Color.accentPress)
                VStack(alignment: .leading, spacing: 6) {
                    Text(summary)
                        .font(Theme.Typography.ui(11, weight: .semibold))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .help(explanation)
                    HStack(spacing: 6) {
                        Text(SystemInfo.summary)
                            .font(Theme.Typography.ui(10, weight: .medium))
                            .foregroundStyle(ink.opacity(0.75))
                        Spacer()
                        Button {
                            // Single animation source: the container's `.animation(value: showWhy)`
                            // below drives the reveal; an explicit withAnimation here would compound it.
                            showWhy.toggle()
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
                Text("Some Apple-silicon Macs on newer macOS versions don’t let apps shift the display’s color at the system level, so here Abendrot can only lay a warm tint over the screen — it can’t remove blue light the way it does on other Macs. Nothing is broken; it’s a macOS limitation. An external monitor with its own color controls can still be truly warmed via Hardware control (Settings → Displays).")
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
