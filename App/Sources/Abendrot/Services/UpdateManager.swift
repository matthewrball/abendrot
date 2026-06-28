import Sparkle
import SwiftUI

@MainActor
final class UpdateManager: ObservableObject {
    static let shared = UpdateManager()

    private let updaterController: SPUStandardUpdaterController?

    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyInstallsUpdates = false
    @Published private(set) var updaterUnavailableReason: String?

    private init() {
        if Self.hasUsableUpdateConfiguration {
            updaterController = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
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

    func setAutomaticallyInstallsUpdates(_ enabled: Bool) {
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
            automaticallyInstallsUpdates = false
            updaterUnavailableReason = "Updates are unavailable in this build."
            return
        }
        canCheckForUpdates = updater.canCheckForUpdates
        automaticallyInstallsUpdates = updater.automaticallyChecksForUpdates
            && updater.automaticallyDownloadsUpdates
        updaterUnavailableReason = nil
    }

    private static var hasUsableUpdateConfiguration: Bool {
        let publicKey = (Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let feedURLString = (Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return !publicKey.isEmpty
            && !publicKey.localizedCaseInsensitiveContains("PLACEHOLDER")
            && URL(string: feedURLString) != nil
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
                Text("Install updates automatically").font(Theme.Typography.ui(13))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { updates.automaticallyInstallsUpdates },
                    set: { enabled in
                        guard enabled != updates.automaticallyInstallsUpdates else { return }
                        updates.setAutomaticallyInstallsUpdates(enabled)
                        if updates.automaticallyInstallsUpdates == enabled {
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
