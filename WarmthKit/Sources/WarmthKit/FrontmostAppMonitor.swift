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

        let desktopLevel = Int(CGWindowLevelForKey(.desktopIconWindow))
        let backdropLevel = Int(CGWindowLevelForKey(.desktopWindow)) + 1
        var firstContent: CGRect?
        var layerZero: [PausePolicy.ListedWindow] = []
        var backdrops: [PausePolicy.BackdropWindow] = []
        for window in windows {
            let layer = window[kCGWindowLayer as String] as? Int ?? 0
            guard layer == 0 || layer == desktopLevel || layer == backdropLevel else { continue }
            guard let boundsDict = window[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  !rect.isEmpty else {
                continue
            }
            let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t ?? -1
            if layer != 0 {
                if let kind = backdropKind(layer: layer, ownerPID: ownerPID,
                                           desktopLevel: desktopLevel, backdropLevel: backdropLevel) {
                    backdrops.append(PausePolicy.BackdropWindow(bounds: rect, kind: kind))
                }
                continue
            }
            // Exclusion still follows the focused window. Full screen only counts a normal
            // dock app. An accessory overlay such as Cua Driver can cover the built-in display
            // without being full screen, and must not turn warmth off.
            if countsAsFullScreenWindow(window, ownerPID: ownerPID) {
                layerZero.append(PausePolicy.ListedWindow(bounds: rect, layer: 0, owner: ownerPID))
            }
            if firstContent == nil, ownerPID == pid {
                firstContent = rect
            }
        }
        let listed = onlineDisplays()
        let covered = PausePolicy.fullScreenDisplayIDs(
            ownedWindows: layerZero,
            displays: listed.displays,
            mirroring: listed.mirroring,
            fullScreenSpaces: PausePolicy.fullScreenSpaceDisplayIDs(
                backdrops: backdrops,
                displays: listed.displays
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

    /// Finder's desktop at the desktop-icon level, or the Dock's backdrop just above the desktop.
    /// Matched by bundle id, so a renamed or localized owner name does not matter.
    nonisolated private static func backdropKind(
        layer: Int,
        ownerPID: pid_t,
        desktopLevel: Int,
        backdropLevel: Int
    ) -> PausePolicy.BackdropWindow.Kind? {
        #if canImport(AppKit)
        let bundleID = NSRunningApplication(processIdentifier: ownerPID)?.bundleIdentifier
        if layer == desktopLevel, bundleID == "com.apple.finder" { return .desktop }
        if layer == backdropLevel, bundleID == "com.apple.dock" { return .fullScreenBackdrop }
        #endif
        return nil
    }

    /// A covering window counts only when a person could be using that app full screen.
    /// Invisible windows and accessory overlays (Cua Driver covers this Mac's built-in display)
    /// are not full screen.
    nonisolated private static func countsAsFullScreenWindow(
        _ window: [String: Any],
        ownerPID: pid_t
    ) -> Bool {
        let alpha = window[kCGWindowAlpha as String] as? Double ?? 1
        guard alpha > 0.01 else { return false }
        #if canImport(AppKit)
        guard let app = NSRunningApplication(processIdentifier: ownerPID) else { return false }
        return app.activationPolicy == .regular
        #else
        return true
        #endif
    }

    /// Online, not merely active: a hardware mirror is not drawable, so `CGGetActiveDisplayList`
    /// omits it, but gamma and DDC still warm it. `mirroring` maps that display to the one it copies.
    nonisolated private static func onlineDisplays() -> (
        displays: [PausePolicy.ListedDisplay],
        mirroring: [CGDirectDisplayID: CGDirectDisplayID]
    ) {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return ([], [:]) }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return ([], [:]) }
        var mirroring: [CGDirectDisplayID: CGDirectDisplayID] = [:]
        let displays = ids.prefix(Int(count)).map { id -> PausePolicy.ListedDisplay in
            let source = CGDisplayMirrorsDisplay(id)
            if source != 0, source != id { mirroring[id] = source }
            return PausePolicy.ListedDisplay(id: id, bounds: CGDisplayBounds(id))
        }
        return (displays, mirroring)
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
