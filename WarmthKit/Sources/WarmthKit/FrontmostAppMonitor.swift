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
/// **Per-display refinement:** on a multi-monitor setup the engine suspends warmth ONLY on
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
    /// UI hook for the app in front. Not consulted by the engine. Nil bundle ids are reported too,
    /// so the popover can say there is nothing suitable to exclude.
    public var onFrontmostBundleID: ((String?) -> Void)?

    #if canImport(AppKit)
    private var token: NSObjectProtocol?
    private var spaceToken: NSObjectProtocol?
    private var spaceFollowUp: Task<Void, Never>?
    /// While the full-screen preference is on, sample every 2s. A zoomed or borderless cover can
    /// start or end without an app activation or a Space change.
    private var coverFollowUp: Task<Void, Never>?
    public var watchesFullScreen = false {
        didSet {
            if watchesFullScreen {
                scheduleCoverFollowUp()
            } else {
                coverFollowUp?.cancel()
                coverFollowUp = nil
            }
        }
    }
    #endif

    public init(engine: WarmthEngine) {
        self.engine = engine
    }

    /// Begin observing frontmost-app changes and seed the engine with the current frontmost app.
    /// Idempotent.
    public func start() {
        #if canImport(AppKit)
        guard token == nil else { return }
        let center = NSWorkspace.shared.notificationCenter
        token = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                self?.deliver(app)
            }
        }
        // Entering or leaving native full screen switches Spaces without activating a new app.
        spaceToken = center.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.deliverFrontmostAfterSpaceChange()
            }
        }
        deliver(NSWorkspace.shared.frontmostApplication)
        #endif
    }

    #if canImport(AppKit)
    private func deliverFrontmostAfterSpaceChange() {
        deliver(NSWorkspace.shared.frontmostApplication)
        // The window list can lag the Space change; sample again once it has settled.
        spaceFollowUp?.cancel()
        spaceFollowUp = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            self?.deliver(NSWorkspace.shared.frontmostApplication)
        }
    }

    private func deliver(_ app: NSRunningApplication?, notifyUI: Bool = true) {
        if notifyUI {
            onFrontmostBundleID?(app?.bundleIdentifier)
        }
        let report = app.map { Self.windowReport(forPID: $0.processIdentifier) }
            ?? FrontmostWindowReport(displayIDs: nil, fullScreenDisplayIDs: [])
        scheduleCoverFollowUp()
        let engine = self.engine
        let bundleID = app?.bundleIdentifier
        Task {
            await engine.setFrontmostApp(
                bundleID,
                onDisplays: report.displayIDs,
                fullScreenDisplays: report.fullScreenDisplayIDs
            )
        }
    }

    private func scheduleCoverFollowUp() {
        guard watchesFullScreen else {
            coverFollowUp?.cancel()
            coverFollowUp = nil
            return
        }
        coverFollowUp?.cancel()
        coverFollowUp = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            self?.deliver(NSWorkspace.shared.frontmostApplication, notifyUI: false)
        }
    }
    #endif

    /// Stop observing. Safe to call repeatedly.
    public func stop() {
        #if canImport(AppKit)
        spaceFollowUp?.cancel()
        spaceFollowUp = nil
        coverFollowUp?.cancel()
        coverFollowUp = nil
        let center = NSWorkspace.shared.notificationCenter
        if let token {
            center.removeObserver(token)
            self.token = nil
        }
        if let spaceToken {
            center.removeObserver(spaceToken)
            self.spaceToken = nil
        }
        #endif
    }

    // MARK: - Permission-free display resolution

    /// The set of `CGDirectDisplayID`s the excluded app's **focused** window occupies — i.e. the
    /// display(s) of its FRONTMOST on-screen window, not every window it has open.
    ///
    /// `CGWindowListCopyWindowInfo(.optionOnScreenOnly | ...)` returns windows front-to-back in z-order,
    /// so the first normal (layer-0) window owned by `pid` is its key/focused window. We suspend only
    /// THAT window's display(s): a stray window of the same app on another monitor must not un-warm that
    /// monitor (bug fix — Preview focused on one display was suspending both). A window that
    /// genuinely spans two monitors suspends both (correct — it IS on both).
    ///
    /// Reads ONLY window *metadata* — `kCGWindowOwnerPID`, `kCGWindowLayer`, `kCGWindowBounds`. That
    /// metadata is returned without any TCC permission on macOS 15/26; only `kCGWindowName` (title) and
    /// pixel capture are gated by Screen Recording, and neither is touched here. No Accessibility either.
    ///
    /// Returns `nil` when no owned normal on-screen window with usable bounds is found (off-screen,
    /// minimised, panels-only, or unresolvable) — the engine reads `nil` as "all displays", preserving
    /// the legacy whole-app suspend (and the single-display case where there is nothing to refine).
    nonisolated static func displayIDs(forPID pid: pid_t) -> Set<CGDirectDisplayID>? {
        windowReport(forPID: pid).displayIDs
    }

    /// Focused-window geometry for `pid`. `displayIDs` is the first layer-0 window of that app, so
    /// exclusion still follows the focused window. `fullScreenDisplayIDs` is any display covered by
    /// a layer-0 window, including one left up on another display after focus moves away, plus any
    /// display showing a native full-screen Space.
    nonisolated static func windowReport(forPID pid: pid_t) -> FrontmostWindowReport {
        // Desktop elements stay in the list: Finder's desktop and the Dock's full-screen backdrop
        // are how a native full-screen Space is told apart from a zoomed window.
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
            as? [[String: Any]] else {
            return FrontmostWindowReport(displayIDs: nil, fullScreenDisplayIDs: [])
        }

        var policies: [pid_t: (bundleID: String?, isRegular: Bool)] = [:]
        let lookup: (Int32) -> (bundleID: String?, isRegular: Bool) = { pid in
            if let cached = policies[pid] { return cached }
            let info = appInfo(pid)
            policies[pid] = info
            return info
        }
        let sample = PausePolicy.classify(windowInfo: windows, app: lookup)
        // Exclusion follows the focused window: the first layer-0 window of that app, of any kind.
        let firstContent = windows.lazy.compactMap { window -> CGRect? in
            guard (window[kCGWindowLayer as String] as? Int ?? 0) == 0,
                  (window[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  let boundsDict = window[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  !rect.isEmpty else { return nil }
            return rect
        }.first
        let listed = PausePolicy.onlineDisplays()
        let unmirrored = listed.displays.filter { listed.mirroring[$0.id] == nil }
        // The all-Spaces list is only needed when some display is missing its desktop.
        let desktopsShown = sample.backdrops.filter { $0.kind == .desktop }.count
        let finderDesktopExists = desktopsShown >= unmirrored.count
            || PausePolicy.finderDesktopExists(
                allWindowInfo: CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? [],
                app: lookup)
        let covered = PausePolicy.fullScreenDisplayIDs(
            ownedWindows: sample.regularWindows,
            displays: listed.displays,
            mirroring: listed.mirroring,
            fullScreenSpaces: PausePolicy.fullScreenSpaceDisplayIDs(
                backdrops: sample.backdrops,
                displays: unmirrored,
                ownedWindows: sample.regularWindows,
                finderDesktopExists: finderDesktopExists
            )
        )
        guard let firstContent else {
            return FrontmostWindowReport(displayIDs: nil, fullScreenDisplayIDs: covered)
        }
        let ids = Set(displayIDs(intersecting: firstContent))
        return FrontmostWindowReport(
            displayIDs: ids.isEmpty ? nil : ids,
            fullScreenDisplayIDs: covered
        )
    }

    nonisolated private static func appInfo(_ pid: pid_t) -> (bundleID: String?, isRegular: Bool) {
        #if canImport(AppKit)
        guard let app = NSRunningApplication(processIdentifier: pid) else { return (nil, false) }
        return (app.bundleIdentifier, app.activationPolicy == .regular)
        #else
        return (nil, true)
        #endif
    }

    /// The online displays whose `CGDisplayBounds` intersect `rect` (both in the same global,
    /// top-left-origin CoreGraphics coordinate space `kCGWindowBounds` reports in).
    nonisolated private static func displayIDs(intersecting rect: CGRect) -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        // First call sizes the result; a window can straddle two monitors, so ask for up to a small cap.
        guard CGGetDisplaysWithRect(rect, 0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetDisplaysWithRect(rect, count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }
}

/// Permission-free geometry of the frontmost normal window. No window title, no pixel capture.
public struct FrontmostWindowReport: Sendable, Equatable {
    public var displayIDs: Set<CGDirectDisplayID>?
    public var fullScreenDisplayIDs: Set<CGDirectDisplayID>

    public init(displayIDs: Set<CGDirectDisplayID>?, fullScreenDisplayIDs: Set<CGDirectDisplayID>) {
        self.displayIDs = displayIDs
        self.fullScreenDisplayIDs = fullScreenDisplayIDs
    }
}
