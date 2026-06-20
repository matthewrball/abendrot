import Foundation
import Logging
#if canImport(AppKit)
import AppKit
#endif

// MARK: - FrontmostAppMonitor

/// Observes **frontmost-app changes** (`NSWorkspace.didActivateApplicationNotification`) and forwards
/// the newly-activated app's bundle id to the engine, so it can suspend warmth across all displays
/// while an *excluded* app is frontmost (true colour for colour-critical work) and resume when focus
/// leaves it. The engine owns the membership check (`setExcludedApps`), so this is a thin bridge.
///
/// Mirrors `SystemWakeObserver`/`HotkeyService`: `NSWorkspace.shared.notificationCenter` posts on the
/// main thread and `NSWorkspace` is main-actor API, so this is `@MainActor`. Each activation hops onto
/// the `WarmthEngine` actor via `setFrontmostApp`. When AppKit is unavailable (it always is on macOS,
/// but this keeps the target portable) nothing is observed and the engine simply never suspends.
@MainActor
public final class FrontmostAppMonitor {
    private let engine: WarmthEngine
    private let logger = Logger(label: "com.abendrot.WarmthKit.FrontmostAppMonitor")

    #if canImport(AppKit)
    private var token: NSObjectProtocol?
    #endif

    public init(engine: WarmthEngine) {
        self.engine = engine
    }

    /// Begin observing frontmost-app changes and seed the engine with the current frontmost app.
    /// Idempotent.
    public func start() {
        #if canImport(AppKit)
        guard token == nil else { return }
        let engine = self.engine
        token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { note in
            // `queue: .main` guarantees main-thread delivery; read the activated app here and hop to
            // the actor with just the (Sendable) bundle id.
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleID = app?.bundleIdentifier
            Task { await engine.setFrontmostApp(bundleID) }
        }
        // Seed once so a launch while an excluded app is already frontmost suspends immediately,
        // rather than waiting for the next activation.
        let seed = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        Task { await engine.setFrontmostApp(seed) }
        #endif
    }

    /// Stop observing. Safe to call repeatedly.
    public func stop() {
        #if canImport(AppKit)
        if let token {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
            self.token = nil
        }
        #endif
    }
}
