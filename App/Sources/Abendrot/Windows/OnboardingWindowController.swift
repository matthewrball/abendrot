import AppKit
import QuartzCore
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
    private static let initialContentSize = OnboardingLayout.initialContentSize
    private var hasFitContent = false
    private var pendingResize: (height: CGFloat, animated: Bool)?
    private var resizeTask: Task<Void, Never>?

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

    static func fitContentHeight(_ height: CGFloat, animated: Bool) {
        shared?.fitContentHeight(height, animated: animated)
    }

    private init(model: AppModel) {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.initialContentSize),
            // `.fullSizeContentView` MUST be present at creation for the glass chrome. A controlled card:
            // no `.resizable`/`.miniaturizable` — the only traffic light is close.
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Abendrot"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // A normal frosted window (matches Settings): the content fills it via `FrostBackground`, the OS
        // rounds the corners, and the traffic-light buttons integrate cleanly into the transparent title
        // bar. (Previously a CLEAR floating glass card, which left the traffic lights detached with a weird
        // double border.) Dragging is handled by a SwiftUI drag background in OnboardingView (grab-anywhere,
        // slider-safe), so the window stays NOT movable-by-background — that would steal the WarmSlider's drag.
        window.isMovableByWindowBackground = false

        // `onFinish` just closes the window; all completion bookkeeping lives in `windowWillClose`
        // so the finish path and the close-button path converge on one site.
        let contentView = NSView(frame: NSRect(origin: .zero, size: Self.initialContentSize))
        contentView.autoresizesSubviews = true
        contentView.wantsLayer = true
        contentView.layer?.masksToBounds = true

        let hosting = NSHostingView(
            rootView: OnboardingView(
                model: model,
                onFinish: { [weak window] in window?.close() },
                onHeightChange: { height, animated in
                    OnboardingWindowController.fitContentHeight(height, animated: animated)
                }
            )
        )
        hosting.frame = contentView.bounds
        hosting.autoresizingMask = [.width, .height]
        hosting.sizingOptions = []
        hosting.wantsLayer = true
        hosting.layer?.masksToBounds = true
        contentView.addSubview(hosting)

        // Do not install the SwiftUI host as `contentViewController`: on macOS 26 its window-layout
        // observer can try to auto-resize the NSWindow from inside AppKit's display cycle. The plain AppKit
        // content view owns the backing size; SwiftUI only fills that box.
        window.contentView = contentView
        window.setContentSize(Self.initialContentSize)
        window.center()

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func fitContentHeight(_ height: CGFloat, animated: Bool) {
        guard height > 1 else { return }
        pendingResize = (height, animated)
        resizeTask?.cancel()
        resizeTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled else { return }
            self?.applyPendingResize()
        }
    }

    private func applyPendingResize() {
        guard let pendingResize else { return }
        self.pendingResize = nil
        resizeTask = nil
        let shouldCenter = !hasFitContent
        resizeContent(to: pendingResize.height, animated: pendingResize.animated && hasFitContent, center: shouldCenter)
        hasFitContent = true
    }

    private func resizeContent(to height: CGFloat, animated: Bool, center: Bool) {
        guard let window else { return }
        let contentHeight = min(
            max(height, OnboardingLayout.minimumContentHeight),
            OnboardingLayout.maximumContentHeight
        )
        var frame = window.frame
        guard abs(frame.height - contentHeight) > 0.5 || abs(frame.width - OnboardingLayout.contentWidth) > 0.5 else { return }

        frame.origin.y = frame.maxY - contentHeight
        frame.size = NSSize(width: OnboardingLayout.contentWidth, height: contentHeight)
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Theme.Motion.durOnboardingResize
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.86, 0.28, 1)
                context.allowsImplicitAnimation = true
                window.animator().setFrame(frame, display: true)
            } completionHandler: {
                Task { @MainActor in
                    window.contentView?.needsDisplay = true
                }
            }
        } else {
            window.setFrame(frame, display: true)
            if center { window.center() }
        }
    }

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
        resizeTask?.cancel()
        // Mark onboarding done whether the user finished or just closed it — never nag twice.
        UserDefaults.standard.set(true, forKey: AppModel.hasCompletedOnboardingKey)
        AppActivationPolicy.leave()
        Self.shared = nil
    }
}
