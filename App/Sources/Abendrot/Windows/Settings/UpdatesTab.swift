import SwiftUI

struct UpdatesTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            TabHeader(title: "Updates", subtitle: "Manage app updates and new releases.")
            UpdateSettingsView(showsSectionLabel: false)
        }
        .toggleStyle(.switch)
        .tint(Theme.Color.accent)
    }
}
