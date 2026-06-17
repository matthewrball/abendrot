import SwiftUI
import AppKit
import WarmthKit

// MARK: - AbendrotApp
//
// The app entry. An `LSUIElement` agent app (set in Info.plist via project.yml): no
// Dock icon, no Cmd-Tab. The whole UI hangs off a `MenuBarExtra` with the provisional
// sunset-arc template glyph. Settings open as a programmatic glass window
// (`SettingsWindowController`), NOT a SwiftUI `Window` scene (see that file's note).
//
// Lifecycle: `AppModel.start()` boots the engine + reveal hotkey; `shutdown()`
// neutral-resets every display on quit.
@main
struct AbendrotApp: App {
    @State private var model = AppModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Hand the model to the delegate so the app-quit hook can neutral-reset displays.
        appDelegate.bind(model: model)
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: model)
        } label: {
            // Provisional template glyph; the real icon + amber-active glow are
            // not finalized yet. TODO: swap in the final icon + amber active state.
            Image(nsImage: MenuBarGlyph.image())
        }
        .menuBarExtraStyle(.window)

        // A SwiftUI Settings scene only so ⌘, / `openSettings()` resolve; the real glass
        // window is the programmatic one. This scene routes to it.
        Settings {
            SettingsLauncher(model: model)
        }
    }
}

// MARK: - SettingsLauncher
//
// Bridges SwiftUI's `Settings` scene (and the `openSettings` action used from the
// popover footer) to the programmatic glass `SettingsWindowController`.
private struct SettingsLauncher: View {
    @Bindable var model: AppModel
    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .onAppear {
                SettingsWindowController.show(model: model)
            }
    }
}

// MARK: - AppDelegate

/// Owns app-level lifecycle the SwiftUI `App` can't express directly: engine start on
/// launch, neutral-reset on quit, and the menu-bar-only activation policy.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private weak var model: AppModel?

    @MainActor
    func bind(model: AppModel) {
        self.model = model
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Start as a menu-bar-only agent; windows raise it via AppActivationPolicy.
        NSApp.setActivationPolicy(.accessory)
        Task { @MainActor in
            model?.start()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Neutral-reset every display before exit (quit guarantee).
        // The reset runs on the main actor, so we can't block the main thread waiting
        // for it (a DispatchSemaphore.wait here would deadlock the very Task it awaits).
        // Instead defer termination with .terminateLater, run the async shutdown, then
        // tell AppKit it's safe to exit. The displays are neutral-reset before the
        // process exits, without blocking the main thread.
        guard let model else { return .terminateNow }
        Task { @MainActor in
            await model.shutdown()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
