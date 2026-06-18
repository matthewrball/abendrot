import Testing
import Foundation
@testable import WarmthKit
@testable import HardwareDDC
@testable import WarmthCore

/// Engine-level failure-injection recovery driven through the engine's
/// injectable test seams: `WarmthEngine.test(backends:store:displays:)` and
/// `simulateReconfiguration(present:)`. These prove the safety-critical recovery paths headlessly.
@Suite("Engine failure-injection recovery")
struct EngineRecoveryTests {

    /// Drive a display into DDC-warming mode on a fresh engine.
    private func warmedEngine(
        ddc: FaultInjectingBackend, store: InMemoryDDCSnapshotStore, display: DisplayIdentity
    ) async -> WarmthEngine {
        let engine = WarmthEngine.test(backends: [ddc], store: store, displays: [display])
        await engine.start()
        await engine.setHardwareDDCEnabled(true, for: display)
        await engine.setEnabled(true)
        await engine.setScheduleMode(.alwaysOn)
        await engine.setWarmth(WarmthLevel(strength: 0.8), for: display)
        return engine
    }

    // MARK: S1 — crash during a DDC write

    @Test("S1: launch-time recovery restores native DDC gain after a mid-write crash")
    func crashDuringWriteRecoversOnRelaunch() async throws {
        let store = InMemoryDDCSnapshotStore()
        let display = DisplayIdentity.fixture()

        // Run 1: warm, but the write faults mid-transaction (panel left dirty).
        let ddc1 = FaultInjectingBackend(method: .hardware)
        await ddc1.setFault(.midApply)
        let engine1 = await warmedEngine(ddc: ddc1, store: store, display: display)

        let dirtyGain = await ddc1.applied[display]
        #expect(dirtyGain != nil && dirtyGain != .neutral)                       // panel left non-neutral
        #expect(await store.dirtyKeys().contains(display.persistentKey))         // write-ahead persisted
        // The faulted write took the documented honest fallback: badge is NOT Hardware, error surfaced.
        let row1 = await engine1.state.displays.first
        #expect(row1?.appliedMethod != .hardware)
        #expect(row1?.lastError != nil)

        // Run 2: a brand-new engine over the SAME store must restore BEFORE applying anything.
        let ddc2 = FaultInjectingBackend(method: .hardware)
        await ddc2.forceApplied(display, Kelvin(3000))                           // still-warm panel
        let engine2 = WarmthEngine.test(backends: [ddc2], store: store, displays: [display])
        await engine2.start()

        #expect(await ddc2.applied[display] == .neutral)                         // restored to native at launch
        #expect(await store.dirtyKeys().isEmpty)                                 // dirty cleared after recovery

        // Drive a warm apply so the reset-before-apply ORDERING is genuinely exercised (not skipped):
        // both events are now guaranteed in the log and the ordering is asserted unconditionally.
        await engine2.setHardwareDDCEnabled(true, for: display)
        await engine2.setEnabled(true)
        await engine2.setScheduleMode(.alwaysOn)
        await engine2.setWarmth(WarmthLevel(strength: 0.8), for: display)
        let log = await ddc2.callLog
        let resetIndex = try #require(log.firstIndex(of: "reset"))
        let applyIndex = try #require(log.firstIndex(of: "apply"))
        #expect(resetIndex < applyIndex)                                         // restore happened before any new warm write
    }

    // MARK: S2 — SIGKILL (no teardown hook runs at all)

    @Test("S2: SIGKILL — relaunch restores from snapshot with no teardown hook, silently")
    func sigkillRelaunchRestores() async throws {
        let store = InMemoryDDCSnapshotStore()
        let display = DisplayIdentity.fixture()

        // A prior run died dirty: persisted native + dirty flag, panel still warm. (This is the
        // engine-level ORDERING/orchestration proof; native-gain write-back fidelity is asserted
        // separately at the transport layer in DDCTransportTests.restoresNative.)
        await store.preseed(
            DDCDisplaySnapshot(
                native: DDCNativeState(
                    red: .init(current: 100, max: 100),
                    green: .init(current: 100, max: 100),
                    blue: .init(current: 100, max: 100)
                ),
                isDirty: true
            ),
            for: display.persistentKey
        )
        let ddc = FaultInjectingBackend(method: .hardware)
        await ddc.forceApplied(display, Kelvin(3000))

        let engine = WarmthEngine.test(backends: [ddc], store: store, displays: [display])
        await engine.start()                                                     // NO shutdown ever called

        #expect(await ddc.applied[display] == .neutral)                          // recovered without teardown
        let state = await engine.state
        #expect(state.displays.first?.lastError == nil)                          // recovery is silent
        #expect(await store.dirtyKeys().isEmpty)
    }

    // MARK: S3 — wake while the display service is gone

    @Test("S3: wake with the display gone — no writes to a dead service, re-applies on return")
    func wakeServiceGoneReapplies() async throws {
        let store = InMemoryDDCSnapshotStore()
        let display = DisplayIdentity.fixture()
        let ddc = FaultInjectingBackend(method: .hardware)

        let engine = WarmthEngine.test(backends: [ddc], store: store, displays: [display])
        await engine.start()
        await engine.setHardwareDDCEnabled(true, for: display)
        await engine.setEnabled(true)
        await engine.setScheduleMode(.alwaysOn)
        await engine.setWarmth(WarmthLevel(strength: 0.7), for: display)
        let appliesBefore = await ddc.callLog.filter { $0 == "apply" }.count
        #expect(appliesBefore >= 1)

        // Display vanishes mid-wake.
        await engine.simulateReconfiguration(present: [])
        let appliesDuringGone = await ddc.callLog.filter { $0 == "apply" }.count
        #expect(appliesDuringGone == appliesBefore)                              // ZERO writes to a dead service
        #expect(await engine.state.displays.contains { $0.id == display } == false)

        // Display returns: identity re-resolves by cgUUID and warmth re-applies.
        await engine.simulateReconfiguration(present: [display])
        let appliesAfterReturn = await ddc.callLog.filter { $0 == "apply" }.count
        #expect(appliesAfterReturn > appliesDuringGone)                          // a REAL DDC write fired on return
        #expect(await ddc.applied[display] != .neutral)                          // panel was actually re-warmed
        let state = await engine.state
        #expect(state.displays.first?.id == display)
        #expect(state.displays.first?.warmth.strength == 0.7)                    // settings survived the unplug
    }
}
