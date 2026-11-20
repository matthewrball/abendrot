import Testing
import AppKit
import CInterop

/// The window filter cuts each window at the radius WindowServer reports for it (issue #30: menus
/// are rounder or squarer than a titled window). Needs a WindowServer session, like the window
/// picker tests. Before macOS 26 the query is never made, which the last test checks.
@MainActor
@Suite("WindowServer corner radii",
       .enabled(if: CGSessionCopyCurrentDictionary() != nil, "needs a logged-in GUI session"))
struct WindowCornerRadiiTests {

    init() { _ = NSApplication.shared }

    private func radii(_ ids: [UInt32]) -> [Double]? {
        var values = [Double](repeating: -1, count: ids.count)
        return WKCopyWindowCornerRadii(ids, ids.count, &values) ? values : nil
    }

    nonisolated private static var queries: Bool {
        if #available(macOS 26, *) { return true }
        return false
    }

    @Test("Before macOS 26 the query is refused, so every radius stays unknown",
          .enabled(if: !queries))
    func refusedBeforeMacOS26() {
        var values = [Double](repeating: -1, count: 1)
        #expect(!WKCopyWindowCornerRadii([1], 1, &values))
        #expect(values == [-1])
    }

    @Test("An on-screen titled window reports the titled-window radius", .enabled(if: queries))
    func titledWindowRadius() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 120),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        // WindowServer sets the radius once the window is ordered in. Fully transparent, so
        // nothing shows.
        window.alphaValue = 0
        window.orderFrontRegardless()
        defer { window.close() }
        try #require(window.windowNumber > 0)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        // Older macOS has no such query; the filter then keeps the titled-window radius.
        let values = try #require(radii([UInt32(window.windowNumber)]))
        let standard = Double(WKStandardWindowCornerRadius())
        try #require(standard > 0)
        #expect(values.count == 1 && abs(values[0] - standard) < 0.01)
    }

    @Test("A borderless window reports no radius, and a window that does not exist reports zero",
          .enabled(if: queries))
    func squareAndMissingWindows() throws {
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        try #require(window.windowNumber > 0)
        let values = try #require(radii([UInt32(window.windowNumber), UInt32.max - 1]))
        #expect(values == [0, 0])
    }

    @Test("An empty list and a nil buffer are answered without a query", .enabled(if: queries))
    func edgeInputs() {
        var none: [Double] = []
        #expect(WKCopyWindowCornerRadii([], 0, &none))
        #expect(!WKCopyWindowCornerRadii(nil, 1, &none))
    }
}
