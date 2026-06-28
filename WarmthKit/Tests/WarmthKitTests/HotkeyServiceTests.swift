import Testing
@testable import WarmthKit
@testable import HardwareDDC

@MainActor
@Suite("Reveal hotkey")
struct HotkeyServiceTests {
    @Test("Default mode flips the master warmth control")
    func defaultModeUsesMasterToggleCallback() {
        let engine = WarmthEngine.test(backends: [], store: InMemoryDDCSnapshotStore(), displays: [])
        var toggles = 0
        let service = HotkeyService(engine: engine) { toggles += 1 }

        service.handleKeyDown()
        service.handleKeyDown()

        #expect(toggles == 2)
    }
}
