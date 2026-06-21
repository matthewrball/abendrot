import SwiftUI
import ServiceManagement
import WarmthKit

// MARK: - SettingsTab

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, displays, advanced, privacy, statistics, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .displays: return "Displays"
        case .advanced: return "Advanced"
        case .privacy: return "Privacy"
        case .statistics: return "Statistics"
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            VStack(spacing: 0) {
                List(SettingsTab.allCases, selection: $model.settingsTab) { tab in
                    Label(tab.title, systemImage: tab.icon)
                        .tag(tab)
                }
                .scrollContentBackground(.hidden)

                Spacer(minLength: 12)
                // Hide the sidebar branding on About (it duplicates the About-page header). Animate
                // offset+opacity on an always-present view rather than a conditional transition, so the
                // slide-OUT (entering About) is exactly as smooth as the slide-IN (leaving) — a SwiftUI
                // removal transition snapped instead of sliding (founder). Stays in the layout (offset
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
            .navigationSplitViewColumnWidth(min: 172, ideal: 180)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            ScrollView {
                tabBody
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(GeometryReader { proxy in
                        // Report the current tab's natural content height so the window can hug it.
                        Color.clear.preference(key: SettingsContentHeightKey.self, value: proxy.size.height)
                    })
            }
            .scrollContentBackground(.hidden)
            .onPreferenceChange(SettingsContentHeightKey.self) { height in
                Task { @MainActor in SettingsWindowController.fitDetailContentHeight(height) }
            }
        }
        .frame(minWidth: 680, minHeight: 480)
        .background(FrostBackground())
    }

    @ViewBuilder
    private var tabBody: some View {
        switch model.settingsTab {
        case .general: GeneralTab(model: model)
        case .displays: DisplaysTab(model: model)
        case .advanced: AdvancedTab(model: model)
        case .privacy: PrivacyTab(model: model)
        case .statistics: StatisticsTab(model: model)
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

/// A small labelled hyperlink (icon + underlined text) in the app's accent, brightening on hover with
/// a link cursor. Used for the About page's GitHub / website links.
private struct AboutLink: View {
    let title: String
    var systemImage: String? = nil
    /// A template image asset (e.g. the GitHub mark) — tinted with the accent, used when no SF Symbol fits.
    var assetImage: String? = nil
    let url: String
    @State private var hovering = false
    var body: some View {
        Link(destination: URL(string: url)!) {
            Label {
                Text(title).underline()
            } icon: {
                icon
            }
            .font(Theme.Typography.ui(12, weight: .medium))
            .foregroundStyle(Theme.Color.accent)
            .opacity(hovering ? 1 : 0.85)
            .animation(.easeOut(duration: 0.12), value: hovering)
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .onHover { hovering = $0 }
    }

    @ViewBuilder private var icon: some View {
        if let assetImage {
            Image(assetImage)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 12, height: 12)
        } else if let systemImage {
            Image(systemName: systemImage)
        }
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

// MARK: - General

private struct GeneralTab: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("softConfirmationTone") private var softTone = false
    @State private var launchAtLoginError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            TabHeader(title: "General", subtitle: "How Abendrot behaves day to day.")

            // The primary control, first and consistent with the menu-bar popover (founder): the
            // master toggle + the SAME liquid-glass WarmSlider (Warmth label, inline Kelvin + ⓘ,
            // Softer/Warmer). The slider reveals with the toggle, exactly like the popover.
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Warm my displays")
                        .font(Theme.Typography.ui(13, weight: .semibold))
                        .foregroundStyle(Theme.Color.textPrimary)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { model.state.isEnabled },
                        set: { model.setEnabled($0) }
                    ))
                    .labelsHidden()
                }
                if model.state.isEnabled {
                    WarmSlider(
                        strength: Binding(
                            get: { model.state.globalWarmth.strength },
                            set: { model.setGlobalWarmth($0) }
                        ),
                        model: model,
                        kelvin: model.globalKelvin
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                }
            }
            .animation(Theme.Motion.warm(reduceMotion: reduceMotion), value: model.state.isEnabled)

            // Schedule MODE lives here (founder): the menu-bar popover groups on/off + warmth + mode as
            // one "how it warms" unit, so General is its full desktop twin. The Mode selector now hides
            // with the master toggle (popover parity); Location stays visible (a standing preference).
            VStack(alignment: .leading, spacing: 12) {
                // Mode selector hides when warming is off (popover parity — on/off + warmth + mode are one
                // unit). Location stays visible regardless: a standing preference (where to estimate sunset),
                // useful even while warming is off (founder).
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

                // Location only matters for Sunset (it estimates your sunset time); hidden for Always on.
                // Kept visible even when warming is off — a standing preference (founder).
                if ScheduleModeOption(model.state.scheduleMode) == .followSunset {
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
            .animation(Theme.Motion.warm(reduceMotion: reduceMotion), value: model.state.isEnabled)

            DividerLine()

            // Far-right switches (label left, control trailing) to match the master toggle and the
            // standard macOS settings layout (founder).
            HStack {
                Text("Launch at login").font(Theme.Typography.ui(13))
                Spacer()
                Toggle("", isOn: $launchAtLogin)
                    .labelsHidden()
                    .onChange(of: launchAtLogin) { _, isOn in setLaunchAtLogin(isOn) }
            }
            if let launchAtLoginError {
                Text(launchAtLoginError)
                    .font(Theme.Typography.ui(11.5))
                    .foregroundStyle(Theme.Color.textFaint)
            }
            // Show-in-menu-bar with clear re-entry (plan §4.3).
            HStack {
                Text("Show icon in menu bar").font(Theme.Typography.ui(13))
                Spacer()
                Toggle("", isOn: $model.showInMenuBar).labelsHidden()
            }
            if !model.showInMenuBar {
                Text("Hidden from the menu bar. Re-open with ⌥⌘T, or relaunch Abendrot to bring Settings back.")
                    .font(Theme.Typography.ui(11.5))
                    .foregroundStyle(Theme.Color.textFaint)
            }
            HStack {
                Text("Sounds").font(Theme.Typography.ui(13))
                Spacer()
                Toggle("", isOn: $softTone).labelsHidden()
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

// MARK: - CityAutocomplete

// Internal (not private) so onboarding step 3 reuses the exact same liquid-glass city picker.
struct CityAutocomplete: View {
    @Bindable var model: AppModel
    /// Onboarding sits this field near the card's bottom, so the dropdown must open UPWARD there or it's
    /// clipped by the card edge and overlaps the primary button. Settings has room below (default).
    var opensUpward: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var fieldFocused: Bool
    @State private var query = ""
    @State private var isOpen = false
    @State private var hoveredID: String?
    @State private var highlightedID: String?
    /// Set when the X (reset) is clicked. If the dropdown is then dismissed WITHOUT picking a city,
    /// the selection falls back to Auto (founder). Cleared by any explicit pick.
    @State private var armedAutoReset = false
    /// The rows the dropdown was showing when `close()` ran. Held for the duration of the out-transition
    /// so settling the field text (which recomputes `filteredCities`) can't reflow the list mid-fade.
    @State private var closingSnapshot: [MajorCities.City]?

    /// Sentinel id for the pinned "Auto (from time zone)" row so it joins the keyboard highlight cycle.
    private let autoID = "__auto__"

    // The first three are the default suggestions shown before the user types (founder pick); the rest
    // are fallbacks in case one isn't in MajorCities. Only the first three resolved cities are shown.
    private let popularCityNames = [
        "San Francisco", "New York", "Chicago", "Seattle", "London", "Paris", "Tokyo", "Sydney"
    ]

    var body: some View {
        searchField
            // Click-away: while the list is open, a near-invisible full-bleed catcher sits behind the field
            // + dropdown so a click anywhere else dismisses the menu. The onboarding window's drag-background
            // otherwise swallows outside clicks without resigning the field's focus, leaving the list open.
            // The field (front) and dropdown (overlay) sit above it, so their own taps still work.
            .background {
                if isOpen {
                    Color.black.opacity(0.001)
                        .frame(width: 3000, height: 3000)
                        .contentShape(Rectangle())
                        .onTapGesture { fieldFocused = false; close() }
                }
            }
            // Float the dropdown BELOW the field as an overlay instead of pushing layout down. This keeps
            // a height-constrained host (the onboarding card) from clipping content/button below, and it's
            // the right behaviour anywhere (a menu should float over content, not shove it). The offset ≈
            // the field's height; `zIndex` lifts the whole picker above sibling content while open.
            .overlay(alignment: opensUpward ? .bottomLeading : .topLeading) {
                if isOpen {
                    dropdown
                        .frame(maxWidth: .infinity)
                        .offset(y: opensUpward ? -44 : 44)
                        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: opensUpward ? .bottom : .top)))
                }
            }
            .zIndex(isOpen ? 10 : 0)
            .onAppear { syncQueryToSelection() }
        .onChange(of: model.userCoordinate) { _, _ in
            if !fieldFocused { syncQueryToSelection() }
        }
        .onChange(of: fieldFocused) { _, focused in
            if focused {
                open()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    if !fieldFocused { close() }
                }
            }
        }
        .animation(Theme.Motion.controlReveal(reduceMotion: reduceMotion), value: isOpen)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.Color.textFaint)

            TextField("", text: $query, prompt: Text("Search for your city…"))
                .textFieldStyle(.plain)
                .font(Theme.Typography.ui(12.5))
                .foregroundStyle(Theme.Color.textPrimary)
                .focused($fieldFocused)
                .onSubmit { selectHighlightedOrFirst() }
                .onChange(of: query) { _, _ in
                    if fieldFocused { isOpen = true }
                    highlightedID = filteredCities.first?.id
                }
                .onKeyPress(.downArrow) {
                    if isOpen { moveHighlight(by: 1) } else { open() }
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    if isOpen { moveHighlight(by: -1) } else { open() }
                    return .handled
                }
                .onKeyPress(.escape) {
                    guard isOpen || fieldFocused else { return .ignored }
                    fieldFocused = false
                    close()
                    return .handled
                }

            // Always an X (founder): clears the input and opens the list; when there's nothing left to
            // clear, it dismisses — so the dropdown is always closable (the chevron used to only re-open).
            Button {
                armedAutoReset = true                    // a reset gesture: dismiss without a pick → Auto
                if isOpen && !query.isEmpty {
                    query = ""                           // clear a typed search; keep the list open
                    highlightedID = filteredCities.first?.id
                } else if isOpen {
                    fieldFocused = false
                    close()                              // already empty → dismiss (falls back to Auto)
                } else {
                    query = ""
                    open()                               // closed → clear the input and open the list
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.Color.textFaint)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isOpen ? "Clear or close the city list" : "Clear and browse cities")
            .help(isOpen ? "Clear, or close the list" : "Clear and browse cities")
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .glassSurface(.frost, cornerRadius: Theme.Radius.control)
        .overlay(searchFieldStroke)
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        .onTapGesture { open() }
    }

    private var dropdown: some View {
        VStack(spacing: 4) {
            cityRow(title: "Auto", systemImage: "globe",
                    selected: selectedCity == nil, highlighted: highlightedID == autoID) {
                selectAuto()
            }
            .onHover { if $0 { highlightedID = autoID } }

            if dropdownCities.isEmpty {
                Text("No cities found")
                    .font(Theme.Typography.ui(12))
                    .foregroundStyle(Theme.Color.textFaint)
                    .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                    .padding(.horizontal, 10)
            } else {
                // Up to 3 results in a plain VStack (NOT a ScrollView): inside the floating dropdown the
                // ScrollView was proposed only the field's height and collapsed to ~0, hiding the cities.
                // A VStack sizes to its rows, so the results always render — and good autocomplete doesn't
                // need a long list (founder: the search does the narrowing).
                VStack(spacing: 3) {
                    ForEach(dropdownCities.prefix(3)) { city in
                        cityRow(
                            title: city.name,
                            systemImage: nil,
                            selected: city == selectedCity,
                            highlighted: city.id == highlightedID || city.id == hoveredID
                        ) {
                            select(city)
                        }
                        .onHover { hovering in
                            hoveredID = hovering ? city.id : nil
                            if hovering { highlightedID = city.id }
                        }
                    }
                }
            }
        }
        .padding(6)
        .glassSurface(.frost, cornerRadius: Theme.Radius.control + 2)
        .overlay(dropdownStroke)
        .shadow(color: .black.opacity(0.24), radius: 18, y: 8)
    }

    private func cityRow(
        title: String,
        systemImage: String?,
        selected: Bool,
        highlighted: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.Color.textFaint)
                        .frame(width: 15)
                }

                Text(title)
                    .font(Theme.Typography.ui(12.5, weight: selected ? .medium : .regular))
                    .foregroundStyle(selected ? Theme.Color.textPrimary : Theme.Color.textMuted)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.Color.accentHighlight)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(rowBackground(selected: selected, highlighted: highlighted))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control - 2, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func rowBackground(selected: Bool, highlighted: Bool) -> some View {
        RoundedRectangle(cornerRadius: Theme.Radius.control - 2, style: .continuous)
            .fill(highlighted ? Theme.Color.line.opacity(0.7) : Theme.Color.line.opacity(selected ? 0.45 : 0))
            .overlay(alignment: .leading) {
                if selected {
                    RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
                        .fill(Theme.Gradient.sunset)
                        .frame(width: 3)
                        .padding(.vertical, 7)
                }
            }
            .animation(Theme.Motion.warm(reduceMotion: reduceMotion), value: highlighted)
            .animation(Theme.Motion.warm(reduceMotion: reduceMotion), value: selected)
    }

    private var searchFieldStroke: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
            .strokeBorder(Theme.Color.lineStrong, lineWidth: 0.5)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.control - 1, style: .continuous)
                    .strokeBorder(Theme.Color.line.opacity(0.5), lineWidth: 0.5)
                    .padding(1)
            )
    }

    private var dropdownStroke: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.control + 2, style: .continuous)
            .strokeBorder(Theme.Color.lineStrong, lineWidth: 0.5)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.control + 1, style: .continuous)
                    .strokeBorder(Theme.Color.line.opacity(0.55), lineWidth: 0.5)
                    .padding(1)
            )
    }

    private var selectedCity: MajorCities.City? {
        guard let coordinate = model.userCoordinate else { return nil }
        return MajorCities.all.first { $0.coordinate == coordinate }
    }

    private var selectionText: String {
        if let selectedCity { return selectedCity.name }
        // Show the neutral "Auto (from time zone)" by default — NOT the derived representative city, which
        // can read as wrong (e.g. "Los Angeles" to an SF user) and overstates precision. Users opt in to a
        // city for accuracy. Matches the dropdown's own "Auto" row.
        return "Auto"
    }

    private var filteredCities: [MajorCities.City] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == selectionText {
            return defaultCities
        }

        let needle = normalized(trimmed)
        let prefix = MajorCities.all.filter { normalized($0.name).hasPrefix(needle) }
        let contains = MajorCities.all.filter {
            let name = normalized($0.name)
            return !name.hasPrefix(needle) && name.contains(needle)
        }
        return Array((prefix + contains).prefix(8))
    }

    /// The rows the dropdown actually renders. While closing, this is the frozen `closingSnapshot` so the
    /// list keeps the rows it had as it fades/scales out (no reflow); otherwise it's the live results.
    private var dropdownCities: [MajorCities.City] {
        closingSnapshot ?? filteredCities
    }

    private var defaultCities: [MajorCities.City] {
        var result: [MajorCities.City] = []
        if let selectedCity { result.append(selectedCity) }
        for name in popularCityNames {
            if let city = MajorCities.all.first(where: { $0.name == name }), !result.contains(city) {
                result.append(city)
            }
        }
        return Array(result.prefix(3))
    }

    private func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private func open() {
        closingSnapshot = nil    // discard any held close-snapshot so the list shows live results again
        hoveredID = nil
        fieldFocused = true
        isOpen = true
        if query == selectionText { query = "" }
        highlightedID = filteredCities.first?.id
    }

    private func close() {
        // Freeze the rows the dropdown is showing BEFORE flipping `isOpen` (the body's `.animation(value:
        // isOpen)` drives the fade/scale-out). While closing, `dropdownCities` reads this snapshot, so
        // settling the field text below — which recomputes `filteredCities` — can't reflow the list under
        // the out-transition. Hover/highlight tints are held too, so no row flips its background mid-fade.
        closingSnapshot = dropdownCities
        isOpen = false
        if armedAutoReset {
            // The X was clicked and the list was dismissed without choosing a city → fall back to Auto.
            model.setUserCoordinate(nil)
            armedAutoReset = false
        }
        syncQueryToSelection()
    }

    private func syncQueryToSelection() {
        query = selectionText
    }

    private func selectAuto() {
        armedAutoReset = false
        model.setUserCoordinate(nil)
        fieldFocused = false
        close()
    }

    private func select(_ city: MajorCities.City) {
        armedAutoReset = false        // an explicit pick: do NOT fall back to Auto on close
        model.setUserCoordinate(city.coordinate)
        fieldFocused = false
        close()
    }

    private func selectHighlightedOrFirst() {
        if highlightedID == autoID {
            selectAuto()
        } else if let highlightedID, let city = filteredCities.first(where: { $0.id == highlightedID }) {
            select(city)
        } else if let city = filteredCities.first {
            select(city)
        }
    }

    /// The keyboard-navigable rows in order: the Auto sentinel, then the filtered cities.
    private var navigableIDs: [String] {
        [autoID] + filteredCities.map(\.id)
    }

    /// Move the highlight up/down the navigable rows, clamped at the ends. From no selection, ↓ lands on
    /// the first row and ↑ on the last.
    private func moveHighlight(by delta: Int) {
        let ids = navigableIDs
        guard !ids.isEmpty else { return }
        let current = highlightedID.flatMap { ids.firstIndex(of: $0) } ?? (delta > 0 ? -1 : ids.count)
        highlightedID = ids[max(0, min(ids.count - 1, current + delta))]
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(display.name)
                    .font(Theme.Typography.ui(13, weight: .medium))
                    .foregroundStyle(Theme.Color.textPrimary)
                Text(statusLine)
                    .font(Theme.Typography.ui(11.5))
                    .foregroundStyle(statusColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // The warming-method picker + per-display warmth show INLINE — no "Advanced" disclosure. This
            // tab exists to configure each display, so its controls shouldn't hide behind a chevron.
            DividerLine()
            WarmingMethodPicker(display: display, model: model)
            PerDisplayWarmthControl(display: display, model: model)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 12)
        .background(Theme.Color.line.opacity(0.4),
                    in: RoundedRectangle(cornerRadius: Theme.Radius.control - 1, style: .continuous))
    }

    /// A display can be *truly* warmed when a real white-point path is available — gamma or hardware
    /// DDC — with advanced methods enabled. Otherwise it can only be tinted. (Mirrors the popover's
    /// `isTintOnly`, §25.J.)
    private var canTrueWarm: Bool {
        let priv = model.state.privateAPIsEnabled
        return priv && (display.capabilities.gamma.isSupported || display.capabilities.hardware.isSupported)
    }

    // Single source so the copy and its colour can't drift apart (review): incompatibility uses the
    // warning accent; a user-chosen tint and a true warm both read muted.
    private var status: (text: String, color: Color) {
        if !canTrueWarm {
            return ("Can only be tinted on this Mac — true warming isn’t available for this display", Theme.Color.accentHighlight)
        }
        if display.preferredMethod == .overlay {
            return ("Adding a warm tint — not true warming", Theme.Color.textMuted)
        }
        return ("Truly warmed — removes blue light", Theme.Color.textMuted)
    }

    private var statusLine: String { status.text }
    private var statusColor: Color { status.color }
}

// MARK: - Per-display override + custom warmth (Settings superset of the popover quick control)

/// The Settings → Displays version of the menu-bar popover's per-display "Override" control. Same
/// wiring (`setWarmthOverride` / `setWarmth`, `display.warmthOverridden` / `display.warmth`) for
/// experience congruency, in the roomier Settings layout. Settings is the superset — custom warmth
/// AND warming method; the popover stays the quick, override-only version.
private struct PerDisplayWarmthControl: View {
    let display: DisplayState
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Override")
                        .font(Theme.Typography.ui(11.5, weight: .medium))
                        .foregroundStyle(Theme.Color.textMuted)
                    Text(display.warmthOverridden ? "Custom warmth for this display" : "Follows the global warmth")
                        .font(Theme.Typography.ui(11))
                        .foregroundStyle(Theme.Color.textFaint)
                }
                Spacer()
                Toggle("", isOn: overrideBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(Theme.Color.accent)
                    .accessibilityLabel("Override warmth for \(display.name)")
            }
            if display.warmthOverridden {
                // WarmSlider already renders its own Softer/Warmer caption (and a "Warmth" header when
                // not compact) — so use the compact slider and don't add a second caption row. The
                // "Override · Custom warmth for this display" header above is label enough. (Fixes the
                // duplicate Softer/Warmer.)
                WarmSlider(strength: warmthBinding, model: model, compact: true)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
        .animation(Theme.Motion.controlReveal(reduceMotion: reduceMotion), value: display.warmthOverridden)
    }

    private var overrideBinding: Binding<Bool> {
        Binding(get: { display.warmthOverridden }, set: { model.setWarmthOverride($0, for: display.id) })
    }

    private var warmthBinding: Binding<Double> {
        Binding(get: { display.warmth.strength }, set: { model.setWarmth($0, for: display.id) })
    }
}

// MARK: - Warming-method picker (plain-language per-display layer choice)

/// The de-jargoned per-display warming-method control. Plain labels (Codex): **Standard /
/// Screen tint / Hardware control** map onto the engine's `DisplayMethod` override.
/// Only methods actually usable for this display are offered, so the available options themselves
/// communicate what the hardware/OS supports. (§26 Settings de-jargon.)
private struct WarmingMethodPicker: View {
    let display: DisplayState
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Warming method")
                .font(Theme.Typography.ui(11.5, weight: .medium))
                .foregroundStyle(Theme.Color.textMuted)

            if availableChoices.count == 1, let choice = availableChoices.first {
                Text(choice.label)
                    .font(Theme.Typography.ui(12, weight: .bold))
                    .foregroundStyle(Theme.Color.inkOnAccent)
                    .lineLimit(1)
                    .padding(.vertical, 7)
                    .padding(.horizontal, 16)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Theme.Gradient.sunset)
                            .overlay(Capsule(style: .continuous).strokeBorder(.white.opacity(0.16), lineWidth: 0.5))
                    )
                    .accessibilityLabel("Warming method: \(choice.label)")
            } else {
                BrandSegmentedControl(
                    options: availableChoices,
                    selection: choiceBinding,
                    label: \.label,
                    onChange: { _ in }
                )
            }

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
        var choices: [WarmingMethodChoice] = []
        if priv, display.capabilities.gamma.isSupported { choices.append(.standard) }
        choices.append(.screenTint)                                     // overlay is always available
        if priv, display.capabilities.hardware.isSupported { choices.append(.hardwareControl) }
        return choices
    }

    private var choiceBinding: Binding<WarmingMethodChoice> {
        Binding(
            get: {
                switch display.preferredMethod {
                case .gamma:
                    if availableChoices.contains(.standard) { return .standard }
                case .overlay:
                    if availableChoices.contains(.screenTint) { return .screenTint }
                case .hardware:
                    if availableChoices.contains(.hardwareControl) { return .hardwareControl }
                default:
                    break
                }
                return availableChoices.contains(.standard) ? .standard : .screenTint
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
            return "Advanced warming isn’t available on this Mac, so only a screen tint is possible."
        }
        if !display.capabilities.gamma.isSupported, !display.capabilities.hardware.isSupported {
            return "This display can’t be truly warmed on this Mac — only a screen tint is available."
        }
        return nil
    }
}

/// Plain-language names for the per-display warming method (Settings → Displays → Advanced). Maps to
/// the engine's `DisplayMethod` override: Standard = gamma (the OS white-point true-warm), Screen
/// tint = overlay, Hardware control = DDC.
private enum WarmingMethodChoice: String, CaseIterable, Identifiable {
    case standard, screenTint, hardwareControl
    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard: return "Standard"
        case .screenTint: return "Screen tint"
        case .hardwareControl: return "Hardware control"
        }
    }

    var preferredMethod: DisplayMethod? {
        switch self {
        case .standard: return .gamma
        case .screenTint: return .overlay
        case .hardwareControl: return .hardware
        }
    }
}

// MARK: - Advanced

private struct AdvancedTab: View {
    @Bindable var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            TabHeader(title: "Advanced", subtitle: "Maximum warmth, the reveal shortcut, and per-app exclusions.")

            CozyModeControl(model: model)
            DividerLine()

            // Reveal True Color hotkey — moved here from the former Shortcuts tab, tucked under
            // Maximum warmth (founder). Click the field to rebind; default ⌥⌘T.
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Reveal True Color")
                Text("Instantly see your screen's true colours — bound to a keyboard shortcut.")
                    .font(Theme.Typography.ui(12))
                    .foregroundStyle(Theme.Color.textMuted)

                // The shortcut as a clear, labelled liquid-glass input — mirrors the Schedule "Location"
                // field so it's obvious you're setting a keyboard shortcut (founder), not a bare pill
                // tucked in the corner. The recorder sits on the right; the whole row reads as a field.
                HStack(spacing: 10) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.Color.accentHighlight)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Keyboard shortcut")
                            .font(Theme.Typography.ui(12.5, weight: .medium))
                            .foregroundStyle(Theme.Color.textPrimary)
                        Text("Click to record — default ⌥⌘T")
                            .font(Theme.Typography.ui(11))
                            .foregroundStyle(Theme.Color.textFaint)
                    }
                    Spacer()
                    RevealShortcutRecorder()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .glassSurface(.frost, cornerRadius: Theme.Radius.control)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                )

                // Hold vs Toggle (§3 locked: ship both, default hold) — on-brand glass switcher.
                VStack(alignment: .leading, spacing: 6) {
                    Text("Behaviour")
                        .font(Theme.Typography.ui(12, weight: .medium))
                        .foregroundStyle(Theme.Color.textMuted)
                    HStack {
                        BrandSegmentedControl(
                            options: RevealMode.allCases,
                            selection: Binding(get: { model.revealMode }, set: { model.setRevealMode($0) }),
                            label: { $0 == .hold ? "Hold" : "Toggle" }
                        )
                        .frame(width: 200)
                        Spacer()
                    }
                    Text(model.revealMode == .hold
                         ? "Hold the shortcut to reveal true colour; release to ease warmth back."
                         : "Press the shortcut to reveal true colour; press again to ease it back.")
                        .font(Theme.Typography.ui(12))
                        .foregroundStyle(Theme.Color.textMuted)
                }
                .padding(.top, 2)
            }
            DividerLine()
            ExcludedAppsControl(model: model)

            DividerLine()
            // Emergency reset, relocated from the Displays page (founder): the forceful gamma/DDC
            // restore kept as a quiet safety net without cluttering the main Displays view.
            Button(role: .destructive) {
                model.setEnabled(false)
                model.restoreAllDisplays()
            } label: {
                Label("Restore all displays to neutral", systemImage: "arrow.counterclockwise")
            }
            Text("Restore every display to true color. Disable warming.")
                .font(Theme.Typography.ui(11.5))
                .foregroundStyle(Theme.Color.textFaint)
        }
    }
}

// MARK: - Excluded apps (suspend-while-frontmost picker)

/// Settings → Advanced → Excluded apps. While one of these apps is the frontmost app, Abendrot
/// suspends warming across all displays (true colour) — for colour-critical work. The list is the
/// observed `model.excludedApps`; rows resolve a friendly name + icon from the bundle id, and "Add
/// app…" picks an `.app` via `NSOpenPanel` (the app is not sandboxed, so no entitlement is needed).
private struct ExcludedAppsControl: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel("Excluded apps")
            Text("Abendrot pauses warming (shows true colour) while one of these apps is frontmost — for colour-critical work.")
                .font(Theme.Typography.ui(12))
                .foregroundStyle(Theme.Color.textMuted)

            if model.excludedApps.isEmpty {
                Text("None — add an app below.")
                    .font(Theme.Typography.ui(11.5))
                    .foregroundStyle(Theme.Color.textFaint)
            } else {
                VStack(spacing: 6) {
                    ForEach(model.excludedApps.sorted(), id: \.self) { bundleID in
                        ExcludedAppRow(bundleID: bundleID) {
                            model.removeExcludedApp(bundleID)
                        }
                    }
                }
            }

            Button {
                addApp()
            } label: {
                Label("Add app…", systemImage: "plus")
            }
            .padding(.top, 2)
        }
    }

    /// Pick an application bundle and add its bundle id to the exclusion set. The panel + `Bundle`
    /// read work without entitlements because the app is not sandboxed.
    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let id = Bundle(url: url)?.bundleIdentifier else { return }
        model.addExcludedApp(id)
    }
}

/// One excluded-app row: the app's icon + friendly name (resolved from the bundle id, falling back to
/// the raw id when the app can't be located), and a ✕ to remove it.
private struct ExcludedAppRow: View {
    let bundleID: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if let icon = resolved.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Color.textFaint)
                    .frame(width: 16, height: 16)
            }
            Text(resolved.name)
                .font(Theme.Typography.ui(12.5))
                .foregroundStyle(Theme.Color.textPrimary)
            Spacer()
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.Color.textMuted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(resolved.name) from excluded apps")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Theme.Color.line.opacity(0.4),
                    in: RoundedRectangle(cornerRadius: Theme.Radius.control - 1, style: .continuous))
    }

    /// Resolve a display name + icon from the bundle id via LaunchServices. Falls back to the raw
    /// bundle id and no icon when the app isn't installed / can't be located.
    private var resolved: (name: String, icon: NSImage?) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return (bundleID, nil)
        }
        let name = FileManager.default.displayName(atPath: url.path)
        // Drop a trailing ".app" the display name can carry when the Finder localization is absent.
        let trimmed = name.hasSuffix(".app") ? String(name.dropLast(4)) : name
        return (trimmed, NSWorkspace.shared.icon(forFile: url.path))
    }
}

// MARK: - Maximum warmth (warmest-point ceiling + opt-in expanded range)

/// "Cozy mode" — the maximum-warmth control, reframed as one delightful toggle (no granular slider,
/// founder). Off, the warmest the General slider reaches is 1900K — where blue is already fully removed.
/// On, it unlocks the deepest candle & ember glow: the engine `warmestPoint` drops to `warmestSupported`
/// (~500K), the card ignites into the sunset gradient, and the screen eases warmer immediately. Below
/// 1900K is a real but minimal extra circadian reduction at a real legibility cost — see
/// docs/research/max-warmth-circadian-research.md (Brown et al. 2022; CIE S 026:2018).
struct CozyModeControl: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Hide the "Maximum warmth" section header (onboarding shows the card bare, under its own title).
    var showsSectionLabel: Bool = true
    /// Hide the when-on science caption (onboarding keeps it compact; the detail lives in Settings).
    var showsExplanation: Bool = true
    /// Onboarding behaviour: toggling Cozy only flips the warmest point — the slider thumb stays exactly
    /// put (no jump, no animation), so the warmth deepens/lightens in place and only the fireball thumb +
    /// "Warmest" label crossfade. (Settings keeps the richer "preserve current warmth, unlock headroom".)
    var keepsSliderInPlace: Bool = false

    /// Derived from the actual warmest point so the toggle can never disagree with the engine.
    private var isCozy: Bool { model.state.warmestPoint.value < Kelvin.everydayWarmest.value }
    private var cardShape: RoundedRectangle { RoundedRectangle(cornerRadius: 16, style: .continuous) }

    /// The §13-safe note with both citations as tappable links. Built as an AttributedString so the body
    /// stays faint while the links read as links — accent-coloured + underlined + clickable. (A blanket
    /// `.foregroundStyle` on a markdown Text flattens the link colour, so they didn't look tappable.)
    private var scienceNote: AttributedString {
        let md = "Below ~1900 K blue light is already gone, so going warmer mainly removes green — a deeper, candle-like glow that's lovely at night but harder to read, with little extra circadian benefit. ([Brown et al. 2022](https://journals.plos.org/plosbiology/article?id=10.1371/journal.pbio.3001571); [CIE S 026](https://cie.co.at/publications/cie-system-metrology-optical-radiation-iprgc-influenced-responses-light-0).)"
        var note = (try? AttributedString(markdown: md)) ?? AttributedString(md)
        note.foregroundColor = Theme.Color.textFaint
        for run in note.runs where run.link != nil {
            note[run.range].foregroundColor = Theme.Color.accent
            note[run.range].underlineStyle = .single
        }
        return note
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsSectionLabel {
                SectionLabel("Maximum warmth")
            }

            Button(action: toggle) { card }
                .buttonStyle(.plain)
                .accessibilityElement()
                .accessibilityLabel("Cozy mode")
                .accessibilityValue(isCozy ? "On" : "Off")
                .accessibilityHint("Unlocks the warmest candle and ember glow, below 1900 Kelvin.")
                .accessibilityAddTraits(.isButton)

            if isCozy && showsExplanation {
                Text(scienceNote)
                    .font(Theme.Typography.ui(11))
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .animation(Theme.Motion.warm(reduceMotion: reduceMotion), value: isCozy)
    }

    private var card: some View {
        HStack(spacing: 14) {
            Image(systemName: isCozy ? "flame.fill" : "flame")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(isCozy ? Theme.Color.groundIndigo : Theme.Color.textMuted)
                .shadow(color: isCozy ? Theme.Color.accentHighlight.opacity(0.55) : .clear, radius: 8)
                .scaleEffect(isCozy ? 1 : 0.9)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text("Cozy mode")
                    .font(Theme.Typography.ui(14, weight: .semibold))
                    .foregroundStyle(isCozy ? Theme.Color.groundIndigo : Theme.Color.textPrimary)
                Text("The warmest candle & ember glow.")
                    .font(Theme.Typography.ui(11.5))
                    .foregroundStyle(isCozy ? Theme.Color.groundIndigo.opacity(0.82) : Theme.Color.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            // Display-only switch — the whole card is the hit target; it just mirrors + animates state.
            Toggle("", isOn: .constant(isCozy))
                .toggleStyle(.switch)
                .tint(isCozy ? Theme.Color.groundIndigo : Theme.Color.accent)
                .labelsHidden()
                .allowsHitTesting(false)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                if isCozy {
                    cardShape.fill(Theme.Gradient.sunset)
                    cardShape
                        .fill(LinearGradient(colors: [.white.opacity(0.32), .white.opacity(0.04), .clear],
                                             startPoint: .top, endPoint: .bottom))
                        .blendMode(.softLight)
                } else {
                    cardShape.fill(Color.white.opacity(0.04))
                }
                cardShape.strokeBorder(isCozy ? Color.white.opacity(0.18) : Theme.Color.lineStrong, lineWidth: 0.5)
            }
        }
        .shadow(color: isCozy ? Theme.Color.accentDeep.opacity(0.38) : .clear, radius: 8, y: 2)
        .shadow(color: isCozy ? Theme.Color.accent.opacity(0.28) : .clear, radius: 18)   // ember glow
        .contentShape(cardShape)
    }

    private func toggle() {
        if keepsSliderInPlace {
            // Onboarding: just flip the warmest point. The slider thumb stays exactly where it is (no jump,
            // no enablement animation) — toggling deepens/lightens the warmth in place, so the only motion
            // is the fireball thumb + "Warmest" label crossfading (founder: keep it smooth, minimal). This
            // path deliberately does NOT preserve warmth, so it stays a bare `setWarmestPoint` rather than
            // `setCozy` (which re-pins the screen for the Settings/CLI "unlock headroom" behaviour).
            model.setWarmestPoint(isCozy ? Kelvin.everydayWarmest : Kelvin.warmestSupported)
            return
        }
        // Settings: the richer behaviour — preserve the user's warmth and just unlock headroom, animated.
        // The actual ceiling + warmth move lives in `model.setCozy`, the ONE path the CLI shares, so the
        // card, onboarding's "Looks right", and `abendrot cozy on|off` can never drift.
        withAnimation(Theme.Motion.warm(reduceMotion: reduceMotion)) {
            model.setCozy(!isCozy)
        }
    }
}

// MARK: - Privacy

private struct PrivacyTab: View {
    @Bindable var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TabHeader(title: "Privacy", subtitle: "Local-first. No account, no telemetry by default.")
            privacyPoint("No accessibility permission", "Hold-to-reveal uses a Carbon global hotkey — no accessibility access required.")
            privacyPoint("No screen recording", "Display capabilities are classified, never measured by screen capture.")
            privacyPoint("No location data", "Your sunset is computed from your time zone — or a city you pick yourself — never your GPS. Abendrot never asks for location access.")
            privacyPoint("No sandbox surprises", "Warmth applies locally; nothing about your displays leaves the machine.")
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

// MARK: - Statistics

/// How long Abendrot has actively warmed the Mac (local-only — never sent anywhere). The headline
/// total ticks live via a `TimelineView` while the tab is open; `AppModel` owns the accrual.
private struct StatisticsTab: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            TabHeader(title: "Statistics", subtitle: "How long Abendrot has softened your evenings — counted on this Mac only.")

            // Live readout: refresh the elapsed total once a second while the tab is visible.
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                VStack(alignment: .leading, spacing: 18) {
                    statBlock(title: "Abendrot has warmed your Mac for",
                              value: model.warmedDurationString, big: true)
                    statBlock(title: "Warm sunset counter",
                              value: "\(model.warmSunsetCount)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .glassSurface(.frost, cornerRadius: Theme.Radius.control)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .strokeBorder(.white.opacity(0.06), lineWidth: 1)
            )

            HStack {
                Button(role: .destructive) { model.resetStatistics() } label: {
                    Label("Reset statistics", systemImage: "arrow.counterclockwise")
                }
                Spacer()
            }

            DividerLine()

            Toggle("Collect statistics on this Mac", isOn: Binding(
                get: { model.statsEnabled },
                set: { model.setStatsEnabled($0) }
            ))
            .toggleStyle(.switch)
            .tint(Theme.Color.accent)
            Text("Stored locally and never sent anywhere. Turn off to stop counting.")
                .font(Theme.Typography.ui(11.5))
                .foregroundStyle(Theme.Color.textFaint)
        }
    }

    private func statBlock(title: String, value: String, big: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(Theme.Typography.ui(big ? 12.5 : 11.5))
                .foregroundStyle(Theme.Color.textMuted)
            Text(value)
                .font(Theme.Typography.serif(big ? 27 : 17))
                .monospacedDigit()
                .foregroundStyle(Theme.Color.accentHighlight)
                .contentTransition(.numericText())
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
                    BylineLink()
                }
            }

            // Mission — what it is, framed as the input it changes (no promised sleep outcome, §13).
            Text("Abendrot warms your screen with the evening — on every display, built-in and external — so your screen gives off less blue light as the day winds down. It’s free, open source, and runs entirely on your Mac: no account, no telemetry.")
                .font(Theme.Typography.ui(12.5))
                .foregroundStyle(Theme.Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 18) {
                AboutLink(title: "abendrot.app", systemImage: "globe", url: "https://abendrot.app")
                AboutLink(title: "GitHub", assetImage: "github", url: "https://github.com/matthewrball/abendrot")
            }

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
                SectionLabel("The science")
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
