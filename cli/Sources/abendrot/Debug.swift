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
        abstract: "Show what Abendrot sees when it decides a screen is full screen. Prints window owners, layers, and sizes, never window titles."
    )
    @Option(help: "Seconds to wait first, so you can switch to the full-screen app (0-60).")
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
            lines.append("  " + row(window, app))
        }
        lines.append("Front app-level windows (up to 12):")
        for window in windows.filter({ (($0[kCGWindowLayer as String] as? Int) ?? -1) == 0 }).prefix(12) {
            lines.append("  " + row(window, app))
        }
        // Floating windows of the front app, e.g. a player's own full-screen mode above normal windows.
        if let pid = front?.processIdentifier {
            let raised = windows.filter {
                ($0[kCGWindowOwnerPID as String] as? Int32) == pid && (($0[kCGWindowLayer as String] as? Int) ?? 0) > 0
            }
            lines.append("Front app's raised windows:\(raised.isEmpty ? " none" : "")")
            for window in raised.prefix(12) {
                lines.append("  " + row(window, app))
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func row(_ window: [String: Any], _ app: (Int32) -> (bundleID: String?, isRegular: Bool)) -> String {
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
        return "\(owner(pid, app, fallback: name)) [\(regular)] layer \(layer) alpha \(String(format: "%.2f", alpha)) \(describe(bounds))"
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
