import Testing
import AppKit
import CInterop
@testable import WarmthKitPrivate

/// The screenshot tool's window picker must skip the warmth panel, or a window capture of an
/// excluded app is a display-sized white rectangle (issue #30, clipboard and Cmd-Shift-4 paths).
@MainActor
@Suite("Window filter panel and the screenshot window picker")
struct WindowCaptureSelectionTests {

    init() { _ = NSApplication.shared }

    @Test("A window can be hidden from the window picker without being shown")
    func marksPlainWindow() throws {
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        try #require(window.windowNumber > 0)
        #expect(!WKWindowExcludedFromCaptureSelection(window))
        #expect(WKExcludeWindowFromCaptureSelection(window))
        #expect(WKWindowExcludedFromCaptureSelection(window))
    }

    @Test("Every warmth panel is hidden from the window picker from creation")
    func panelIsExcludedFromPicker() throws {
        try #require(WKWindowFilterAvailable())
        let screen = try #require(NSScreen.screens.first)
        let displayID = try #require(
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value)
        let panel = try WindowFilterPanel(screen: screen, displayID: displayID)
        defer { panel.close() }
        #expect(panel.isExcludedFromWindowPicker)
    }

    @Test("A window without a window number is refused, not crashed on")
    func deferredWindowIsRefused() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                              styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        try #require(window.windowNumber <= 0)
        #expect(!WKExcludeWindowFromCaptureSelection(window))
    }
}
