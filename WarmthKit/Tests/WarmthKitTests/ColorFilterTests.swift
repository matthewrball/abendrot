import Testing
import Foundation
@testable import WarmthKit
@testable import WarmthKitPrivate
@testable import WarmthCore
@testable import HardwareDDC

@Suite("Color filter recovery")
struct ColorFilterTests {
    @Test("native matrix gains use the sRGB linear-light transfer")
    func linearNativeGains() {
        #expect(ColorFilterBackend.linearGain(0) == 0)
        #expect(ColorFilterBackend.linearGain(1) == 1)
        #expect(abs(ColorFilterBackend.linearGain(0.5) - 0.21404114) < 0.000001)
        #expect(abs(ColorFilterBackend.linearGain(0.04045) - 0.003130805) < 0.000001)
    }

    @Test("helper failure immediately clears an active filter badge")
    func helperFailureIsHonest() async {
        let display = DisplayIdentity.fixture(transport: .builtIn)
        let filter = FaultInjectingBackend(method: .colorFilter)
        let engine = WarmthEngine.test(backends: [filter], store: InMemoryDDCSnapshotStore(), displays: [display])
        await engine.start()
        await engine.setScheduleMode(.alwaysOn)
        await engine.setEnabled(true)
        #expect(await engine.state.displays.first?.appliedMethod == .colorFilter)
        await engine.colorFilterFailed()
        #expect(await engine.state.displays.first?.appliedMethod == .off)
        #expect(await engine.state.displays.first?.lastError?.method == .colorFilter)
        await engine.shutdown()
    }

    @Test("helper failure during apply cannot be overwritten by the older successful return", .timeLimit(.minutes(1)))
    func helperFailureDuringApplyRemainsOff() async {
        await assertHelperFailureDuringApply(retrySucceeds: false)
    }

    @Test("a fresh successful apply confirms replacement helper warmth without an intervening reset", .timeLimit(.minutes(1)))
    func freshHelperRetrySucceeds() async {
        await assertHelperFailureDuringApply(retrySucceeds: true)
    }

    private func assertHelperFailureDuringApply(retrySucceeds: Bool) async {
        let display = DisplayIdentity.fixture(transport: .builtIn)
        let filter = SuspendedHelperFailureBackend()
        let engine = WarmthEngine.test(backends: [filter], store: InMemoryDDCSnapshotStore(), displays: [display])
        await engine.start()
        await engine.setScheduleMode(.alwaysOn)
        await engine.setWarmth(.init(strength: 1), warmestPoint: .everydayWarmest)
        await engine.setEnabled(true)
        #expect(await engine.state.displays.first?.appliedMethod == .colorFilter)
        let successfulApplies = await filter.successfulApplies
        let applyAttempts = await filter.applyAttempts
        let resetCount = await filter.resetCount

        await filter.suspendNextApply()
        let applying = Task { await engine.simulateCatchUpReassert() }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while !(await filter.isSuspended), clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
        #expect(await filter.isSuspended, "The older apply must be in flight before helper failure")

        await engine.colorFilterFailed()
        #expect(await engine.state.displays.first?.appliedMethod == .off)
        await filter.resumeApply(retrySucceeds: retrySucceeds)
        await applying.value

        // The fake returns success after the failure notification, reproducing the race.
        #expect(await filter.applyAttempts == applyAttempts + 2)
        #expect(await filter.successfulApplies == successfulApplies + (retrySucceeds ? 2 : 1))
        if retrySucceeds {
            #expect(await filter.resetCount == resetCount)
            #expect(await engine.state.displays.first?.appliedMethod == .colorFilter)
            #expect(await engine.state.displays.first?.lastError == nil)
            #expect(await filter.applied[display] == .everydayWarmest)
        } else {
            #expect(await engine.state.displays.first?.appliedMethod == .off)
            #expect(await engine.state.displays.first?.lastError?.method == .colorFilter)
            #expect(await filter.applied[display] == .neutral)
        }
        await engine.shutdown()
    }

    @Test("unverified recovery is visible even when the capable display is already off")
    func pendingRecoveryOnDisabledDisplay() async {
        let display = DisplayIdentity.fixture(transport: .builtIn)
        let filter = FaultInjectingBackend(method: .colorFilter)
        let engine = WarmthEngine.test(backends: [filter], store: InMemoryDDCSnapshotStore(), displays: [display])
        await engine.start()
        await engine.setEnabled(false)
        await filter.setFault(.onReset)
        await engine.colorFilterFailed(recoveryVerified: false)
        #expect(await engine.state.displays.first?.appliedMethod == .off)
        #expect(await engine.state.displays.first?.lastError?.message.contains("Recovery is pending") == true)
        await engine.simulateCatchUpReassert()
        #expect(await engine.state.displays.first?.lastError?.message.contains("Recovery is pending") == true)
        await filter.setFault(nil)
        await engine.restoreAllDisplays()
        #expect(await engine.state.displays.first?.lastError == nil)
        await engine.shutdown()
    }

    @Test("failed native reset remains pending and blocks another warming layer",
          arguments: ["off", "reveal", "restoreAll", "shutdown", "overlay", "privateOff"])
    func failedResetRemainsPending(action: String) async {
        let display = DisplayIdentity.fixture(transport: .builtIn)
        let filter = FaultInjectingBackend(method: .colorFilter)
        let overlay = FaultInjectingBackend(method: .overlay)
        let engine = WarmthEngine.test(backends: [filter, overlay], store: InMemoryDDCSnapshotStore(), displays: [display])
        await engine.start()
        await engine.setScheduleMode(.alwaysOn)
        await engine.setWarmth(.init(strength: 1), warmestPoint: .everydayWarmest)
        await engine.setEnabled(true)
        await filter.setFault(.onReset)
        switch action {
        case "off": await engine.setEnabled(false)
        case "reveal": await engine.beginReveal()
        case "restoreAll": await engine.restoreAllDisplays()
        case "shutdown": await engine.shutdown()
        case "overlay": await engine.setPreferredMethod(.overlay, for: display)
        case "privateOff": await engine.setPrivateAPIsEnabled(false)
        default: Issue.record("Unknown reset action")
        }
        #expect(await filter.applied[display] == .everydayWarmest)
        #expect(await engine.state.displays.first?.appliedMethod == .off)
        #expect(await engine.state.displays.first?.lastError?.message.contains("Recovery is pending") == true)
        await engine.simulateCatchUpReassert()
        #expect(await engine.state.displays.first?.lastError?.message.contains("Recovery is pending") == true)
        #expect(await overlay.callLog.contains("apply") == false)
        await filter.setFault(nil)
        await engine.restoreAllDisplays()
        #expect(await filter.applied[display] == .neutral)
        #expect(await engine.state.displays.first?.lastError == nil)
        await engine.shutdown()
    }

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

    @Test("display recovery resends unchanged warmth without resetting the native filter")
    func reassertDoesNotResetNativeFilter() async {
        let display = DisplayIdentity.fixture(transport: .builtIn)
        let filter = ReassertableColorFilterBackend()
        let engine = WarmthEngine.test(backends: [filter], store: InMemoryDDCSnapshotStore(), displays: [display])
        await engine.start()
        await engine.setScheduleMode(.alwaysOn)
        await engine.setWarmth(.init(strength: 1), warmestPoint: .everydayWarmest)
        await engine.setEnabled(true)
        #expect(await filter.applied[display] == .everydayWarmest)

        let initialApplyCount = await filter.applyCount
        let initialResetCount = await filter.resetCount
        await engine.simulateCatchUpReassert()
        #expect(await filter.applyCount == initialApplyCount + 1)
        #expect(await filter.applied[display] == .everydayWarmest)
        #expect(await filter.resetCount == initialResetCount)

        await filter.loseOutput(for: display)
        #expect(await filter.applied[display] == .neutral)
        #expect(await engine.state.displays.first?.appliedMethod == .colorFilter)

        await engine.simulateReconfiguration(present: [display])
        #expect(await filter.applied[display] == .everydayWarmest)
        #expect(await filter.resetCount == initialResetCount)
        #expect(await engine.state.globalWarmth.strength == 1)
        #expect(await engine.state.displays.first?.appliedMethod == .colorFilter)

        // WindowServer can still be settling after the first recovery attempt.
        await filter.loseOutput(for: display)
        await engine.simulateCatchUpReassert()
        #expect(await filter.applied[display] == .everydayWarmest)
        #expect(await filter.resetCount == initialResetCount)

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

/// Models a native matrix cleared by the system and restored by resending current warmth.
private actor ReassertableColorFilterBackend: WarmthBackend {
    nonisolated let method: DisplayMethod = .colorFilter
    private(set) var applied: [DisplayIdentity: Kelvin] = [:]
    private(set) var applyCount = 0
    private(set) var resetCount = 0

    func classify(_ identity: DisplayIdentity) async -> Capability<Void> { .supported(()) }
    func loseOutput(for identity: DisplayIdentity) {
        applied[identity] = .neutral
    }
    func apply(_ kelvin: Kelvin, to identity: DisplayIdentity) async throws {
        applyCount += 1
        applied[identity] = kelvin
    }
    func reset(_ identity: DisplayIdentity) async throws {
        resetCount += 1
        applied[identity] = .neutral
    }
}

private actor SuspendedHelperFailureBackend: WarmthBackend {
    nonisolated let method: DisplayMethod = .colorFilter
    private(set) var applied: [DisplayIdentity: Kelvin] = [:]
    private(set) var successfulApplies = 0
    private(set) var applyAttempts = 0
    private(set) var resetCount = 0
    private var futureApplyFails = false
    private var shouldSuspend = false
    private var continuation: CheckedContinuation<Void, Never>?
    var isSuspended: Bool { continuation != nil }

    func classify(_ identity: DisplayIdentity) async -> Capability<Void> { .supported(()) }
    func suspendNextApply() { shouldSuspend = true }
    func resumeApply(retrySucceeds: Bool) {
        // Also disarm a late apply if the bounded rendezvous failed.
        shouldSuspend = false
        futureApplyFails = !retrySucceeds
        continuation?.resume()
        continuation = nil
    }
    func apply(_ kelvin: Kelvin, to identity: DisplayIdentity) async throws {
        applyAttempts += 1
        if futureApplyFails { throw FaultError.injected(.beforeApply) }
        if shouldSuspend {
            shouldSuspend = false
            await withCheckedContinuation { continuation = $0 }
        }
        applied[identity] = kelvin
        successfulApplies += 1
    }
    func reset(_ identity: DisplayIdentity) async throws {
        resetCount += 1
        applied[identity] = .neutral
    }
}
