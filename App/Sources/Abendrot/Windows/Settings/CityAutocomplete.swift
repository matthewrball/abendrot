import SwiftUI
import WarmthKit

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
