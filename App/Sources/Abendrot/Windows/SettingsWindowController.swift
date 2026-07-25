import AppKit
import SwiftUI

// MARK: - SettingsWindowController
//
// Programmatic settings window. A SwiftUI `Window` scene
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
    /// First content-fit (on open) is instant; later fits (mode/tab changes) animate.
    private var hasFitContent = false

    /// Open (or re-focus) the Settings window for the given model, optionally deep-linking a tab.
    ///
    /// Two things have to happen, in order:
    /// 1. Dismiss the `MenuBarExtra(.window)` dropdown. SwiftUI only auto-dismisses it on
    /// app-deactivate / outside-click — NOT when another same-app window (Settings) becomes key.
    /// Left open it lingers behind Settings, resigns key, and its `.switch` master toggle
    /// desaturates to grey (warming is still on). We close it here, while it's still the key
    /// window at click time. (Also the desired UX: clicking the gear closes the dropdown.)
    /// 2. Open / raise Settings on the NEXT main-actor turn, so the dropdown teardown settles before
    /// we front the window; `orderFrontRegardless` in `focus()` forces it up for this `.accessory`
    /// agent app.
    static func show(model: AppModel, tab: SettingsTab? = nil, focusExcludedApps: Bool = false) {
        // Close the dropdown now, while it's still key. Guard against closing the Settings window
        // itself (the re-focus path, where Settings may already be the key/last-key window).
        if let dropdown = NSApp.keyWindow, dropdown !== shared?.window {
            dropdown.close()
        }
        Task { @MainActor in
            // Set the tab BEFORE the early return so re-focusing an already-open window also
            // deep-links (clicking "Manage…" while Settings is open jumps it to Advanced).
            if let tab { model.settingsTab = tab }
            if focusExcludedApps { model.excludedAppsFocusRequest = UUID() }
            if let existing = shared {
                existing.focus()
                return
            }
            let controller = SettingsWindowController(model: model)
            shared = controller
            // enter() exactly once per open, paired 1:1 with the single `windowWillClose` leave().
            // Re-focusing an already-open window must NOT enter() again, or the counter strands the
            // app in `.regular` (Dock icon / Cmd-Tab) after the window closes.
            AppActivationPolicy.enter()
            controller.focus()
        }
    }

    /// Resize the Settings window so the detail pane exactly hugs `contentHeight` — the current tab's
    /// natural content height, measured by SettingsView. Keeps the width and the TOP edge fixed (grows /
    /// shrinks downward). The first fit (on open) is instant; later fits — switching tab, or toggling
    /// Sunset ⇄ Always-on which shows/hides Location — animate, so the window follows the content like
    /// macOS System Settings does between panes.
    static func fitDetailContentHeight(_ contentHeight: CGFloat) {
        guard contentHeight > 1, let ctrl = shared, let win = ctrl.window else { return }
        let titlebar = max(0, win.frame.height - win.contentLayoutRect.height)
        let target = max(contentHeight + titlebar, win.minSize.height)
        let current = win.frame
        guard abs(current.height - target) > 1 else { return }
        var f = current
        f.size.height = target
        if ctrl.hasFitContent {
            f.origin.y = current.maxY - target              // later fits: keep the TOP edge fixed (grows/shrinks downward)
            win.setFrame(f, display: true, animate: true)
        } else {
            win.setFrame(f, display: true, animate: false)  // first fit (on open): size to content…
            win.center()                                    // …then center on the main display
        }
        ctrl.hasFitContent = true
    }

    private init(model: AppModel) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 824),
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
        window.minSize = NSSize(width: 700, height: 520)
        window.center()

        let hosting = NSHostingController(rootView: SettingsView(model: model))
        window.contentViewController = hosting
        // The window then resizes to HUG each tab's content height (see `fitDetailContentHeight`, driven by
        // a height preference in SettingsView): General is taller in Sunset, with Location, than in
        // Always-on, so the window follows — no bottom gap, no clipping, in either mode or any tab.

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
        AppActivationPolicy.leave()
        Self.shared = nil
    }
}
