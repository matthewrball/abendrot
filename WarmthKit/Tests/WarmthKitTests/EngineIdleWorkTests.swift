import Testing
import Foundation
@testable import HardwareDDC
@testable import WarmthCore
@testable import WarmthKit

@Suite("Engine idle work")
struct EngineIdleWorkTests {
    @Test("static schedules do not rewrite an unchanged backend on the minute tick")
    func staticScheduleSkipsRampTickApply() async {
        for mode in [ScheduleMode.alwaysOn, .off] {
            let (engine, overlay) = await engine(in: mode)
            let callsBefore = await overlay.callLog.count
            await engine.simulateRampTick()
            #expect(await overlay.callLog.count == callsBefore)
        }
    }

    @Test("time-varying schedules still reapply on the minute tick")
    func dynamicSchedulesKeepRampTickApply() async {
        let custom = CustomSchedule(
            start: DateComponents(hour: 0),
            end: DateComponents(hour: 0),
            warmest: WarmthLevel(strength: 0.7)
        )
        for mode in [
            ScheduleMode.followSystemNightShift,
            .solar(latitude: 0, longitude: 0),
            .custom(custom),
        ] {
            let (engine, overlay) = await engine(in: mode)
            let callsBefore = await overlay.callLog.count
            await engine.simulateRampTick()
            #expect(await overlay.callLog.count > callsBefore)
        }
    }

    private func engine(in mode: ScheduleMode) async -> (WarmthEngine, FaultInjectingBackend) {
        let display = DisplayIdentity.fixture()
        let overlay = FaultInjectingBackend(method: .overlay)
        let engine = WarmthEngine.test(
            backends: [overlay],
            store: InMemoryDDCSnapshotStore(),
            displays: [display]
        )
        await engine.start()
        await engine.setScheduleMode(mode)
        await engine.setEnabled(true)
        return (engine, overlay)
    }
}
