import Testing
import Foundation
@testable import WarmthKit
@testable import HardwareDDC
@testable import WarmthCore

@Suite("Engine session pause and fullscreen suspend")
struct EnginePauseTests {

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

    private func method(_ engine: WarmthEngine, for display: DisplayIdentity? = nil) async -> DisplayMethod? {
        let state = await engine.state
        if let display {
            return state.displays.first { $0.id == display }?.appliedMethod
        }
        return state.displays.first?.appliedMethod
    }

    @Test("A future pause suspends warmth without changing enable, and resume restores it")
    func pauseAndResume() async {
        let store = InMemoryDDCSnapshotStore()
        let display = DisplayIdentity.fixture()
        let ddc = FaultInjectingBackend(method: .hardware)
        let engine = await warmedEngine(ddc: ddc, store: store, display: display)
        #expect(await method(engine) == .hardware)

        let pause = PausePolicy.oneHour(from: Date())
        await engine.setTimedPause(pause)
        let paused = await engine.state
        #expect(paused.isEnabled)
        #expect(paused.timedPause == pause)
        #expect(await method(engine) == .off)
        #expect(await ddc.applied[display] == .neutral)

        await engine.setWarmth(WarmthLevel(strength: 0.3))
        #expect(await method(engine) == .off)

        await engine.setTimedPause(nil)
        let resumed = await engine.state
        #expect(resumed.timedPause == nil)
        #expect(resumed.isEnabled)
        #expect(resumed.globalWarmth.strength == 0.3)
        #expect(await method(engine) == .hardware)
        #expect(await ddc.applied[display] != .neutral)
    }

    @Test("An expired or far-future pause cannot leave the display neutral")
    func expiredPauseDoesNotStick() async {
        let store = InMemoryDDCSnapshotStore()
        let display = DisplayIdentity.fixture()
        let engine = await warmedEngine(
            ddc: FaultInjectingBackend(method: .hardware), store: store, display: display)

        await engine.setTimedPause(TimedPause(until: Date().addingTimeInterval(-30), kind: .oneHour))
        #expect(await engine.state.timedPause == nil)
        #expect(await method(engine) == .hardware)

        let far = TimedPause(until: Date().addingTimeInterval(PausePolicy.maximumLead + 120), kind: .untilSunrise)
        await engine.setTimedPause(far)
        #expect(await engine.state.timedPause == nil)
        #expect(await method(engine) == .hardware)
    }

    @Test("Turning warmth off clears a pause so turning it back on does not stay neutral")
    func disableClearsPause() async {
        let store = InMemoryDDCSnapshotStore()
        let display = DisplayIdentity.fixture()
        let engine = await warmedEngine(
            ddc: FaultInjectingBackend(method: .hardware), store: store, display: display)

        await engine.setTimedPause(PausePolicy.oneHour(from: Date()))
        #expect(await method(engine) == .off)

        await engine.setEnabled(false)
        #expect(await engine.state.timedPause == nil)
        #expect(await method(engine) == .off)

        await engine.setEnabled(true)
        #expect(await engine.state.timedPause == nil)
        #expect(await method(engine) == .hardware)
    }

    @Test("Pause expiry reapplies the current schedule instead of sticking neutral")
    func expiryRestoresWarmth() async throws {
        let store = InMemoryDDCSnapshotStore()
        let display = DisplayIdentity.fixture()
        let engine = await warmedEngine(
            ddc: FaultInjectingBackend(method: .hardware), store: store, display: display)

        await engine.setTimedPause(TimedPause(until: Date().addingTimeInterval(0.05), kind: .oneHour))
        #expect(await method(engine) == .off)

        try await Task.sleep(nanoseconds: 800_000_000)
        #expect(await engine.state.timedPause == nil)
        #expect(await method(engine) == .hardware)
    }

    @Test("Resume does not undo an excluded frontmost app")
    func composesWithExclusion() async {
        let store = InMemoryDDCSnapshotStore()
        let display = DisplayIdentity.fixture()
        let engine = await warmedEngine(
            ddc: FaultInjectingBackend(method: .hardware), store: store, display: display)

        await engine.setExcludedApps(["com.x"])
        await engine.setFrontmostApp("com.x")
        await engine.setTimedPause(PausePolicy.oneHour(from: Date()))
        #expect(await method(engine) == .off)

        await engine.setTimedPause(nil)
        #expect(await method(engine) == .off)

        await engine.setExcludedApps([])
        #expect(await method(engine) == .hardware)
    }

    @Test("Fullscreen preference suspends only the covered display")
    func fullscreenIsPerDisplay() async {
        let store = InMemoryDDCSnapshotStore()
        let displayA = DisplayIdentity.fixture(cgUUID: UUID(), displayID: 1)
        let displayB = DisplayIdentity.fixture(cgUUID: UUID(), displayID: 2)
        let engine = WarmthEngine.test(
            backends: [FaultInjectingBackend(method: .hardware)], store: store, displays: [displayA, displayB])
        await engine.start()
        for display in [displayA, displayB] {
            await engine.setHardwareDDCEnabled(true, for: display)
            await engine.setWarmth(WarmthLevel(strength: 0.8), for: display)
        }
        await engine.setEnabled(true)
        await engine.setScheduleMode(.alwaysOn)

        await engine.setFrontmostApp("com.player", onDisplays: [1], fullScreenDisplays: [1])
        #expect(await method(engine, for: displayA) == .hardware)
        #expect(await method(engine, for: displayB) == .hardware)

        await engine.setPausesForFullScreen(true)
        let active = await engine.state
        #expect(active.pausesForFullScreen)
        #expect(active.isFullScreenPauseActive)
        #expect(await method(engine, for: displayA) == .off)
        #expect(await method(engine, for: displayB) == .hardware)

        await engine.setFrontmostApp("com.player", onDisplays: [2], fullScreenDisplays: [])
        #expect(await engine.state.isFullScreenPauseActive == false)
        #expect(await method(engine, for: displayA) == .hardware)
        #expect(await method(engine, for: displayB) == .hardware)

        await engine.setPausesForFullScreen(false)
        await engine.setFrontmostApp("com.player", onDisplays: [1], fullScreenDisplays: [1])
        #expect(await method(engine, for: displayA) == .hardware)
    }

    @Test("A pause prepared before start is honored by the first apply")
    func preparedPauseSurvivesStart() async {
        let store = InMemoryDDCSnapshotStore()
        let display = DisplayIdentity.fixture()
        let engine = WarmthEngine.test(
            backends: [FaultInjectingBackend(method: .hardware)], store: store, displays: [display])
        await engine.prepareSessionPause(PausePolicy.oneHour(from: Date()), pausesForFullScreen: true)
        await engine.start()
        await engine.setHardwareDDCEnabled(true, for: display)
        await engine.setEnabled(true)
        await engine.setScheduleMode(.alwaysOn)
        await engine.setWarmth(WarmthLevel(strength: 0.8), for: display)

        #expect(await engine.state.timedPause != nil)
        #expect(await engine.state.pausesForFullScreen)
        #expect(await method(engine) == .off)
    }
}
