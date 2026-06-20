import SwiftUI
import AppKit
import WarmthKit

// MARK: - AbendrotApp
//
// The app entry. An `LSUIElement` agent app (set in Info.plist via project.yml): no
// Dock icon, no Cmd-Tab. The whole UI hangs off a `MenuBarExtra` with the provisional
// sunset-arc template glyph (plan §4.3). Settings open as a programmatic glass window
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
            // "One Ripple" sunset-arc glyph: a monochrome template at rest, ember-amber filled while
            // warming (chosen 2026-06-20 from the menu-bar icon lab). Reactive via @Observable model.
            Image(nsImage: model.isWarmingActive ? MenuBarGlyph.active() : MenuBarGlyph.template())
        }
        .menuBarExtraStyle(.window)
        // (First-run onboarding is presented imperatively from `AppModel.applyPersistedState()`, not via
        // a Scene `.onChange` here — that has no prior art on `MenuBarExtra` and isn't guaranteed to fire
        // on a cold launch where the menu is never clicked.)
        // Replace AppKit's default About panel: the standard "About Abendrot" menu item
        // (and any caller of `orderFrontStandardAboutPanel`) opens our branded glass
        // `AboutWindowController` instead. `model` is in scope from the App body.
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Abendrot") {
                    AboutWindowController.show(model: model)
                }
            }
        }

        // TODO(pre-release): REMOVE before shipping — a DEV-ONLY menu-bar item to replay the onboarding
        // flow on demand for testing (founder request, Session 11). Deliberately a SEPARATE menu-bar item
        // (default `.menu` style → a small ✨ pull-down) so it stays OUT of the main popover and doesn't
        // clutter the UI under test. Delete this whole scene to remove. NOT gated behind `#if DEBUG`
        // because the founder dogfoods the Release build.
        MenuBarExtra("Replay onboarding", systemImage: "sparkles") {
            Button("Replay onboarding") {
                OnboardingWindowController.show(model: model)
            }
            Button("Reset onboarding flag (next launch shows it)") {
                UserDefaults.standard.removeObject(forKey: AppModel.hasCompletedOnboardingKey)
            }
        }

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
            .background(SettingsHostWindowDismisser())
            .onAppear {
                SettingsWindowController.show(model: model)
            }
    }
}

// The SwiftUI `Settings` scene exists only so ⌘, resolves; it hosts the 1×1 launcher above that opens
// the real glass window. Without this, that invisible host window LINGERS after the glass window closes,
// so a second ⌘, finds it already open and `onAppear` never re-fires → Settings won't reopen. Closing the
// host right after it appears makes each ⌘, recreate it and re-trigger the launch. (The popover gear calls
// `SettingsWindowController.show` directly and doesn't go through this scene at all.)
private struct SettingsHostWindowDismisser: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in view?.window?.close() }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
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
        // Neutral-reset every display before exit (contract §9 quit guarantee).
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
