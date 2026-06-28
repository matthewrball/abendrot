import SwiftUI

struct UpdatesTab: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            TabHeader(title: "Updates", subtitle: "Manage app updates and new releases.")
            UpdateSettingsView(model: model, showsSectionLabel: false)
        }
        .toggleStyle(.switch)
        .tint(Theme.Color.accent)
    }
}
