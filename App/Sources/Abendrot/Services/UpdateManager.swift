import AppKit
import Sparkle
import SwiftUI

@MainActor
final class UpdateManager: ObservableObject {
    static let shared = UpdateManager()

    private let updaterController: SPUStandardUpdaterController?
    // Sparkle references its delegates weakly (SPUStandardUpdaterController.h), so we own this.
    private let updaterDelegate = UpdaterDelegate()

    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyDownloadsUpdates = false
    @Published private(set) var updaterUnavailableReason: String?

    private init() {
        if Self.hasUsableUpdateConfiguration {
            let controller = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: updaterDelegate,
                userDriverDelegate: nil
            )
            updaterController = controller
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
        let publicKey = (Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let feedURLString = (Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return !publicKey.isEmpty
            && !publicKey.localizedCaseInsensitiveContains("PLACEHOLDER")
            && feedURLString == "https://raw.githubusercontent.com/matthewrball/abendrot/main/appcast.xml"
    }
}

// MARK: - UpdaterDelegate
//
// Two hooks, both fixing the same symptom: pushing a release and relaunching prompted nothing.
// Out of the box Sparkle checks at most once per `SUScheduledCheckInterval` (24h) and, with
// automatic downloads on, installs silently on quit — so a relaunch neither checks nor asks.
@MainActor
final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    // Sparkle calls the hook below after every *completed* check too, so without this latch the
    // forced check would retrigger itself forever.
    private var didForceLaunchCheck = false

    /// Sparkle compares `now - SULastCheckTime` against the 24h interval and, when it hasn't
    /// elapsed, only arms a timer — see `-scheduleNextUpdateCheckFiringImmediately:usingCurrentDate:`
    /// in `SPUUpdater.m`. Relaunching does not reset that persisted date, so a relaunch checks
    /// nothing. This callback *is* that "not yet" decision, and Sparkle has already cleared
    /// `sessionInProgress` by the time it fires, so we force exactly one check per launch — a
    /// main-queue turn later, to let Sparkle finish arming its timer before we start a session.
    func updater(_ updater: SPUUpdater, willScheduleUpdateCheckAfterDelay delay: TimeInterval) {
        guard !didForceLaunchCheck else { return }
        didForceLaunchCheck = true
        Task { @MainActor in updater.checkForUpdatesInBackground() }
    }

    /// With automatic downloads on, Sparkle hands the check to `SPUAutomaticUpdateDriver`, which
    /// downloads silently and installs on quit showing no UI at all. Returning `true` takes over
    /// that last step so the user is actually asked. Sparkle still installs on quit either way,
    /// which is what makes "Later" a safe answer.
    func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        // Answer Sparkle first, ask the user after: running a modal alert inside Sparkle's own
        // callback would spin a nested run loop mid-install-session.
        Task { @MainActor in
            Self.presentReadyToInstall(item, install: immediateInstallHandler)
        }
        return true
    }

    private static func presentReadyToInstall(
        _ item: SUAppcastItem,
        install: @escaping () -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = "Abendrot \(item.displayVersionString) is ready to install"
        alert.informativeText = """
            The update is already downloaded. Installing now relaunches Abendrot; \
            choosing Later installs it the next time you quit.
            """
        alert.addButton(withTitle: "Install and Relaunch")
        alert.addButton(withTitle: "Later")
        // Agent app: an `.accessory` process can't front a modal alert (see AppActivationPolicy).
        AppActivationPolicy.enter()
        let response = alert.runModal()
        AppActivationPolicy.leave()
        if response == .alertFirstButtonReturn { install() }
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
