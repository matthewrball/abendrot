import Testing
import Foundation
@testable import WarmthKit
@testable import HardwareDDC
@testable import WarmthCore

/// The experimental "keep other windows warm" exclusion. While an excluded app is in front, a display
/// hands its warmth from the normal layer to the window filter, and hands it back when focus leaves.
@Suite("Engine window filter for excluded apps")
struct EngineWindowFilterTests {

    private struct Rig {
        let engine: WarmthEngine
        let gamma: FaultInjectingBackend
        let windowFilter: FaultInjectingBackend
        let display: DisplayIdentity
    }

    private func rig(keepsOtherWindowsWarm: Bool = true) async -> Rig {
        let gamma = FaultInjectingBackend(method: .gamma)
        let windowFilter = FaultInjectingBackend(method: .windowFilter)
        let display = DisplayIdentity.fixture()
        let engine = WarmthEngine.test(backends: [gamma, windowFilter], store: InMemoryDDCSnapshotStore(),
                                       displays: [display])
        await engine.start()
        await engine.setEnabled(true)
        await engine.setScheduleMode(.alwaysOn)
        await engine.setWarmth(WarmthLevel(strength: 0.8), for: display)
        await engine.setKeepsOtherWindowsWarm(keepsOtherWindowsWarm)
        await engine.setExcludedApps(["com.x"])
        return Rig(engine: engine, gamma: gamma, windowFilter: windowFilter, display: display)
    }

    private func method(_ rig: Rig) async -> DisplayMethod? {
        await rig.engine.state.displays.first?.appliedMethod
    }

    @Test("With the setting on, an excluded app hands the display to the window filter")
    func handsOverToWindowFilter() async {
        let rig = await rig()
        #expect(await method(rig) == .gamma)
        let warm = await rig.gamma.applied[rig.display]

        await rig.engine.setFrontmostApp("com.x")
        #expect(await method(rig) == .windowFilter)
        #expect(await rig.windowFilter.applied[rig.display] == warm)
        // The display transform goes neutral so the excluded window shows true color.
        #expect(await rig.gamma.applied[rig.display] == .neutral)
    }

    @Test("Focus leaving the excluded app removes the window filter and restores the display layer")
    func handsBack() async {
        let rig = await rig()
        let warm = await rig.gamma.applied[rig.display]
        await rig.engine.setFrontmostApp("com.x")
        await rig.engine.setFrontmostApp("com.y")

        #expect(await method(rig) == .gamma)
        #expect(await rig.windowFilter.applied[rig.display] == .neutral)
        #expect(await rig.gamma.applied[rig.display] == warm)
    }

    @Test("With the setting off, an excluded app still pauses the whole display")
    func settingOffKeepsDisplayPause() async {
        let rig = await rig(keepsOtherWindowsWarm: false)
        await rig.engine.setFrontmostApp("com.x")

        #expect(await method(rig) == .off)
        #expect(await rig.windowFilter.callLog.contains("apply") == false)
    }

    @Test("Turning the setting off while the excluded app is in front pauses the whole display")
    func turningOffWhileExcluded() async {
        let rig = await rig()
        await rig.engine.setFrontmostApp("com.x")
        await rig.engine.setKeepsOtherWindowsWarm(false)

        #expect(await method(rig) == .off)
        #expect(await rig.windowFilter.applied[rig.display] == .neutral)
        #expect(await rig.gamma.applied[rig.display] == .neutral)
    }

    @Test("A window filter failure falls back to the display pause and reports it")
    func failureFallsBack() async {
        let rig = await rig()
        await rig.windowFilter.setFault(.beforeApply)
        await rig.engine.setFrontmostApp("com.x")

        let display = await rig.engine.state.displays.first
        #expect(display?.appliedMethod == .off)
        #expect(display?.lastError?.method == .windowFilter)
        #expect(await rig.windowFilter.callLog.last == "reset")
        #expect(await rig.gamma.applied[rig.display] == .neutral)
    }

    @Test("Warmth at zero while excluded removes the window filter, and warmth returning doesn't stack")
    func zeroWarmthRemovesPanel() async {
        let rig = await rig()
        await rig.engine.setFrontmostApp("com.x")
        #expect(await method(rig) == .windowFilter)

        await rig.engine.setWarmth(.off, for: rig.display)
        #expect(await rig.windowFilter.applied[rig.display] == .neutral)

        await rig.engine.setFrontmostApp("com.y")
        await rig.engine.setWarmth(WarmthLevel(strength: 0.8), for: rig.display)
        #expect(await method(rig) == .gamma)
        #expect(await rig.windowFilter.applied[rig.display] == .neutral)
    }

    @Test("Reveal and full screen still turn the display fully neutral")
    func strongerSuspensionsWin() async {
        let rig = await rig()
        await rig.engine.setFrontmostApp("com.x")
        await rig.engine.beginReveal()
        #expect(await method(rig) == .off)
        #expect(await rig.windowFilter.applied[rig.display] == .neutral)
        await rig.engine.endReveal()
        #expect(await method(rig) == .windowFilter)

        await rig.engine.setPausesForFullScreen(true)
        await rig.engine.setFrontmostApp("com.x", fullScreenDisplays: [rig.display.currentDisplayID])
        #expect(await method(rig) == .off)
        #expect(await rig.windowFilter.applied[rig.display] == .neutral)
    }

    @Test("Hardware control keeps the whole-display pause")
    func hardwareKeepsDisplayPause() async {
        let ddc = FaultInjectingBackend(method: .hardware)
        let windowFilter = FaultInjectingBackend(method: .windowFilter)
        let display = DisplayIdentity.fixture()
        let engine = WarmthEngine.test(backends: [ddc, windowFilter], store: InMemoryDDCSnapshotStore(),
                                       displays: [display])
        await engine.start()
        await engine.setHardwareDDCEnabled(true, for: display)
        await engine.setEnabled(true)
        await engine.setScheduleMode(.alwaysOn)
        await engine.setWarmth(WarmthLevel(strength: 0.8), for: display)
        await engine.setKeepsOtherWindowsWarm(true)
        await engine.setExcludedApps(["com.x"])
        await engine.setFrontmostApp("com.x")

        #expect(await engine.state.displays.first?.appliedMethod == .off)
        #expect(await windowFilter.callLog.contains("apply") == false)
    }

    @Test("Shutdown removes the window filter")
    func shutdownResets() async {
        let rig = await rig()
        await rig.engine.setFrontmostApp("com.x")
        await rig.engine.shutdown()
        #expect(await rig.windowFilter.applied[rig.display] == .neutral)
    }
}
