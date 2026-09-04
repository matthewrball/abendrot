#if APP_STORE
import SwiftUI

struct UpdateSettingsView: View {
    var showsSectionLabel = true

    init(model _: AppModel, showsSectionLabel: Bool = true) {
        self.showsSectionLabel = showsSectionLabel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsSectionLabel {
                SectionLabel("Updates")
            }
            Label("Updates are delivered through the Mac App Store.", systemImage: "checkmark.seal")
                .font(Theme.Typography.ui(12.5))
                .foregroundStyle(Theme.Color.textMuted)
        }
    }
}
#endif
