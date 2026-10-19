import Testing
import Foundation
@testable import WarmthKit
@testable import WarmthKitPrivate
@testable import WarmthCore
@testable import HardwareDDC

@Suite("Color filter recovery")
struct ColorFilterTests {
    @Test("automatic support stays within the visually verified hardware and OS")
    func verifiedConfigurationOnly() {
        let version = OperatingSystemVersion(majorVersion: 26, minorVersion: 6, patchVersion: 0)
        #expect(ColorFilterBackend.supports(chipBrand: "Apple M5 Pro", os: version, builtIn: true))
        #expect(!ColorFilterBackend.supports(chipBrand: "Apple M5 Pro", os: version, builtIn: false))
        #expect(!ColorFilterBackend.supports(chipBrand: "Apple M5 Max", os: version, builtIn: true))
        #expect(!ColorFilterBackend.supports(chipBrand: "Apple M5 Pro", os: .init(majorVersion: 26, minorVersion: 5, patchVersion: 1), builtIn: true))
    }

    @Test("full warmth, disable, re-enable and disconnect reach the filter backend")
    func lifecycle() async {
        let display = DisplayIdentity.fixture(transport: .builtIn)
        let filter = FaultInjectingBackend(method: .colorFilter)
        let engine = WarmthEngine.test(backends: [filter], store: InMemoryDDCSnapshotStore(), displays: [display])
        await engine.start()
        await engine.setScheduleMode(.alwaysOn)
        await engine.setWarmth(.init(strength: 1), warmestPoint: .everydayWarmest)
        await engine.setEnabled(true)
        #expect(await engine.state.displays.first?.appliedMethod == .colorFilter)
        #expect(await filter.applied[display] == .everydayWarmest)
        await engine.beginReveal()
        #expect(await filter.applied[display] == .neutral)
        await engine.endReveal()
        #expect(await filter.applied[display] == .everydayWarmest)
        await engine.setPreferredMethod(.overlay, for: display)
        #expect(await filter.applied[display] == .neutral)
        await engine.setPreferredMethod(nil, for: display)
        #expect(await filter.applied[display] == .everydayWarmest)
        await engine.setPrivateAPIsEnabled(false)
        #expect(await filter.applied[display] == .neutral)
        await engine.setPrivateAPIsEnabled(true)
        #expect(await filter.applied[display] == .everydayWarmest)
        await engine.setEnabled(false)
        #expect(await filter.applied[display] == .neutral)
        await engine.setEnabled(true)
        #expect(await filter.applied[display] == .everydayWarmest)
        await engine.simulateReconfiguration(present: [])
        #expect(await filter.applied[display] == .neutral)
        await engine.shutdown()
    }

    @Test("a partial private-filter failure is reset and reported as off, never as success or tint")
    func failedApplyIsHonest() async {
        let display = DisplayIdentity.fixture(transport: .builtIn)
        let filter = FaultInjectingBackend(method: .colorFilter)
        await filter.setFault(.midApply)
        let engine = WarmthEngine.test(backends: [filter], store: InMemoryDDCSnapshotStore(), displays: [display])
        await engine.start()
        await engine.setScheduleMode(.alwaysOn)
        await engine.setEnabled(true)
        #expect(await engine.state.displays.first?.appliedMethod == .off)
        #expect(await engine.state.displays.first?.lastError?.method == .colorFilter)
        #expect(await filter.applied[display] == .neutral)
        await engine.shutdown()
    }

    @Test("display recovery rebuilds a stale compositor even when warmth has not changed")
    func staleCompositorRecovers() async {
        let display = DisplayIdentity.fixture(transport: .builtIn)
        let filter = StaleColorFilterBackend()
        let engine = WarmthEngine.test(backends: [filter], store: InMemoryDDCSnapshotStore(), displays: [display])
        await engine.start()
        await engine.setScheduleMode(.alwaysOn)
        await engine.setWarmth(.init(strength: 1), warmestPoint: .everydayWarmest)
        await engine.setEnabled(true)
        #expect(await filter.applied[display] == .everydayWarmest)

        await filter.loseCompositor(for: display)
        await engine.setWarmth(.init(strength: 0.99))
        await engine.setWarmth(.init(strength: 1))
        #expect(await filter.applied[display] == .neutral)
        #expect(await engine.state.displays.first?.appliedMethod == .colorFilter)

        await engine.simulateReconfiguration(present: [display])
        #expect(await filter.applied[display] == .everydayWarmest)
        #expect(await engine.state.globalWarmth.strength == 1)
        #expect(await engine.state.displays.first?.appliedMethod == .colorFilter)

        // WindowServer can still be settling after the first recovery attempt.
        await filter.loseCompositor(for: display)
        await engine.simulateCatchUpReassert()
        #expect(await filter.applied[display] == .everydayWarmest)

        await engine.beginReveal()
        await engine.simulateReconfiguration(present: [display])
        #expect(await filter.applied[display] == .neutral)
        await engine.endReveal()
        #expect(await filter.applied[display] == .everydayWarmest)
        await engine.setEnabled(false)
        await engine.simulateReconfiguration(present: [display])
        #expect(await filter.applied[display] == .neutral)
        await engine.shutdown()
    }
}

/// Reproduces the observed WindowServer failure: gain writes succeed, but only recreation recovers.
private actor StaleColorFilterBackend: WarmthBackend {
    nonisolated let method: DisplayMethod = .colorFilter
    private(set) var applied: [DisplayIdentity: Kelvin] = [:]
    private var stale: Set<DisplayIdentity> = []

    func classify(_ identity: DisplayIdentity) async -> Capability<Void> { .supported(()) }
    func loseCompositor(for identity: DisplayIdentity) {
        stale.insert(identity)
        applied[identity] = .neutral
    }
    func apply(_ kelvin: Kelvin, to identity: DisplayIdentity) async throws {
        if !stale.contains(identity) { applied[identity] = kelvin }
    }
    func reset(_ identity: DisplayIdentity) async throws {
        stale.remove(identity)
        applied[identity] = .neutral
    }
}
