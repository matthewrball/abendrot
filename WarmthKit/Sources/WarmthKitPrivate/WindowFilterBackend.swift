import AppKit
import ColorSync
import QuartzCore
import WarmthCore
import CInterop

/// Experimental: warms a display around the frontmost app's windows, so an excluded app shows true
/// color while the rest of that display stays warm. A click-through panel above everything filters
/// what is behind it through a private compositor color matrix; tiles leave a hole over the app's
/// visible windows. Window positions come from `CGWindowListCopyWindowInfo` metadata, with no
/// Screen Recording and no Accessibility. Direct distribution only.
@MainActor
public final class WindowFilterBackend: WarmthBackend {
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

    private func refreshHoles() {
        guard !panels.isEmpty else { return }
        let owner = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1
        let windows = listedWindows()
        for (_, panel) in panels {
            let display = CGDisplayBounds(panel.displayID)
            let region = WindowHolePolicy.neutralRegion(windows: windows, owner: owner, display: display)
            panel.setTiles(WindowHolePolicy.warmTiles(around: region, in: display), display: display)
        }
    }

    /// Activation policy by process, kept while tracking. Cleared when tracking stops.
    private var activationPolicies: [pid_t: Bool] = [:]

    private func listedWindows() -> [WindowHolePolicy.Window] {
        guard let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return [] }
        return raw.compactMap { window in
            guard let boundsDict = window[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { return nil }
            let owner = window[kCGWindowOwnerPID as String] as? pid_t ?? -1
            let layer = window[kCGWindowLayer as String] as? Int ?? 0
            let regular: Bool
            if let cached = activationPolicies[owner] {
                regular = cached
            } else {
                regular = NSRunningApplication(processIdentifier: owner)?.activationPolicy == .regular
                activationPolicies[owner] = regular
            }
            return WindowHolePolicy.Window(
                bounds: rect,
                layer: layer,
                owner: owner,
                alpha: window[kCGWindowAlpha as String] as? Double ?? 1,
                isRegularApp: regular
            )
        }
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

private enum WindowFilterError: Error {
    case unavailable, displayMissing
}

/// One click-through panel per display. Each tile is a backdrop layer with the same color matrix;
/// together they cover the display except the hole.
@MainActor
private final class WindowFilterPanel {
    let displayID: CGDirectDisplayID
    private let panel: NSPanel
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
    }

    func close() {
        panel.orderOut(nil)
        panel.close()
    }
}
