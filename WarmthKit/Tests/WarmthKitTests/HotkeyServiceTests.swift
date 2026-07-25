import Testing
@testable import WarmthKit
@testable import HardwareDDC

@MainActor
@Suite("Reveal hotkey")
struct HotkeyServiceTests {
    @Test("Reveal defaults to hold and toggle uses the master warmth control")
    func revealModeDefaultsToHold() {
        let engine = WarmthEngine.test(backends: [], store: InMemoryDDCSnapshotStore(), displays: [])
        var toggles = 0
        let service = HotkeyService(engine: engine) { toggles += 1 }

        #expect(service.mode == .hold)

        service.mode = .toggle
        service.handleKeyDown()
        service.handleKeyDown()

        #expect(toggles == 2)
    }
}
