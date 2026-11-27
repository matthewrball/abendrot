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
        abstract: "Show what Abendrot sees when it decides a screen is full screen. Prints window owners, layers, sizes, corner radii, tags and shadow boxes, and the remembered menu margin, never window titles."
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
        // Apps raise ordinary windows to this level too (LuLu's alert, #38): each row says whether the
        // app may take the window for a padded menu, with WindowServer's tags and shadow box.
        let menus = windows.filter { ($0[kCGWindowLayer as String] as? Int) == WindowHolePolicy.popUpMenuLayer }
        // The margin the app cuts padded menus with from the first sample after launch (#37).
        lines.append(MenuMarginLine.text(
            storedValue: Control.preference(MenuMarginMemory.defaultsKey), build: ThisMac.osBuild,
            osMajor: os.majorVersion, radiusQueryExists: CornerRadii.queryExists))
        lines.append("Menu-level windows (up to 12):\(menus.isEmpty ? " none" : "")")
        let details = WindowServerDetails.read(menus.prefix(12).compactMap { $0[kCGWindowNumber as String] as? Int })
        for window in menus.prefix(12) {
            let number = window[kCGWindowNumber as String] as? Int
            let detail = number.flatMap { details?[$0] }
            lines.append("  " + row(window, app, radii) + MenuLevelDetail.text(
                bounds: windowBounds(window), radius: radii.flatMap { radii in number.flatMap { radii[$0] } },
                tags: detail?.tags, shadow: detail?.shadow))
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

    private static func windowBounds(_ window: [String: Any]) -> CGRect {
        guard let dict = window[kCGWindowBounds as String] as? [String: Any],
              let rect = CGRect(dictionaryRepresentation: dict as CFDictionary) else { return .zero }
        return rect
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

    /// The six SkyLight calls of the radius query, the same ones the app resolves.
    private struct Calls {
        let main, query, copy, advance, windowID, radii: UnsafeMutableRawPointer
    }

    /// The query's calls on macOS 26 or later, or nil. The radii calls return a new array the caller
    /// owns on macOS 26, where that was checked, so they are not looked up before it.
    private static func calls() -> Calls? {
        guard #available(macOS 26, *) else { return nil }
        guard let sky = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY | RTLD_LOCAL),
              let main = dlsym(sky, "SLSMainConnectionID"), let query = dlsym(sky, "SLSWindowQueryWindows"),
              let copy = dlsym(sky, "SLSWindowQueryResultCopyWindows"), let advance = dlsym(sky, "SLSWindowIteratorAdvance"),
              let windowID = dlsym(sky, "SLSWindowIteratorGetWindowID"),
              let radii = dlsym(sky, "SLSWindowIteratorGetResolvedCornerRadii") ?? dlsym(sky, "SLSWindowIteratorGetCornerRadii")
        else { return nil }
        return Calls(main: main, query: query, copy: copy, advance: advance, windowID: windowID, radii: radii)
    }

    /// Whether this Mac has the radius query: macOS 26 or later with all six calls. The app's
    /// `WKCopyWindowCornerRadii(nil, 0, nil)` checks the same, and only then does it load or store a
    /// remembered menu margin. Looks the calls up without making the query.
    static var queryExists: Bool { calls() != nil }

    static func read(_ numbers: [Int]) -> [Int: Double]? {
        guard let calls = calls() else { return nil }
        let ids = numbers.filter { $0 > 0 && $0 <= Int(UInt32.max) }.map { NSNumber(value: UInt32($0)) }
        let connection = unsafeBitCast(calls.main, to: MainConnection.self)()
        guard let result = unsafeBitCast(calls.query, to: Query.self)(connection, ids as CFArray, 0)?.takeRetainedValue(),
              let iterator = unsafeBitCast(calls.copy, to: CopyWindows.self)(result)?.takeRetainedValue() else { return nil }
        var found: [Int: Double] = [:]
        while unsafeBitCast(calls.advance, to: Advance.self)(iterator) {
            let id = Int(unsafeBitCast(calls.windowID, to: WindowID.self)(iterator))
            found[id] = radius(from: unsafeBitCast(calls.radii, to: Radii.self)(iterator)?.takeRetainedValue())
        }
        return found
    }

    /// One radius from WindowServer's corner values, as the app's window query reduces them: only
    /// numbers count (not booleans or anything else in the array), then the largest finite one,
    /// starting from 0. So the row prints, and the verdict judges, the radius the app gets.
    static func radius(from values: CFArray?) -> Double {
        guard let values else { return 0 }
        let numbers = (values as NSArray).compactMap { value -> Double? in
            guard let number = value as? NSNumber, CFGetTypeID(number) == CFNumberGetTypeID() else { return nil }
            return number.doubleValue
        }
        return WindowHolePolicy.largestReportedCornerRadius(numbers)
    }
}

/// What `debug fullscreen` adds to a menu-level window's row (#38): WindowServer's tag bits, how far
/// its shadow box reaches past each edge (left/top/right/bottom, negative when inside the window),
/// and whether the app may take the window for a padded menu, by the same rule the app uses.
/// `radius` is the reported radius as `CornerRadii` reads it; the verdict normalises it the way
/// the app does, so a radius of 80 pt or more counts as none.
enum MenuLevelDetail {
    static func text(bounds: CGRect, radius: Double?, tags: UInt64?, shadow: CGRect?) -> String {
        var text = ""
        if let tags { text += " tags 0x\(String(tags, radix: 16))" }
        if let shadow {
            if shadow.isNull || shadow.width <= 0 || shadow.height <= 0 {
                text += " shadow none"
            } else {
                let reach = [bounds.minX - shadow.minX, bounds.minY - shadow.minY,
                             shadow.maxX - bounds.maxX, shadow.maxY - bounds.maxY]
                text += " shadow " + reach.map { String(format: "%g", Double($0)) }.joined(separator: "/")
            }
        }
        // The app keeps a reported radius only when it is usable (finite, above 0, under 80 pt).
        let window = WindowHolePolicy.Window(
            bounds: bounds, layer: WindowHolePolicy.popUpMenuLayer, owner: 0,
            cornerRadius: radius.flatMap { WindowHolePolicy.usableCornerRadius($0) })
        text += window.canBePaddedMenu ? " padded menu: possible" : " padded menu: no (reports a radius)"
        return text
    }
}

/// The line on the menu margin the app remembers across launches (#37): the stored record, and
/// whether the app would use it. It reports the stored record, not a running app's memory. The app
/// loads a record only on macOS 26 or later where WindowServer's radius query exists
/// (`radiusQueryExists`, `CornerRadii.queryExists`), and only one proven on this Mac's OS build; it
/// uses it while Keep other windows warm cuts menus. Pure, so every case is tested: `storedValue`
/// is the raw preference, `build` this Mac's `kern.osversion`.
enum MenuMarginLine {
    /// The first macOS on which the app keeps and uses a remembered margin.
    static let firstMacOS = 26

    static func text(storedValue: Any?, build: String?, osMajor: Int, radiusQueryExists: Bool) -> String {
        let prefix = "Menu margin remembered: "
        guard let storedValue else { return prefix + "none" }
        guard let record = MenuMarginMemory.Record(storedValue: storedValue) else {
            return prefix + "unreadable value, not used"
        }
        let proven = prefix + "\(String(format: "%g", Double(record.margin))) pt, proven on \(record.build)"
        guard osMajor >= firstMacOS else { return proven + ", not used before macOS \(firstMacOS)" }
        guard radiusQueryExists else { return proven + ", not used: this macOS has no window corner query" }
        guard let build else { return proven + " (this Mac's build is unknown), not used" }
        guard record.build == build else { return proven + " (this Mac runs \(build)), not used" }
        return proven + " (this Mac), used when Keep other windows warm is on"
    }
}

/// This Mac's OS build (`kern.osversion`, such as 26B131), read as the app reads it, or nil when it
/// cannot be read. Kept out of main.swift: a top-level value there is never set under the tests.
enum ThisMac {
    static let osBuild: String? = {
        var size = 0
        guard sysctlbyname("kern.osversion", nil, &size, nil, 0) == 0, size > 1 else { return nil }
        var bytes = [UInt8](repeating: 0, count: size)
        guard sysctlbyname("kern.osversion", &bytes, &size, nil, 0) == 0 else { return nil }
        let build = String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        return build.isEmpty ? nil : build
    }()
}

/// WindowServer's tag bits and shadow box for each window number, for the report only. Read on
/// macOS 26 and later, like the radii. Both come back by value, so nothing is owned. Nil before
/// macOS 26 or when this macOS has no such calls; a window missing from the answer is left out.
enum WindowServerDetails {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias Query = @convention(c) (Int32, CFArray, UInt32) -> Unmanaged<CFTypeRef>?
    private typealias CopyWindows = @convention(c) (CFTypeRef) -> Unmanaged<CFTypeRef>?
    private typealias Advance = @convention(c) (CFTypeRef) -> Bool
    private typealias WindowID = @convention(c) (CFTypeRef) -> UInt32
    private typealias Tags = @convention(c) (CFTypeRef) -> UInt64
    private typealias Box = @convention(c) (CFTypeRef) -> CGRect

    static func read(_ numbers: [Int]) -> [Int: (tags: UInt64, shadow: CGRect)]? {
        guard #available(macOS 26, *) else { return nil }
        guard let sky = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY | RTLD_LOCAL),
              let main = dlsym(sky, "SLSMainConnectionID"), let query = dlsym(sky, "SLSWindowQueryWindows"),
              let copy = dlsym(sky, "SLSWindowQueryResultCopyWindows"), let advance = dlsym(sky, "SLSWindowIteratorAdvance"),
              let windowID = dlsym(sky, "SLSWindowIteratorGetWindowID"),
              let tags = dlsym(sky, "SLSWindowIteratorGetTags"), let box = dlsym(sky, "SLSWindowIteratorGetFrameBounds")
        else { return nil }
        let ids = numbers.filter { $0 > 0 && $0 <= Int(UInt32.max) }.map { NSNumber(value: UInt32($0)) }
        guard !ids.isEmpty else { return [:] }
        let connection = unsafeBitCast(main, to: MainConnection.self)()
        guard let result = unsafeBitCast(query, to: Query.self)(connection, ids as CFArray, 0)?.takeRetainedValue(),
              let iterator = unsafeBitCast(copy, to: CopyWindows.self)(result)?.takeRetainedValue() else { return nil }
        var found: [Int: (tags: UInt64, shadow: CGRect)] = [:]
        while unsafeBitCast(advance, to: Advance.self)(iterator) {
            let id = Int(unsafeBitCast(windowID, to: WindowID.self)(iterator))
            found[id] = (unsafeBitCast(tags, to: Tags.self)(iterator), unsafeBitCast(box, to: Box.self)(iterator))
        }
        return found
    }
}
