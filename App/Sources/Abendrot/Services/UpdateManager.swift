import Sparkle
import SwiftUI

@MainActor
final class UpdateManager: ObservableObject {
    static let shared = UpdateManager()

    private let updaterController: SPUStandardUpdaterController?

    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyDownloadsUpdates = false
    @Published private(set) var updaterUnavailableReason: String?

    private init() {
        if Self.hasUsableUpdateConfiguration {
            let controller = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
            updaterController = controller
            if controller.updater.automaticallyChecksForUpdates {
                controller.updater.checkForUpdatesInBackground()
            }
        } else {
            updaterController = nil
            updaterUnavailableReason = "Updates are unavailable in this build."
        }
        refresh()
    }

    func checkForUpdates() {
        guard let updaterController else {
            refresh()
            return
        }
        updaterController.checkForUpdates(nil)
        refresh()
    }

    func setAutomaticallyDownloadsUpdates(_ enabled: Bool) {
        guard let updater = updaterController?.updater else {
            refresh()
            return
        }
        updater.automaticallyChecksForUpdates = enabled
        updater.automaticallyDownloadsUpdates = enabled
        refresh()
    }

    func refresh() {
        guard let updater = updaterController?.updater else {
            canCheckForUpdates = false
            automaticallyDownloadsUpdates = false
            updaterUnavailableReason = "Updates are unavailable in this build."
            return
        }
        canCheckForUpdates = updater.canCheckForUpdates
        automaticallyDownloadsUpdates = updater.automaticallyChecksForUpdates
            && updater.automaticallyDownloadsUpdates
        updaterUnavailableReason = nil
    }

    private static var hasUsableUpdateConfiguration: Bool {
        #if DEBUG
        return false
        #else
        let publicKey = (Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let feedURLString = (Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return !publicKey.isEmpty
            && !publicKey.localizedCaseInsensitiveContains("PLACEHOLDER")
            && URL(string: feedURLString) != nil
        #endif
    }
}

@MainActor
struct CheckForUpdatesView: View {
    @ObservedObject private var updates: UpdateManager

    init(updates: UpdateManager = .shared) {
        _updates = ObservedObject(wrappedValue: updates)
    }

    var body: some View {
        Button("Check for Updates...") {
            updates.checkForUpdates()
        }
        .disabled(!updates.canCheckForUpdates)
        .onAppear { updates.refresh() }
    }
}

@MainActor
struct UpdateSettingsView: View {
    @Bindable var model: AppModel
    @ObservedObject private var updates: UpdateManager
    var showsSectionLabel = true

    init(model: AppModel, updates: UpdateManager = .shared, showsSectionLabel: Bool = true) {
        self.model = model
        _updates = ObservedObject(wrappedValue: updates)
        self.showsSectionLabel = showsSectionLabel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsSectionLabel {
                SectionLabel("Updates")
            }
            HStack {
                Text("Download updates automatically").font(Theme.Typography.ui(13))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { updates.automaticallyDownloadsUpdates },
                    set: { enabled in
                        guard enabled != updates.automaticallyDownloadsUpdates else { return }
                        updates.setAutomaticallyDownloadsUpdates(enabled)
                        if updates.automaticallyDownloadsUpdates == enabled {
                            model.playSoftToggleTone(on: enabled)
                        }
                    }
                ))
                .labelsHidden()
                .disabled(updates.updaterUnavailableReason != nil)
            }
            if let reason = updates.updaterUnavailableReason {
                Text(reason)
                    .font(Theme.Typography.ui(11.5))
                    .foregroundStyle(Theme.Color.textFaint)
            }
            Button {
                updates.checkForUpdates()
            } label: {
                Label("Check for Updates...", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.liquidGlass)
            .disabled(!updates.canCheckForUpdates)
        }
        .onAppear { updates.refresh() }
    }
}
