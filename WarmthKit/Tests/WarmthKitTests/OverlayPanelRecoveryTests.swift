import AppKit
import Foundation
import Testing
@testable import OverlayRenderer
@testable import WarmthCore

/// Opt-in native window check; ordinary hosted tests never tint a desktop.
@MainActor
@Suite("Native tint window recovery", .enabled(if: ProcessInfo.processInfo.environment["ABENDROT_DISPLAY_QA"] == "1"))
struct OverlayPanelRecoveryTests {
    @Test("unchanged warmth restores a hidden tint window and neutral keeps it hidden")
    func unchangedWarmthRestoresVisibility() throws {
        let app = NSApplication.shared
        let existing = Set(app.windows.map(ObjectIdentifier.init))
        let screen = try #require(NSScreen.main)
        let overlay = OverlayPanel(identity: .fixture(), screen: screen)
        defer { overlay.orderOut() }
        let window = try #require(app.windows.first { !existing.contains(ObjectIdentifier($0)) })
        let gain = rgbGain(for: .everydayWarmest)

        overlay.setVeilGain(gain)
        #expect(window.isVisible)
        overlay.orderOut()
        #expect(!window.isVisible)
        overlay.setVeilGain(gain)
        #expect(window.isVisible)
        overlay.setVeilGain(.identity)
        #expect(!window.isVisible)
        overlay.setVeilGain(.identity)
        #expect(!window.isVisible)
    }
}
