import SwiftUI
import AppKit
import WarmthKit

// MARK: - Advanced

/// Settings → Advanced as grouped cards, in the System Settings style: Maximum warmth, Reveal True
/// Color, Pause automatically (full screen and excluded apps), and a Troubleshooting footer.
/// Rarely used options sit behind a disclosure so the tab stays short.
struct AdvancedTab: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            TabHeader(title: "Advanced", subtitle: "Maximum warmth, the reveal shortcut, and when Abendrot pauses.")
                .padding(.bottom, -20) // TabHeader's own bottom padding duplicates this stack's spacing.

            AdvancedGroup("Maximum warmth") {
                CozyRow(model: model)
            }

            AdvancedGroup("Reveal True Color", footnote: revealFootnote) {
                SettingsCard {
                    SettingsRow(systemImage: "keyboard", title: "Keyboard shortcut", subtitle: "Click to record — default ⌥⌘T") {
                        RevealShortcutRecorder()
                    }
                    CardDivider()
                    SettingsRow(systemImage: nil, title: "Behavior") {
                        BrandSegmentedControl(
                            options: RevealMode.allCases,
                            selection: Binding(get: { model.revealMode }, set: { model.setRevealMode($0) }),
                            label: { $0 == .hold ? "Hold" : "Toggle" }
                        )
                        .frame(width: 170)
                    }
                }
            }

            AdvancedGroup("Pause automatically") {
                VStack(alignment: .leading, spacing: 10) {
                    SettingsCard {
                        SettingsRow(
                            systemImage: "arrow.up.left.and.arrow.down.right",
                            title: "In full screen",
                            subtitle: "Turns warmth off on a screen while an app fills it."
                        ) {
                            SettingsSwitch(
                                isOn: Binding(get: { model.state.pausesForFullScreen },
                                              set: { model.setPausesForFullScreen($0) }),
                                label: "Pause in full screen"
                            )
                        }
                    }
                    ExcludedAppsCard(model: model)
                    #if !APP_STORE
                    ExperimentalCard(model: model)
                    #endif
                }
            }

            AdvancedGroup("Troubleshooting") {
                RestoreCard(model: model)
            }
        }
    }

    private var revealFootnote: String {
        model.revealMode == .hold
            ? "Hold the shortcut to reveal true color; release to ease warmth back."
            : "Press the shortcut to turn warming off, and again to bring it back."
    }
}

// MARK: - Building blocks

/// A titled group: a section label above one or more cards, with an optional footnote below.
private struct AdvancedGroup<Content: View>: View {
    let title: String
    let footnote: String?
    let content: Content

    init(_ title: String, footnote: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footnote = footnote
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(title)
            content
            if let footnote {
                Text(footnote)
                    .font(Theme.Typography.ui(11.5))
                    .foregroundStyle(Theme.Color.textFaint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2)
            }
        }
    }
}

/// An inset card that holds rows separated by hairlines.
private struct SettingsCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.045), in: shape)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Theme.Color.lineStrong, lineWidth: 0.5))
    }
}

private struct CardDivider: View {
    var body: some View {
        Rectangle().fill(Theme.Color.line).frame(height: 0.5)
    }
}

/// A leading icon tile, a title and optional subtitle, and a trailing control.
private struct SettingsRow<Trailing: View>: View {
    let systemImage: String?
    let lit: Bool
    let title: String
    let subtitle: String?
    let trailing: Trailing

    init(systemImage: String?, lit: Bool = false, title: String, subtitle: String? = nil,
         @ViewBuilder trailing: () -> Trailing) {
        self.systemImage = systemImage
        self.lit = lit
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            IconTile(systemImage: systemImage, lit: lit)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Typography.ui(13, weight: .semibold))
                    .foregroundStyle(Theme.Color.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.Typography.ui(12))
                        .foregroundStyle(Theme.Color.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(minHeight: 46)
    }
}

/// The 26-point icon tile at the start of a row. An empty tile keeps titles aligned.
private struct IconTile: View {
    let systemImage: String?
    var lit = false

    var body: some View {
        ZStack {
            if let systemImage {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(lit ? AnyShapeStyle(Theme.Gradient.sunset) : AnyShapeStyle(Color.white.opacity(0.08)))
                Image(systemName: systemImage)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(lit ? Theme.Color.inkOnAccent : Theme.Color.textMuted)
            }
        }
        .frame(width: 26, height: 26)
        .accessibilityHidden(true)
    }
}

private struct SettingsSwitch: View {
    @Binding var isOn: Bool
    let label: String

    var body: some View {
        Toggle("", isOn: $isOn)
            .toggleStyle(.switch)
            .tint(Theme.Color.accent)
            .labelsHidden()
            .accessibilityLabel(label)
    }
}

// MARK: - Maximum warmth

/// Cozy mode as a card row. The popover and onboarding use the compact `CozyModeControl` card.
private struct CozyRow: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Derived from the actual warmest point so the switch can never disagree with the engine.
    private var isCozy: Bool { model.state.warmestPoint.value < Kelvin.everydayWarmest.value }

    var body: some View {
        SettingsCard {
            SettingsRow(
                systemImage: isCozy ? "flame.fill" : "flame",
                lit: isCozy,
                title: "Cozy mode",
                subtitle: "The warmest setting — past 1900 K toward candlelight."
            ) {
                SettingsSwitch(isOn: Binding(get: { isCozy }, set: { model.setCozy($0) }), label: "Cozy mode")
            }
            if isCozy {
                CardDivider()
                Text(CozyModeControl.scienceNote)
                    .font(Theme.Typography.ui(11))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .transition(.opacity)
            }
        }
        .animation(Theme.Motion.warm(reduceMotion: reduceMotion), value: isCozy)
    }
}

// MARK: - Excluded apps

/// While one of these apps is in front, Abendrot pauses warmth on the display that app is using.
/// The popover's per-app pause deep-links here through `excludedAppsFocusRequest`.
private struct ExcludedAppsCard: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsFocusCue = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsCard {
                HStack(spacing: 12) {
                    IconTile(systemImage: "pause.rectangle")
                    Text("Excluded apps")
                        .font(Theme.Typography.ui(13, weight: .semibold))
                        .foregroundStyle(Theme.Color.textPrimary)
                    Spacer()
                    Text("\(model.excludedApps.count)")
                        .font(Theme.Typography.ui(11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.Color.textMuted)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 1)
                        .background(Color.white.opacity(0.08), in: Capsule())
                        .accessibilityLabel(model.excludedApps.count == 1 ? "1 app" : "\(model.excludedApps.count) apps")
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 40)
                CardDivider()

                if model.excludedApps.isEmpty {
                    Text("None yet. Abendrot stays warm in every app.")
                        .font(Theme.Typography.ui(12))
                        .foregroundStyle(Theme.Color.textFaint)
                        .padding(12)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(sortedIDs.enumerated()), id: \.element) { index, bundleID in
                                if index > 0 { CardDivider() }
                                ExcludedAppRow(bundleID: bundleID) {
                                    model.removeExcludedApp(bundleID)
                                }
                            }
                        }
                    }
                    // Three rows and their two dividers, so Add app stays on screen.
                    .frame(maxHeight: 3 * 36 + 2 * 0.5)
                }
                CardDivider()

                Button(action: addApp) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Add app…")
                            .font(Theme.Typography.ui(12.5, weight: .semibold))
                        Spacer()
                    }
                    .foregroundStyle(Theme.Color.accentText)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 38)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .background(focusCueFill)
            .overlay(focusCueStroke)

            Text(explanation)
                .font(Theme.Typography.ui(11.5))
                .foregroundStyle(Theme.Color.textFaint)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 2)
        }
        .task(id: model.excludedAppsFocusRequest) {
            guard let request = model.excludedAppsFocusRequest else { return }
            await runFocusCue(request)
        }
    }

    /// Sorted by the name people see, not the bundle id.
    private var sortedIDs: [String] {
        model.excludedApps
            .map { (id: $0, name: AppIdentity.name(for: $0)) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map(\.id)
    }

    private var explanation: String {
        #if APP_STORE
        "While one of these apps is in front, warmth turns off on its screen. Other screens stay warm. Abendrot can't keep just one window neutral."
        #else
        model.state.keepsOtherWindowsWarm
            ? "While one of these apps is in front, only its windows lose their warmth."
            : "While one of these apps is in front, warmth turns off on its screen. Other screens stay warm."
        #endif
    }

    private var focusCueFill: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.control + 4, style: .continuous)
            .fill(Theme.Color.accent.opacity(0.12))
            .opacity(showsFocusCue ? 1 : 0)
            .padding(-6)
    }

    private var focusCueStroke: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.control + 4, style: .continuous)
            .stroke(Theme.Color.accent.opacity(0.7), lineWidth: 1)
            .shadow(color: Theme.Color.accent.opacity(0.45), radius: 12)
            .opacity(showsFocusCue ? 1 : 0)
            .padding(-6)
    }

    @MainActor
    private func runFocusCue(_ request: UUID) async {
        if showsFocusCue {
            withAnimation(nil) { showsFocusCue = false }
            await Task.yield()
        }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
            showsFocusCue = true
        }
        do {
            try await Task.sleep(nanoseconds: 700_000_000)
        } catch {
            return
        }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.42)) {
            showsFocusCue = false
        }
        do {
            try await Task.sleep(nanoseconds: reduceMotion ? 0 : 420_000_000)
        } catch {
            return
        }
        if model.excludedAppsFocusRequest == request {
            model.excludedAppsFocusRequest = nil
        }
    }

    /// Pick an application bundle and add its bundle id to the exclusion set. In the App Store
    /// build, the Powerbox grants this one selection read-only access through the user-selected-file
    /// entitlement; the direct build remains unsandboxed.
    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"
        guard panel.runModal() == .OK, let url = panel.url,
              let id = Bundle(url: url)?.bundleIdentifier else { return }
        model.addExcludedApp(id)
    }
}

/// One excluded app: its icon and name (the bundle id when the app can't be found), and a remove button.
private struct ExcludedAppRow: View {
    let bundleID: String
    let onRemove: () -> Void
    @State private var hovered = false

    var body: some View {
        let name = AppIdentity.name(for: bundleID)
        HStack(spacing: 10) {
            if let icon = AppIdentity.icon(for: bundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Color.textFaint)
                    .frame(width: 18, height: 18)
            }
            Text(name)
                .font(Theme.Typography.ui(12.5))
                .foregroundStyle(Theme.Color.textPrimary)
                .lineLimit(1)
            Spacer()
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(hovered ? Theme.Color.textPrimary : Theme.Color.textMuted)
                    .frame(width: 22, height: 22)
                    .background(Color.white.opacity(hovered ? 0.1 : 0), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { hovered = $0 }
            .accessibilityLabel("Remove \(name) from excluded apps")
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .frame(height: 36)
    }
}

// MARK: - Experimental

#if !APP_STORE
/// Direct-download-only options behind a disclosure. It starts open while one of them is on, so a
/// setting that changes behavior is never hidden.
private struct ExperimentalCard: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Set once when the card appears, so turning the switch off never collapses it under the cursor.
    @State private var expanded: Bool?

    private var isExpanded: Bool { expanded ?? model.state.keepsOtherWindowsWarm }

    var body: some View {
        SettingsCard {
            Button {
                withAnimation(Theme.Motion.warm(reduceMotion: reduceMotion)) { expanded = !isExpanded }
            } label: {
                HStack(spacing: 10) {
                    Text("Experimental")
                        .font(Theme.Typography.ui(12.5, weight: .medium))
                        .foregroundStyle(Theme.Color.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.Color.textFaint)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Experimental options")
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            if isExpanded {
                CardDivider()
                SettingsRow(
                    systemImage: nil,
                    title: "Keep other windows warm",
                    subtitle: "Only the excluded app loses its warmth. Everything else on that screen stays warm, except screens using hardware control."
                ) {
                    SettingsSwitch(
                        isOn: Binding(get: { model.state.keepsOtherWindowsWarm },
                                      set: { model.setKeepsOtherWindowsWarm($0) }),
                        label: "Keep other windows warm"
                    )
                }
                .transition(.opacity)
            }
        }
        .onAppear { if expanded == nil { expanded = model.state.keepsOtherWindowsWarm } }
    }
}
#endif

// MARK: - Troubleshooting

/// The emergency reset. It turns warmth off and forcefully restores every display layer (gamma,
/// overlay, color filter and hardware), which turning warmth off alone does not. It stays available
/// while warmth is off, because that is when stuck colors are noticed.
private struct RestoreCard: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confirming = false

    private var multiple: Bool { model.state.displays.count > 1 }

    var body: some View {
        SettingsCard {
            if confirming {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(confirmTitle)
                            .font(Theme.Typography.ui(13, weight: .semibold))
                            .foregroundStyle(Theme.Color.textPrimary)
                        Text("Use this if colors stay tinted after a crash or display change.")
                            .font(Theme.Typography.ui(12))
                            .foregroundStyle(Theme.Color.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Button("Cancel") { setConfirming(false) }
                        .buttonStyle(.liquidGlass)
                        .keyboardShortcut(.cancelAction)
                    Button("Restore", role: .destructive) {
                        model.setEnabled(false)
                        model.restoreAllDisplays()
                        setConfirming(false)
                    }
                    .buttonStyle(.liquidGlass)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .transition(.opacity)
            } else {
                SettingsRow(
                    systemImage: "arrow.counterclockwise",
                    title: multiple ? "Restore displays to True Color" : "Restore display to True Color",
                    subtitle: model.state.isEnabled
                        ? "Emergency reset if your screen stays tinted. Turns warmth off."
                        : "Emergency reset if your screen stays tinted."
                ) {
                    Button("Restore…") { setConfirming(true) }
                        .buttonStyle(.liquidGlass)
                }
                .transition(.opacity)
            }
        }
    }

    private var confirmTitle: String {
        let target = multiple ? "your displays" : "your display"
        return model.state.isEnabled ? "Turn warmth off and reset \(target)?" : "Reset \(target)?"
    }

    private func setConfirming(_ value: Bool) {
        withAnimation(Theme.Motion.warm(reduceMotion: reduceMotion)) { confirming = value }
    }
}
