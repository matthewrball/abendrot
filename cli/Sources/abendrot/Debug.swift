import AppKit
import ArgumentParser
import CoreGraphics
import Foundation
import WarmthCore
import AbendrotControl

// MARK: - debug

struct Debug: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Diagnostics to paste into a bug report.",
        subcommands: [DebugFullScreen.self]
    )
}

struct DebugFullScreen: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "fullscreen",
        abstract: "Show what Abendrot sees when it decides a screen is full screen. Prints window owners, layers, sizes, and corner radii, never window titles."
    )
    @Option(help: "Seconds to wait first, so you can switch to the full-screen app or open a menu (0-60).")
    var delay: Double = 0

    func run() throws {
        guard delay.isFinite, (0...60).contains(delay) else {
            throw fail("delay must be 0-60 seconds, got \(delay)", code: CLIExit.badInput)
        }
        if delay > 0 { Thread.sleep(forTimeInterval: delay) }
        print(FullScreenReport.text())
    }
}

/// Uses the same classifier and rules as the app, so the verdict matches what it decides.
enum FullScreenReport {
    static func text() -> String {
        var lines: [String] = []
        let os = ProcessInfo.processInfo.operatingSystemVersion
        lines.append("Abendrot full-screen check")
        lines.append("macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion), CLI \(cliVersion)")
        if let snapshot = Control.readSnapshot(), Control.isRunning() {
            lines.append("App \(snapshot.appVersion) (\(snapshot.appBuild)) running")
        } else {
            lines.append("App not running")
        }
        lines.append("Full screen pause: \(Control.configuredBool(PreferenceKey.pausesForFullScreen) == true ? "on" : "off")")
        let front = NSWorkspace.shared.frontmostApplication
        lines.append("Front app: \(front?.localizedName ?? "none") (\(front?.bundleIdentifier ?? "-"))")

        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let radii = CornerRadii.read(windows.compactMap { $0[kCGWindowNumber as String] as? Int })
        var apps: [Int32: (bundleID: String?, isRegular: Bool)] = [:]
        func app(_ pid: Int32) -> (bundleID: String?, isRegular: Bool) {
            if let cached = apps[pid] { return cached }
            let running = NSRunningApplication(processIdentifier: pid)
            let info = (running?.bundleIdentifier, running?.activationPolicy == .regular)
            apps[pid] = info
            return info
        }
        let sample = PausePolicy.classify(windowInfo: windows, app: app)
        let listed = PausePolicy.onlineDisplays()
        let unmirrored = listed.displays.filter { listed.mirroring[$0.id] == nil }
        let allWindows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        let finderDesktopExists = PausePolicy.finderDesktopExists(allWindowInfo: allWindows, app: app)
        let spaces = PausePolicy.fullScreenSpaceDisplayIDs(
            backdrops: sample.backdrops, displays: unmirrored, ownedWindows: sample.regularWindows,
            finderDesktopExists: finderDesktopExists)
        let paused = PausePolicy.fullScreenDisplayIDs(
            ownedWindows: sample.regularWindows, displays: listed.displays,
            mirroring: listed.mirroring, fullScreenSpaces: spaces)
        lines.append("Finder desktop on any Space: \(finderDesktopExists ? "yes" : "no")")

        lines.append("")
        for display in listed.displays {
            let center = CGPoint(x: display.bounds.midX, y: display.bounds.midY)
            let verdict = !paused.contains(display.id) ? "not full screen"
                : spaces.contains(display.id) ? "full screen (full-screen Space)"
                : listed.mirroring[display.id] != nil ? "full screen (mirrors a full-screen display)"
                : "full screen (a window covers it)"
            let desktop = sample.backdrops.contains { $0.kind == .desktop && $0.bounds.contains(center) }
            let backdrop = sample.backdrops.contains {
                $0.kind == .fullScreenBackdrop && PausePolicy.coversDisplay(window: $0.bounds, display: display.bounds)
            }
            var name = "Display \(display.id)"
            if CGDisplayIsBuiltin(display.id) != 0 { name += " built-in" }
            if let source = listed.mirroring[display.id] { name += " mirroring \(source)" }
            lines.append("\(name) \(describe(display.bounds)): \(verdict)")
            lines.append("  Finder desktop: \(desktop ? "present" : "absent"), Dock full-screen backdrop: \(backdrop ? "present" : "absent")")
            if let top = PausePolicy.topWindow(sample.regularWindows, on: display, among: unmirrored) {
                lines.append("  Top app window: \(owner(top.owner, app)) \(describe(top.bounds))")
            } else {
                lines.append("  Top app window: none")
            }
        }

        lines.append("")
        lines.append("Desktop-level windows:")
        for window in windows where (window[kCGWindowLayer as String] as? Int ?? 0) < 0 {
            lines.append("  " + row(window, app, radii))
        }
        lines.append("Front app-level windows (up to 12):")
        for window in windows.filter({ (($0[kCGWindowLayer as String] as? Int) ?? -1) == 0 }).prefix(12) {
            lines.append("  " + row(window, app, radii))
        }
        // Menus, context menus and menu-bar extras, of any app: their corners decide the cut-outs
        // over an excluded app's window.
        let menus = windows.filter { ($0[kCGWindowLayer as String] as? Int) == WindowHolePolicy.popUpMenuLayer }
        lines.append("Menu-level windows (up to 12):\(menus.isEmpty ? " none" : "")")
        for window in menus.prefix(12) {
            lines.append("  " + row(window, app, radii))
        }
        // Menu-bar extras, their status items and their popovers, of any app: a popover is cut at the
        // popover, not its window, when its top sits where the arrow puts it under a status item.
        let status = windows.filter { ($0[kCGWindowLayer as String] as? Int) == WindowHolePolicy.statusLayer }
        lines.append("Status-level windows (up to 24):\(status.isEmpty ? " none" : "")")
        for window in status.prefix(24) {
            lines.append("  " + row(window, app, radii))
        }
        // Floating windows of the front app, e.g. a player's own full-screen mode above normal windows.
        if let pid = front?.processIdentifier {
            let raised = windows.filter {
                ($0[kCGWindowOwnerPID as String] as? Int32) == pid && (($0[kCGWindowLayer as String] as? Int) ?? 0) > 0
            }
            lines.append("Front app's raised windows:\(raised.isEmpty ? " none" : "")")
            for window in raised.prefix(12) {
                lines.append("  " + row(window, app, radii))
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func row(
        _ window: [String: Any], _ app: (Int32) -> (bundleID: String?, isRegular: Bool), _ radii: [Int: Double]?
    ) -> String {
        let pid = window[kCGWindowOwnerPID as String] as? Int32 ?? -1
        let layer = window[kCGWindowLayer as String] as? Int ?? 0
        let alpha = window[kCGWindowAlpha as String] as? Double ?? 1
        var bounds = CGRect.zero
        if let dict = window[kCGWindowBounds as String] as? [String: Any],
           let rect = CGRect(dictionaryRepresentation: dict as CFDictionary) {
            bounds = rect
        }
        let regular = app(pid).isRegular ? "app" : "background"
        let name = window[kCGWindowOwnerName as String] as? String
        var text = "\(owner(pid, app, fallback: name)) [\(regular)] layer \(layer) alpha \(String(format: "%.2f", alpha)) \(describe(bounds))"
        if let radii {
            if let radius = (window[kCGWindowNumber as String] as? Int).flatMap({ radii[$0] }) {
                text += " radius \(String(format: "%g", radius))"
            }
        }
        return text
    }

    private static func owner(
        _ pid: Int32, _ app: (Int32) -> (bundleID: String?, isRegular: Bool), fallback: String? = nil
    ) -> String {
        let name = NSRunningApplication(processIdentifier: pid)?.localizedName ?? fallback ?? "pid \(pid)"
        return "\(name) (\(app(pid).bundleID ?? "-"))"
    }

    private static func describe(_ rect: CGRect) -> String {
        "x \(Int(rect.minX)) y \(Int(rect.minY)) \(Int(rect.width))x\(Int(rect.height))"
    }
}

/// WindowServer's corner radius per window number, read the same way the app reads it. Nil before
/// macOS 26 or when this macOS has no such query, so the report leaves the radius out. A window
/// missing from the answer is left out too, not printed as 0.
enum CornerRadii {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias Query = @convention(c) (Int32, CFArray, UInt32) -> Unmanaged<CFTypeRef>?
    private typealias CopyWindows = @convention(c) (CFTypeRef) -> Unmanaged<CFTypeRef>?
    private typealias Advance = @convention(c) (CFTypeRef) -> Bool
    private typealias WindowID = @convention(c) (CFTypeRef) -> UInt32
    private typealias Radii = @convention(c) (CFTypeRef) -> Unmanaged<CFArray>?

    static func read(_ numbers: [Int]) -> [Int: Double]? {
        // The radii calls return a new array the caller owns on macOS 26, where that was checked.
        guard #available(macOS 26, *) else { return nil }
        guard let sky = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY | RTLD_LOCAL),
              let main = dlsym(sky, "SLSMainConnectionID"), let query = dlsym(sky, "SLSWindowQueryWindows"),
              let copy = dlsym(sky, "SLSWindowQueryResultCopyWindows"), let advance = dlsym(sky, "SLSWindowIteratorAdvance"),
              let windowID = dlsym(sky, "SLSWindowIteratorGetWindowID"),
              let radii = dlsym(sky, "SLSWindowIteratorGetResolvedCornerRadii") ?? dlsym(sky, "SLSWindowIteratorGetCornerRadii")
        else { return nil }
        let ids = numbers.filter { $0 > 0 && $0 <= Int(UInt32.max) }.map { NSNumber(value: UInt32($0)) }
        let connection = unsafeBitCast(main, to: MainConnection.self)()
        guard let result = unsafeBitCast(query, to: Query.self)(connection, ids as CFArray, 0)?.takeRetainedValue(),
              let iterator = unsafeBitCast(copy, to: CopyWindows.self)(result)?.takeRetainedValue() else { return nil }
        var found: [Int: Double] = [:]
        while unsafeBitCast(advance, to: Advance.self)(iterator) {
            let id = Int(unsafeBitCast(windowID, to: WindowID.self)(iterator))
            let values = unsafeBitCast(radii, to: Radii.self)(iterator)?.takeRetainedValue() as? [NSNumber] ?? []
            found[id] = values.map(\.doubleValue).filter(\.isFinite).max() ?? 0
        }
        return found
    }
}
