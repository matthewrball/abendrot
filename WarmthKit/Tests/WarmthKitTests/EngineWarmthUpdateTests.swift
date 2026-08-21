import Testing
@testable import WarmthKit
@testable import HardwareDDC
@testable import WarmthCore

@Suite("Atomic warmth-curve updates")
struct EngineWarmthUpdateTests {
    @Test("Cozy override and restoration each apply one complete curve")
    func cozyOverrideAndRestoreAreAtomic() async {
        let display = DisplayIdentity.fixture()
        let backend = FaultInjectingBackend(method: .hardware)
        let engine = WarmthEngine.test(
            backends: [backend],
            store: InMemoryDDCSnapshotStore(),
            displays: [display]
        )
        let configured = WarmthLevel(strength: 0.42)

        await engine.start()
        await engine.setHardwareDDCEnabled(true, for: display)
        await engine.setEnabled(true)
        await engine.setScheduleMode(.alwaysOn)

        var before = await backend.callLog.filter { $0 == "apply" }.count
        await engine.setWarmth(.init(strength: 1), warmestPoint: .warmestSupported)
        #expect(await backend.callLog.filter { $0 == "apply" }.count == before + 1)
        #expect(await backend.applied[display] == .warmestSupported)

        before = await backend.callLog.filter { $0 == "apply" }.count
        await engine.setWarmth(configured, warmestPoint: .everydayWarmest)
        #expect(await backend.callLog.filter { $0 == "apply" }.count == before + 1)
        #expect(await engine.state.globalWarmth == configured)
        #expect(await backend.applied[display] == configured.kelvin(warmestPoint: .everydayWarmest))
    }
}
