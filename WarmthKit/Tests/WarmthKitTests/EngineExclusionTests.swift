import Testing
import Foundation
@testable import WarmthKit
@testable import HardwareDDC
@testable import WarmthCore

/// Per-app exclusions: while an *excluded* app is the frontmost app the engine suspends warmth across
/// all displays (true colour), composing with — not clobbering — hold-to-reveal. Driven headlessly
/// through `setExcludedApps` / `setFrontmostApp` and asserted via `appliedMethod` (`.off` == suspended,
/// `.hardware` == the warm DDC layer), mirroring `EngineRecoveryTests`' harness.
@Suite("Engine per-app exclusions (suspend-while-frontmost)")
struct EngineExclusionTests {

    /// A single DDC-warmed display, enabled, always-on, warmth > 0 — so an un-suspended display reads
    /// `appliedMethod == .hardware` and a suspended one reads `.off`.
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

    private func appliedMethod(_ engine: WarmthEngine) async -> DisplayMethod? {
        await engine.state.displays.first?.appliedMethod
    }

    @Test("Excluded app frontmost → warmth suspended (appliedMethod .off)")
    func excludedFrontmostSuspends() async {
        let store = InMemoryDDCSnapshotStore()
        let display = DisplayIdentity.fixture()
        let engine = await warmedEngine(ddc: FaultInjectingBackend(method: .hardware), store: store, display: display)

        #expect(await appliedMethod(engine) == .hardware)            // warming before any exclusion

        await engine.setExcludedApps(["com.x"])
        await engine.setFrontmostApp("com.x")
        #expect(await appliedMethod(engine) == .off)                 // suspended while excluded app is front
    }

    @Test("Focus leaves the excluded app → warmth resumes")
    func leavingExcludedResumes() async {
        let store = InMemoryDDCSnapshotStore()
        let display = DisplayIdentity.fixture()
        let engine = await warmedEngine(ddc: FaultInjectingBackend(method: .hardware), store: store, display: display)

        await engine.setExcludedApps(["com.x"])
        await engine.setFrontmostApp("com.x")
        #expect(await appliedMethod(engine) == .off)

        await engine.setFrontmostApp("com.y")                        // a non-excluded app takes focus
        #expect(await appliedMethod(engine) == .hardware)            // warmth resumes
    }

    @Test("Removing the exclusion while its app is front → warmth resumes")
    func removingExclusionResumes() async {
        let store = InMemoryDDCSnapshotStore()
        let display = DisplayIdentity.fixture()
        let engine = await warmedEngine(ddc: FaultInjectingBackend(method: .hardware), store: store, display: display)

        await engine.setExcludedApps(["com.x"])
        await engine.setFrontmostApp("com.x")
        #expect(await appliedMethod(engine) == .off)

        await engine.setExcludedApps([])                             // un-exclude the still-frontmost app
        #expect(await appliedMethod(engine) == .hardware)            // warmth resumes immediately
    }

    @Test("Composes with reveal: ending reveal must NOT resume while still excluded")
    func composesWithReveal() async {
        let store = InMemoryDDCSnapshotStore()
        let display = DisplayIdentity.fixture()
        let engine = await warmedEngine(ddc: FaultInjectingBackend(method: .hardware), store: store, display: display)

        await engine.setExcludedApps(["com.x"])
        await engine.setFrontmostApp("com.x")
        await engine.beginReveal()                                   // both suspend reasons active
        #expect(await appliedMethod(engine) == .off)

        await engine.endReveal()                                     // reveal ends, but the app is still excluded
        #expect(await appliedMethod(engine) == .off)                 // STILL suspended — the two compose
    }

    @Test("nil frontmost app → not suspended")
    func nilFrontmostNotSuspended() async {
        let store = InMemoryDDCSnapshotStore()
        let display = DisplayIdentity.fixture()
        let engine = await warmedEngine(ddc: FaultInjectingBackend(method: .hardware), store: store, display: display)

        await engine.setExcludedApps(["com.x"])
        await engine.setFrontmostApp(nil)                            // no resolvable frontmost app
        #expect(await appliedMethod(engine) == .hardware)            // warming continues
    }

    @Test("Frontmost switching between two excluded apps stays suspended (change-gate no-op)")
    func frontmostChangeAmongExcludedStaysSuspended() async {
        let store = InMemoryDDCSnapshotStore()
        let display = DisplayIdentity.fixture()
        let engine = await warmedEngine(ddc: FaultInjectingBackend(method: .hardware), store: store, display: display)

        await engine.setExcludedApps(["com.x", "com.y"])
        await engine.setFrontmostApp("com.x")
        #expect(await appliedMethod(engine) == .off)

        await engine.setFrontmostApp("com.y")                        // switch between two excluded apps
        #expect(await appliedMethod(engine) == .off)                 // still suspended; the change-gate skips reapply
    }

    // MARK: - Per-display suspend (multi-monitor refinement, Session 9)

    /// Two DDC-warmed displays with distinct `CGDirectDisplayID`s, enabled, always-on, warmth > 0 —
    /// so each un-suspended display reads `appliedMethod == .hardware` and a suspended one reads `.off`.
    private func warmedTwoDisplayEngine(
        store: InMemoryDDCSnapshotStore, displays: [DisplayIdentity]
    ) async -> WarmthEngine {
        let engine = WarmthEngine.test(backends: [FaultInjectingBackend(method: .hardware)], store: store, displays: displays)
        await engine.start()
        for display in displays { await engine.setHardwareDDCEnabled(true, for: display) }
        await engine.setEnabled(true)
        await engine.setScheduleMode(.alwaysOn)
        for display in displays { await engine.setWarmth(WarmthLevel(strength: 0.8), for: display) }
        return engine
    }

    private func appliedMethod(_ engine: WarmthEngine, for id: DisplayIdentity) async -> DisplayMethod? {
        await engine.state.displays.first(where: { $0.id == id })?.appliedMethod
    }

    @Test("Excluded app on ONE display of two → only that display suspends, the other stays warm")
    func excludedOnOneDisplaySuspendsOnlyThatDisplay() async {
        let store = InMemoryDDCSnapshotStore()
        let displayA = DisplayIdentity.fixture(cgUUID: UUID(), displayID: 1)
        let displayB = DisplayIdentity.fixture(cgUUID: UUID(), displayID: 2)
        let engine = await warmedTwoDisplayEngine(store: store, displays: [displayA, displayB])

        #expect(await appliedMethod(engine, for: displayA) == .hardware)   // both warm before exclusion
        #expect(await appliedMethod(engine, for: displayB) == .hardware)

        await engine.setExcludedApps(["com.x"])
        await engine.setFrontmostApp("com.x", onDisplays: [1])             // excluded app lives on display A only

        #expect(await appliedMethod(engine, for: displayA) == .off)        // A goes true-colour
        #expect(await appliedMethod(engine, for: displayB) == .hardware)   // B stays warm
    }

    @Test("nil display set (whole-app / single-display fallback) suspends ALL displays — legacy behaviour")
    func nilDisplaySetSuspendsAll() async {
        let store = InMemoryDDCSnapshotStore()
        let displayA = DisplayIdentity.fixture(cgUUID: UUID(), displayID: 1)
        let displayB = DisplayIdentity.fixture(cgUUID: UUID(), displayID: 2)
        let engine = await warmedTwoDisplayEngine(store: store, displays: [displayA, displayB])

        await engine.setExcludedApps(["com.x"])
        await engine.setFrontmostApp("com.x", onDisplays: nil)             // unresolved set → suspend everywhere

        #expect(await appliedMethod(engine, for: displayA) == .off)
        #expect(await appliedMethod(engine, for: displayB) == .off)
    }

    @Test("Moving the excluded app's window between displays moves the suspend with it")
    func suspendFollowsExcludedAppAcrossDisplays() async {
        let store = InMemoryDDCSnapshotStore()
        let displayA = DisplayIdentity.fixture(cgUUID: UUID(), displayID: 1)
        let displayB = DisplayIdentity.fixture(cgUUID: UUID(), displayID: 2)
        let engine = await warmedTwoDisplayEngine(store: store, displays: [displayA, displayB])

        await engine.setExcludedApps(["com.x"])
        await engine.setFrontmostApp("com.x", onDisplays: [1])
        #expect(await appliedMethod(engine, for: displayA) == .off)
        #expect(await appliedMethod(engine, for: displayB) == .hardware)

        await engine.setFrontmostApp("com.x", onDisplays: [2])             // same app, window dragged to display B
        #expect(await appliedMethod(engine, for: displayA) == .hardware)   // A warms back up
        #expect(await appliedMethod(engine, for: displayB) == .off)        // B now suspended
    }

    @Test("Excluded app spanning both displays suspends both")
    func excludedSpanningBothDisplaysSuspendsBoth() async {
        let store = InMemoryDDCSnapshotStore()
        let displayA = DisplayIdentity.fixture(cgUUID: UUID(), displayID: 1)
        let displayB = DisplayIdentity.fixture(cgUUID: UUID(), displayID: 2)
        let engine = await warmedTwoDisplayEngine(store: store, displays: [displayA, displayB])

        await engine.setExcludedApps(["com.x"])
        await engine.setFrontmostApp("com.x", onDisplays: [1, 2])          // window straddles both monitors

        #expect(await appliedMethod(engine, for: displayA) == .off)
        #expect(await appliedMethod(engine, for: displayB) == .off)
    }

    @Test("Leaving the excluded app re-warms the previously-suspended display")
    func leavingExcludedResumesPerDisplay() async {
        let store = InMemoryDDCSnapshotStore()
        let displayA = DisplayIdentity.fixture(cgUUID: UUID(), displayID: 1)
        let displayB = DisplayIdentity.fixture(cgUUID: UUID(), displayID: 2)
        let engine = await warmedTwoDisplayEngine(store: store, displays: [displayA, displayB])

        await engine.setExcludedApps(["com.x"])
        await engine.setFrontmostApp("com.x", onDisplays: [1])
        #expect(await appliedMethod(engine, for: displayA) == .off)

        await engine.setFrontmostApp("com.y", onDisplays: [1])             // a non-excluded app takes focus
        #expect(await appliedMethod(engine, for: displayA) == .hardware)   // A warms back
        #expect(await appliedMethod(engine, for: displayB) == .hardware)
    }
}
