import AppKit
import SwiftUI

// MARK: - OnboardingWindowController
//
// The first-run "3 clicks to warmth" window, shown ONCE on first launch by a direct imperative
// `OnboardingWindowController.show(model:)` call in `AppModel.applyPersistedState()` (when no
// completion flag exists). NOT driven by a Scene observer — that has no prior art on `MenuBarExtra`.
// The dev "Replay onboarding" menu-bar item also calls `show` on demand.
//
// Mirrors `AboutWindowController`'s programmatic glass pattern: a SwiftUI `Window` scene can't
// carry the Liquid Glass chrome (`.fullSizeContentView` must be set at window *creation* and
// SwiftUI resets it), so we host `OnboardingView` in an `NSHostingController` inside an NSWindow
// we build ourselves. Unlike the frosted Settings/About windows this is a CLEAR, floating glass
// card — lighter for a welcome, and it echoes the menu-bar popover the user is about to use.
//
// A singleton, with `AppActivationPolicy.enter()/leave()` so this `.accessory` agent app
// foregrounds the card and flips back to menu-bar-only when it closes. Completion is written in
// `windowWillClose`, covering BOTH the finish button (which closes the window) and a manual
// dismiss (the close button) — so a user who bails is not nagged on the next launch.
@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {

    private static var shared: OnboardingWindowController?

    /// Open (or re-focus) the onboarding window for the given model.
    static func show(model: AppModel) {
        Task { @MainActor in
            if let existing = shared {
                existing.focus()
                return
            }
            let controller = OnboardingWindowController(model: model)
            shared = controller
            // enter() exactly once per open, paired 1:1 with the single `windowWillClose` leave().
            // Re-focusing an already-open window must NOT enter() again, or the counter strands the
            // app in `.regular` (Dock icon / Cmd-Tab) after the window closes.
            AppActivationPolicy.enter()
            controller.focus()
        }
    }

    private init(model: AppModel) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 520),
            // `.fullSizeContentView` MUST be present at creation for the glass chrome. A fixed card:
            // no `.resizable`/`.miniaturizable` — the only traffic light is close.
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Abendrot"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // Clear window so the rounded glass card floats (popover-style), not a frosted box.
        window.isOpaque = false
        window.backgroundColor = .clear
        // NOT grab-anywhere (unlike About): step 2 carries the WarmSlider, and movable-by-background
        // would steal its drag and move the whole window instead — the exact bug SettingsWindowController
        // fixes the same way. The window still drags by its transparent title-bar strip.
        window.isMovableByWindowBackground = false
        window.center()

        // `onFinish` just closes the window; all completion bookkeeping lives in `windowWillClose`
        // so the finish path and the close-button path converge on one site.
        let hosting = NSHostingController(
            rootView: OnboardingView(model: model) { [weak window] in window?.close() }
        )
        window.contentViewController = hosting

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // Front the window. The activation-policy `enter()` is owned by `show()` (once per open), NOT
    // here — `focus()` runs on every re-focus and must stay balanced against the single `leave()`.
    private func focus() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        // `.accessory` agent apps don't reliably foreground a window via activate() alone; this is a
        // pure z-order safety net (key status is already set by makeKeyAndOrderFront above).
        window?.orderFrontRegardless()
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // Mark onboarding done whether the user finished or just closed it — never nag twice.
        UserDefaults.standard.set(true, forKey: AppModel.hasCompletedOnboardingKey)
        AppActivationPolicy.leave()
        Self.shared = nil
    }
}
