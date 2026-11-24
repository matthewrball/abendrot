import AppKit
import ColorSync
import QuartzCore
import WarmthCore
import CInterop

/// Experimental: warms a display around an excluded app's windows, so that app shows true
/// color while the rest of that display stays warm. Picture in picture stays neutral after
/// focus leaves. A click-through panel above everything filters what is behind it through a
/// private compositor color matrix; tiles leave a hole over the visible windows. Window
/// positions come from `CGWindowListCopyWindowInfo` metadata, with no Screen Recording and
/// no Accessibility. Direct distribution only.
@MainActor
public final class WindowFilterBackend: WarmthBackend, ExcludedWindowFilter {
    nonisolated public let method: DisplayMethod = .windowFilter
    /// Keyed by display identity, not `currentDisplayID`. That ID changes across sleep and
    /// hotplug; keying on it opened a second panel and left the first one up.
    private var panels: [DisplayIdentity: WindowFilterPanel] = [:]
    private var gains: [DisplayIdentity: RGBGain] = [:]
    private var tracker: Timer?
    private var observers: [NSObjectProtocol] = []
    /// Follows moves and resizes. 60 Hz keeps a dragged window's fringe to about one frame and
    /// costs well under a millisecond per sample.
    private let trackingInterval: TimeInterval = 1.0 / 60.0

    nonisolated public init() {}

    nonisolated public func classify(_ identity: DisplayIdentity) async -> Capability<Void> {
        WKWindowFilterAvailable() ? .supported(()) : .unsupported(reason: .privateSymbolUnavailable)
    }

    public func apply(_ kelvin: Kelvin, to identity: DisplayIdentity) async throws {
        guard WKWindowFilterAvailable() else { throw WindowFilterError.unavailable }
        let displayID = identity.currentDisplayID
        guard let screen = Self.screen(for: displayID) else { throw WindowFilterError.displayMissing }
        let gain = rgbGain(for: kelvin)
        let panel: WindowFilterPanel
        if let existing = panels[identity], existing.displayID == displayID {
            panel = existing
        } else {
            panels.removeValue(forKey: identity)?.close()
            panel = try WindowFilterPanel(screen: screen, displayID: displayID)
            panels[identity] = panel
        }
        try panel.setGain(gain)
        gains[identity] = gain
        startTracking()
        // Cut the hole before showing the panel so the excluded window never flashes warm.
        refreshHoles()
        panel.show(on: screen)
    }

    public func reset(_ identity: DisplayIdentity) async throws {
        panels.removeValue(forKey: identity)?.close()
        gains.removeValue(forKey: identity)
        if panels.isEmpty { stopTracking() }
    }

    // MARK: Tracking

    private func startTracking() {
        guard tracker == nil else { return }
        let timer = Timer(timeInterval: trackingInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshHoles() }
        }
        RunLoop.main.add(timer, forMode: .common)
        tracker = timer
        let workspace = NSWorkspace.shared.notificationCenter
        let center = NotificationCenter.default
        // A stale WindowServer attachment can accept gain writes without visibly warming.
        observers = [
            workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.rebuildPanels() }
            },
            workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshHoles() }
            },
            center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.rebuildPanels() }
            },
        ]
    }

    private func stopTracking() {
        tracker?.invalidate()
        tracker = nil
        let workspace = NSWorkspace.shared.notificationCenter
        for observer in observers {
            workspace.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
        observers = []
        activationPolicies = [:]
        bundleIDs = [:]
        trackedFloatingDisplays = nil
    }

    private func rebuildPanels() {
        let kept = panels
        panels = [:]
        for (identity, old) in kept {
            old.close()
            let displayID = Self.onlineDisplayID(matching: identity.cgUUID) ?? old.displayID
            guard let screen = Self.screen(for: displayID), let gain = gains[identity],
                  let panel = try? WindowFilterPanel(screen: screen, displayID: displayID),
                  (try? panel.setGain(gain)) != nil else {
                // The engine's next pass reports the failure and falls back to the display pause.
                gains.removeValue(forKey: identity)
                continue
            }
            panels[identity] = panel
        }
        gains = gains.filter { panels[$0.key] != nil }
        guard !panels.isEmpty else {
            stopTracking()
            return
        }
        refreshHoles()
        for (_, panel) in panels {
            if let screen = Self.screen(for: panel.displayID) { panel.show(on: screen) }
        }
    }

    private var cornerRadius: CGFloat?

    /// Whether the last window list came with WindowServer's corner radii (macOS 26 and later).
    private var reportsCornerRadii = false

    /// The transparent margin around this Mac's menu windows. Zero until a menu window proves
    /// one. It depends on the system, so it is kept after tracking stops. It is never stored.
    private var menuMargin: CGFloat = 0

    private var bundleIDs: [pid_t: String] = [:]
    private var excludedBundleIDs: Set<String> = []
    /// The excluded app that was frontmost before the screenshot tool took focus.
    /// Window capture must not close the hole, or the screen flashes warm.
    private var lastExcludedFrontPID: pid_t?
    /// Displays whose excluded floating windows are keeping the filter up after focus left.
    /// Nil until the first sample of that state, so the focus-change pass is not repeated.
    private var trackedFloatingDisplays: Set<CGDirectDisplayID>?
    private var onFloatingWindowsChanged: (@Sendable () -> Void)?

    package func setExcludedApps(_ bundleIDs: Set<String>) async {
        excludedBundleIDs = bundleIDs
    }

    package func setOnFloatingWindowsChanged(_ handler: (@Sendable () -> Void)?) async {
        onFloatingWindowsChanged = handler
    }

    package func displaysWithExcludedFloatingWindows() async -> Set<CGDirectDisplayID> {
        floatingDisplayIDs(in: listedWindows())
    }

    private func refreshHoles() {
        guard !panels.isEmpty else { return }
        if cornerRadius == nil { cornerRadius = WKStandardWindowCornerRadius() }
        let front = NSWorkspace.shared.frontmostApplication
        let capturing = front?.bundleIdentifier == Self.screenCaptureBundleID
        let reportedExcluded = front?.bundleIdentifier.map { excludedBundleIDs.contains($0) } ?? false
        if reportedExcluded, let pid = front?.processIdentifier {
            lastExcludedFrontPID = pid
        }
        // The screenshot tool is not a real focus change. Keep punching the app the user
        // was in, and hide this panel from the window picker.
        let frontExcluded = reportedExcluded || (capturing && lastExcludedFrontPID != nil)
        let owner: pid_t = reportedExcluded
            ? (front?.processIdentifier ?? -1)
            : (capturing ? (lastExcludedFrontPID ?? -1) : -1)
        let windows = listedWindows()
        let floating = floatingOwners(in: windows, besides: owner)
        noteFloatingWindows(in: windows, frontExcluded: frontExcluded)
        if windows.contains(where: { $0.layer == WindowHolePolicy.popUpMenuLayer }),
           let proven = WindowHolePolicy.observedMenuMargin(
               in: windows, displays: Self.onlineDisplayBounds().map(\.bounds)) {
            menuMargin = proven
        }
        for (_, panel) in panels {
            panel.setSharingType(capturing ? .none : .readOnly)
            let display = CGDisplayBounds(panel.displayID)
            let region = WindowHolePolicy.neutralRegion(
                windows: windows,
                owner: owner,
                display: display,
                cornerRadius: cornerRadius ?? 0,
                floatingOwners: floating,
                menuMargin: menuMargin,
                reportsCornerRadii: reportsCornerRadii)
            panel.setTiles(WindowHolePolicy.warmTiles(around: region, in: display), display: display)
        }
    }

    private static let screenCaptureBundleID = "com.apple.screencaptureui"
    private static let stageManagerBundleID = "com.apple.WindowManager"

    /// After focus leaves, the tracking timer is the only thing still running. When the last
    /// floating window closes, or moves to another display, the engine has to choose the layer again.
    private func noteFloatingWindows(in windows: [WindowHolePolicy.Window], frontExcluded: Bool) {
        guard !frontExcluded else {
            trackedFloatingDisplays = nil
            return
        }
        let displays = floatingDisplayIDs(in: windows)
        if trackedFloatingDisplays == nil {
            trackedFloatingDisplays = displays
            if displays.isEmpty { onFloatingWindowsChanged?() }
            return
        }
        guard displays != trackedFloatingDisplays else { return }
        trackedFloatingDisplays = displays
        onFloatingWindowsChanged?()
    }

    private func floatingDisplayIDs(in windows: [WindowHolePolicy.Window]) -> Set<CGDirectDisplayID> {
        let excluded = excludedBundleIDs
        guard !excluded.isEmpty else { return [] }
        let displays = Self.onlineDisplayBounds()
        guard !displays.isEmpty else { return [] }
        var hits: Set<CGDirectDisplayID> = []
        for window in windows {
            // Above the normal window. Desktop windows (layer below 0) are not picture in picture.
            guard window.layer > 0, window.alpha > 0.01, !window.bounds.isEmpty else { continue }
            guard let id = bundleID(for: window.owner), excluded.contains(id) else { continue }
            for display in displays {
                guard window.bounds.intersects(display.bounds),
                      !PausePolicy.coversDisplay(window: window.bounds, display: display.bounds) else { continue }
                hits.insert(display.id)
            }
        }
        return hits
    }

    private static func onlineDisplayBounds() -> [(id: CGDirectDisplayID, bounds: CGRect)] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).map { ($0, CGDisplayBounds($0)) }
    }

    private func floatingOwners(in windows: [WindowHolePolicy.Window], besides frontmost: pid_t) -> Set<Int32> {
        let excluded = excludedBundleIDs
        guard !excluded.isEmpty else { return [] }
        var owners: Set<Int32> = []
        var seen: Set<pid_t> = []
        for window in windows {
            let pid = window.owner
            guard pid != frontmost, seen.insert(pid).inserted else { continue }
            if let id = bundleID(for: pid), excluded.contains(id) {
                owners.insert(pid)
            }
        }
        return owners
    }

    private func bundleID(for pid: pid_t) -> String? {
        if let id = bundleIDs[pid] { return id }
        let id = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        if let id { bundleIDs[pid] = id }
        return id
    }

    /// Activation policy by process, kept while tracking. Cleared when tracking stops.
    private var activationPolicies: [pid_t: Bool] = [:]

    private static let ownPID = ProcessInfo.processInfo.processIdentifier

    private func listedWindows() -> [WindowHolePolicy.Window] {
        guard let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return [] }
        let panelNumbers = Set(panels.values.map(\.windowNumber))
        let reported = Self.cornerRadii(of: raw.compactMap { $0[kCGWindowNumber as String] as? Int })
        reportsCornerRadii = reported != nil
        let radii = reported ?? [:]
        return raw.compactMap { window in
            guard let boundsDict = window[kCGWindowBounds as String] as? [String: Any],
                  var rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { return nil }
            let owner = window[kCGWindowOwnerPID as String] as? pid_t ?? -1
            let layer = window[kCGWindowLayer as String] as? Int ?? 0
            let number = window[kCGWindowNumber as String] as? Int ?? 0
            var radius = radii[number]
            var measured = false
            if owner == Self.ownPID {
                // The warmth panels are not windows a person reads.
                if panelNumbers.contains(number) { return nil }
                // The popover's window includes its arrow and shadow margin. This process can
                // see its own content, so the popover stays warm exactly where it is drawn.
                if let own = NSApp.window(withWindowNumber: number), let visible = Self.visibleBounds(of: own) {
                    rect = visible.bounds
                    radius = visible.cornerRadius ?? radius
                    measured = true
                }
            }
            let regular: Bool
            if let cached = activationPolicies[owner] {
                regular = cached
            } else {
                let app = NSRunningApplication(processIdentifier: owner)
                regular = app?.activationPolicy == .regular
                activationPolicies[owner] = regular
                if let id = app?.bundleIdentifier {
                    bundleIDs[owner] = id
                }
            }
            return WindowHolePolicy.Window(
                bounds: rect,
                layer: layer,
                owner: owner,
                alpha: window[kCGWindowAlpha as String] as? Double ?? 1,
                isRegularApp: regular,
                isMeasured: measured,
                cornerRadius: radius,
                isStageManager: bundleID(for: owner) == Self.stageManagerBundleID
            )
        }
    }

    /// WindowServer's corner radius for each listed window that reports one. Asked on every
    /// sample, not cached: a window has no radius until it is ordered in, and one query for every
    /// on-screen window costs well under a tenth of a millisecond. Older macOS has no such query,
    /// so every radius stays unknown and the hole keeps the titled-window radius as before.
    /// Nil when this macOS has no such query, so a missing radius means nothing.
    private static func cornerRadii(of numbers: [Int]) -> [Int: CGFloat]? {
        let listed = numbers.filter { $0 > 0 && $0 <= Int(UInt32.max) }
        guard !listed.isEmpty else { return [:] }
        let ids = listed.map { UInt32($0) }
        var values = [Double](repeating: 0, count: ids.count)
        guard WKCopyWindowCornerRadii(ids, ids.count, &values) else { return nil }
        var radii: [Int: CGFloat] = [:]
        for (number, value) in zip(listed, values) where value.isFinite && value > 0 && value < 80 {
            radii[number] = CGFloat(value)
        }
        return radii
    }

    /// One of this app's windows, in CoreGraphics global space. A normal window is its frame. A
    /// popover or menu-bar window is its content view, without the arrow and shadow margin, and
    /// takes the radius of the glass it is drawn on, when there is one.
    private static func visibleBounds(of window: NSWindow) -> (bounds: CGRect, cornerRadius: CGFloat?)? {
        guard window.isVisible, let primary = NSScreen.screens.first else { return nil }
        var frame = window.frame
        var radius: CGFloat?
        if window.level != .normal, let content = window.contentView {
            let inner = window.convertToScreen(content.convert(content.bounds, to: nil))
            if !inner.isEmpty {
                frame = inner
                radius = surfaceCornerRadius(behind: content)
            }
        }
        return (CGRect(x: frame.minX, y: primary.frame.maxY - frame.maxY, width: frame.width, height: frame.height),
                radius)
    }

    /// The radius of the glass behind a popover's content. On macOS 26 the popover's frame view
    /// holds, beside the content, a glass effect view as large as the frame whose `cornerRadius` is
    /// the popover's visible corner; the window reports none to WindowServer. Nil when there is no
    /// such view, which keeps the popover's square cut.
    private static func surfaceCornerRadius(behind content: NSView) -> CGFloat? {
        guard #available(macOS 26, *), let frameView = content.superview else { return nil }
        for case let glass as NSGlassEffectView in frameView.subviews where glass.frame == frameView.bounds {
            let radius = glass.cornerRadius
            if radius.isFinite, radius > 0, radius < 80 { return radius }
        }
        return nil
    }

    /// The online display whose UUID matches, so a wake or hotplug can move a panel onto the
    /// new `currentDisplayID` instead of leaving the old one up.
    private static func onlineDisplayID(matching uuid: UUID) -> CGDirectDisplayID? {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return nil }
        for id in ids.prefix(Int(count)) {
            guard let cfUUID = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
                  let parsed = UUID(uuidString: CFUUIDCreateString(nil, cfUUID) as String) else { continue }
            if parsed == uuid { return id }
        }
        return nil
    }

    private static func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        }
    }
}

enum WindowFilterError: Error {
    case unavailable, displayMissing
}

/// One click-through panel per display. Each tile is a backdrop layer with the same color matrix;
/// together they cover the display except the hole.
@MainActor
final class WindowFilterPanel {
    let displayID: CGDirectDisplayID
    private let panel: NSPanel
    var windowNumber: Int { panel.windowNumber }
    private let content: NSView
    private var tiles: [CALayer] = []
    private var lastTiles: [CGRect] = []
    private var gain: RGBGain?

    init(screen: NSScreen, displayID: CGDirectDisplayID) throws {
        self.displayID = displayID
        guard WKWindowFilterAvailable() else { throw WindowFilterError.unavailable }
        panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        // Nonzero alpha keeps WindowServer surface masking active; black adds no channel bias.
        panel.backgroundColor = .black.withAlphaComponent(0.001)
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        // Raised windows otherwise default to transient and disappear in Mission Control.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.sharingType = .readOnly
        content = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        content.wantsLayer = true
        content.layerUsesCoreImageFilters = false
        panel.contentView = content
        guard WKConfigureWindowFilterWindow(panel) else {
            panel.close()
            throw WindowFilterError.unavailable
        }
        excludeFromWindowPicker()
    }

    /// The screenshot tool's window picker otherwise selects this full-screen panel, and a
    /// window capture of an excluded app comes out as a display-sized white rectangle. The
    /// picker runs in `screencapture`, so a frontmost check on the screenshot UI misses
    /// Cmd-Shift-4 then Space and the clipboard (Control) capture. Area captures keep warmth.
    var isExcludedFromWindowPicker: Bool { WKWindowExcludedFromCaptureSelection(panel) }

    private var pickerExcludedWindowNumber: Int?

    private func excludeFromWindowPicker() {
        let number = panel.windowNumber
        guard number > 0, pickerExcludedWindowNumber != number else { return }
        if WKExcludeWindowFromCaptureSelection(panel) { pickerExcludedWindowNumber = number }
    }

    func setSharingType(_ sharing: NSWindow.SharingType) {
        guard panel.sharingType != sharing else { return }
        panel.sharingType = sharing
    }

    func setGain(_ value: RGBGain) throws {
        guard value != gain else { return }
        for tile in tiles where !WKSetWindowFilterGain(tile, Float(value.red), Float(value.green), Float(value.blue)) {
            throw WindowFilterError.unavailable
        }
        gain = value
    }

    /// `rects` and `display` are in CoreGraphics global space (top-left origin).
    func setTiles(_ rects: [CGRect], display: CGRect) {
        guard rects != lastTiles else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        while tiles.count < rects.count {
            guard let tile = WKCreateWindowFilterLayer() else { return }
            if let gain {
                _ = WKSetWindowFilterGain(tile, Float(gain.red), Float(gain.green), Float(gain.blue))
            }
            content.layer?.addSublayer(tile)
            tiles.append(tile)
        }
        for (index, tile) in tiles.enumerated() {
            guard index < rects.count else {
                tile.isHidden = true
                continue
            }
            let rect = rects[index]
            // Layer space is bottom-left origin within this display.
            tile.frame = CGRect(x: rect.minX - display.minX,
                                y: display.maxY - rect.maxY,
                                width: rect.width, height: rect.height)
            tile.isHidden = false
        }
        lastTiles = rects
    }

    func show(on screen: NSScreen) {
        if panel.frame != screen.frame {
            panel.setFrame(screen.frame, display: false)
            content.frame = NSRect(origin: .zero, size: screen.frame.size)
        }
        panel.orderFrontRegardless()
        panel.displayIfNeeded()
        excludeFromWindowPicker()
    }

    func close() {
        panel.orderOut(nil)
        panel.close()
    }
}
