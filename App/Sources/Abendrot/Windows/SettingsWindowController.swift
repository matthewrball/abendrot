import AppKit
import SwiftUI

// MARK: - SettingsWindowController
//
// Programmatic settings window (plan §4.4, reference doc). A SwiftUI `Window` scene
// CANNOT carry the Liquid Glass chrome because `.fullSizeContentView` must be set at
// window *creation* and SwiftUI resets it — so we host `SettingsView` in an
// `NSHostingController` inside an NSWindow we build ourselves, with the full glass
// style mask from the start.
//
// A singleton so re-opening Settings re-focuses the existing window. Uses
// `AppActivationPolicy.enter()/leave()` so this `.accessory` agent app foregrounds
// the window correctly and flips back to menu-bar-only when it closes.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {

    private static var shared: SettingsWindowController?

    /// Open (or re-focus) the Settings window for the given model.
    static func show(model: AppModel) {
        if let existing = shared {
            existing.focus()
            return
        }
        let controller = SettingsWindowController(model: model)
        shared = controller
        controller.focus()
    }

    private init(model: AppModel) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 460),
            // `.fullSizeContentView` MUST be present at creation for the glass chrome.
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Abendrot Settings"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // NOT movable-by-background: a draggable background steals mouse-drags from the custom
        // WarmSlider (a SwiftUI shape whose hit area reports mouseDownCanMoveWindow = true), so the
        // window moved instead of the slider thumb. The window stays draggable by its transparent
        // title-bar strip (where the traffic-light buttons live). (Settings slider-drag bug fix.)
        window.isMovableByWindowBackground = false
        window.center()
        window.setFrameAutosaveName("AbendrotSettings")

        let hosting = NSHostingController(rootView: SettingsView(model: model))
        window.contentViewController = hosting

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func focus() {
        AppActivationPolicy.enter()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        AppActivationPolicy.leave()
        Self.shared = nil
    }
}
