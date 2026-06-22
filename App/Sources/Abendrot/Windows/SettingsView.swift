import SwiftUI

// MARK: - SettingsTab

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, displays, advanced, privacy, statistics, updates, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .displays: return "Displays"
        case .advanced: return "Advanced"
        case .privacy: return "Privacy"
        case .statistics: return "Statistics"
        case .updates: return "Updates"
        case .about: return "About"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .displays: return "display.2"
        case .advanced: return "slider.horizontal.3"
        case .privacy: return "hand.raised"
        case .statistics: return "chart.bar.xaxis"
        case .updates: return "arrow.down.circle"
        case .about: return "info.circle"
        }
    }
}

// MARK: - SettingsView
//
// The Settings window body (tabs: General / Schedule / Displays / Shortcuts
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
    /// Screenshot harness only: render the detail column WITHOUT its ScrollView so the view hugs the
    /// tab's natural height (the live window does this via `fitDetailContentHeight`; ImageRenderer can't).
    var scrolls: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                VStack(spacing: 4) {
                    ForEach(SettingsTab.allCases) { tab in
                        SettingsSidebarButton(
                            tab: tab,
                            isSelected: model.settingsTab == tab,
                            reduceMotion: reduceMotion
                        ) {
                            withAnimation(Theme.Motion.controlReveal(reduceMotion: reduceMotion)) {
                                model.settingsTab = tab
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)

                Spacer(minLength: 12)
                // Hide the sidebar branding on About (it duplicates the About-page header). Animate
                // offset+opacity on an always-present view rather than a conditional transition, so the
                // slide-OUT (entering About) is exactly as smooth as the slide-IN (leaving) — a SwiftUI
                // removal transition snapped instead of sliding . Stays in the layout (offset
                // off-screen + faded) so nothing reflows.
                SidebarBranding()
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(model.settingsTab == .about ? 0 : 1)
                    .offset(x: model.settingsTab == .about ? -200 : 0)
                    .accessibilityHidden(model.settingsTab == .about)   // off-screen: leave the focus order
                    .animation(Theme.Motion.controlReveal(reduceMotion: reduceMotion), value: model.settingsTab)
            }
            .frame(width: 180)
            .frame(maxHeight: .infinity)

            Divider()

            if scrolls {
                ScrollView { detailColumn }
                    .scrollContentBackground(.hidden)
                    .onPreferenceChange(SettingsContentHeightKey.self) { height in
                        Task { @MainActor in SettingsWindowController.fitDetailContentHeight(height) }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                detailColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(minWidth: 680, minHeight: 480)
        .background(FrostBackground())
    }

    private var detailColumn: some View {
        tabBody
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GeometryReader { proxy in
                // Report the current tab's natural content height so the window can hug it.
                Color.clear.preference(key: SettingsContentHeightKey.self, value: proxy.size.height)
            })
    }

    @ViewBuilder
    private var tabBody: some View {
        switch model.settingsTab {
        case .general: GeneralTab(model: model)
        case .displays: DisplaysTab(model: model)
        case .advanced: AdvancedTab(model: model)
        case .privacy: PrivacyTab(model: model)
        case .statistics: StatisticsTab(model: model)
        case .updates: UpdatesTab()
        case .about: AboutTab()
        }
    }
}

/// The current tab's natural content height (measured inside the detail ScrollView) so the Settings
/// window can size itself to hug whatever tab/mode is showing — see
/// `SettingsWindowController.fitDetailContentHeight`.
private struct SettingsContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

// MARK: - Sidebar row

private struct SettingsSidebarButton: View {
    let tab: SettingsTab
    let isSelected: Bool
    let reduceMotion: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Label {
                Text(tab.title)
                    .font(Theme.Typography.ui(13, weight: .semibold))
                    .lineLimit(1)
                    .allowsTightening(true)
                    .minimumScaleFactor(0.9)
                    .fixedSize(horizontal: true, vertical: false)
            } icon: {
                Image(systemName: tab.icon)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 24)
            }
            .labelStyle(.titleAndIcon)
            .foregroundStyle(isSelected ? Theme.Color.inkOnAccent : Theme.Color.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .padding(.horizontal, 10)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(backgroundFill)
        )
        .onHover { isHovered = $0 }
        .animation(Theme.Motion.controlReveal(reduceMotion: reduceMotion), value: isSelected)
        .animation(Theme.Motion.controlReveal(reduceMotion: reduceMotion), value: isHovered)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var backgroundFill: Color {
        if isSelected { return Theme.Color.accent }
        if isHovered { return Theme.Color.textPrimary.opacity(0.08) }
        return .clear
    }
}

// MARK: - Tab header

// Internal (not private) so the per-tab files (General/Displays/Advanced/Privacy/Statistics) share it.
struct TabHeader: View {
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

/// "Built by Matthew Ball" → matthewball.me. The name is always underlined so it reads as a link, and
/// it brightens on hover (same hue) for a clear, colour-preserving affordance. Shared by the Settings
/// sidebar footer (11) and the About page (11.5) so the two stay congruent — `fontSize` is the only
/// difference between the two placements.
struct BylineLink: View {
    var fontSize: CGFloat = 11
    @State private var hovering = false
    var body: some View {
        Link(destination: URL(string: "https://matthewball.me/")!) {
            (Text("Built by ") + Text("Matthew Ball").underline())
                .font(Theme.Typography.ui(fontSize))
                .foregroundStyle(Theme.Color.textMuted)
                .opacity(hovering ? 1 : 0.85)
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .onHover { hovering = $0 }
    }
}

private struct SidebarBranding: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            AppIconView()
                .frame(width: 32, height: 32)
            Text("Abendrot")
                .font(Theme.Typography.serif(15))
                .foregroundStyle(Theme.Color.textPrimary)
            BylineLink()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 10)
        .overlay(alignment: .top) {
            DividerLine()
        }
    }
}

// MARK: - Preview

#Preview("Settings") {
    SettingsView(model: AppModel(previewState: MockWarmthState.warming))
}
