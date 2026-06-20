import Foundation
import CoreGraphics
import Logging
#if canImport(AppKit)
import AppKit
#endif

// MARK: - FrontmostAppMonitor

/// Observes **frontmost-app changes** (`NSWorkspace.didActivateApplicationNotification`) and forwards
/// the newly-activated app's bundle id — plus the set of displays its on-screen windows occupy — to the
/// engine, so it can suspend warmth while an *excluded* app is frontmost (true colour for colour-critical
/// work) and resume when focus leaves it. The engine owns the membership check (`setExcludedApps`), so
/// this stays a thin bridge: it only reports *which* app is front and *where* its windows are.
///
/// **Per-display refinement (Session 9):** on a multi-monitor setup the engine suspends warmth ONLY on
/// the display(s) the excluded app's windows sit on, keeping the other monitors warm. The display set is
/// resolved here, permission-free, from `CGWindowListCopyWindowInfo` window *metadata* — `kCGWindowBounds`
/// (geometry) + `kCGWindowOwnerPID` (owner) — which on macOS 15/26 needs **no Screen Recording** and **no
/// Accessibility** permission. Only the window *title* (`kCGWindowName`) and pixel *capture* are gated by
/// Screen Recording, and this code reads neither. (Apple DTS, Forums thread 126860; behaviour re-verified
/// on macOS 26 Tahoe.) Preserves the app's "No Screen Recording / No Accessibility" privacy promise.
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
            // the actor with just the (Sendable) bundle id + display-id set.
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleID = app?.bundleIdentifier
            let displayIDs = app.flatMap { Self.displayIDs(forPID: $0.processIdentifier) }
            Task { await engine.setFrontmostApp(bundleID, onDisplays: displayIDs) }
        }
        // Seed once so a launch while an excluded app is already frontmost suspends immediately,
        // rather than waiting for the next activation.
        let seed = NSWorkspace.shared.frontmostApplication
        let seedDisplays = seed.flatMap { Self.displayIDs(forPID: $0.processIdentifier) }
        let seedBundle = seed?.bundleIdentifier
        Task { await engine.setFrontmostApp(seedBundle, onDisplays: seedDisplays) }
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

    // MARK: - Permission-free display resolution

    /// The set of `CGDirectDisplayID`s whose bounds intersect any on-screen window owned by `pid`.
    ///
    /// Reads ONLY window *metadata* — `kCGWindowOwnerPID` and `kCGWindowBounds` — from
    /// `CGWindowListCopyWindowInfo(.optionOnScreenOnly | .excludeDesktopElements, kCGNullWindowID)`. That
    /// metadata is returned without any TCC permission on macOS 15/26; only `kCGWindowName` (title) and
    /// pixel capture are gated by Screen Recording, and neither is touched here. No Accessibility either.
    ///
    /// Returns `nil` when no owned on-screen window with usable bounds is found (off-screen, minimised,
    /// or unresolvable) — the engine reads `nil` as "all displays", preserving the legacy whole-app
    /// suspend (and the single-display case where there is nothing to refine).
    static func displayIDs(forPID pid: pid_t) -> Set<CGDirectDisplayID>? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        var displays: Set<CGDirectDisplayID> = []
        for window in windows {
            // Owner PID — the canonical owner key, always present without permission.
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t, ownerPID == pid else {
                continue
            }
            // Window geometry — present and correct without permission. Deliberately NOT reading
            // kCGWindowName (the one Screen-Recording-gated field).
            guard let boundsDict = window[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  !rect.isEmpty else {
                continue
            }
            for id in displayIDs(intersecting: rect) {
                displays.insert(id)
            }
        }
        return displays.isEmpty ? nil : displays
    }

    /// The online displays whose `CGDisplayBounds` intersect `rect` (both in the same global,
    /// top-left-origin CoreGraphics coordinate space `kCGWindowBounds` reports in).
    private static func displayIDs(intersecting rect: CGRect) -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        // First call sizes the result; a window can straddle two monitors, so ask for up to a small cap.
        guard CGGetDisplaysWithRect(rect, 0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetDisplaysWithRect(rect, count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }
}
