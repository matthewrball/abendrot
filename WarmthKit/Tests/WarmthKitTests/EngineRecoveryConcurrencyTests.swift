import Testing
import Foundation
@testable import WarmthKit
@testable import WarmthCore
@testable import HardwareDDC

@Suite("Recovery respects newer neutral requests", .timeLimit(.minutes(1)))
struct EngineRecoveryConcurrencyTests {
    @Test("Off requested during a recovery write leaves the display neutral")
    func offDuringRecovery() async {
        await assertNeutralRequestWins(reveal: false)
    }

    @Test("Reveal requested during a recovery write leaves the display neutral")
    func revealDuringRecovery() async {
        await assertNeutralRequestWins(reveal: true)
    }

    @Test("Shutdown drains a recovery write before restoring the display to neutral")
    func shutdownDuringRecovery() async {
        let display = DisplayIdentity.fixture(transport: .builtIn)
        let filter = SuspendedRecoveryColorFilter()
        let engine = WarmthEngine.test(
            backends: [filter], store: InMemoryDDCSnapshotStore(), displays: [display]
        )
        await engine.start()
        await engine.setScheduleMode(.alwaysOn)
        await engine.setWarmth(.init(strength: 1), warmestPoint: .everydayWarmest)
        await engine.setEnabled(true)
        #expect(await filter.applied[display] == .everydayWarmest)

        await filter.suspendNextApply()
        let recovery = Task { await engine.simulateReconfiguration(present: [display]) }
        let suspended = await waitUntil { await filter.isSuspended }
        #expect(suspended, "Recovery must reach the stalled backend write")

        let shutdown = Task { await engine.shutdown() }
        let shuttingDown = await waitUntil { await engine.shutdownHasStartedForTesting }
        #expect(shuttingDown, "Shutdown must begin before the older recovery write resumes")
        await filter.resumeApply()
        await recovery.value
        await shutdown.value

        #expect(await filter.applied[display] == .neutral)
    }

    private func assertNeutralRequestWins(reveal: Bool) async {
        let display = DisplayIdentity.fixture(transport: .builtIn)
        let filter = SuspendedRecoveryColorFilter()
        let engine = WarmthEngine.test(
            backends: [filter], store: InMemoryDDCSnapshotStore(), displays: [display]
        )
        await engine.start()
        await engine.setScheduleMode(.alwaysOn)
        await engine.setWarmth(.init(strength: 1), warmestPoint: .everydayWarmest)
        await engine.setEnabled(true)
        #expect(await filter.applied[display] == .everydayWarmest)
        #expect(await engine.state.displays.first?.appliedMethod == .colorFilter)

        await filter.suspendNextApply()
        let recovery = Task { await engine.simulateReconfiguration(present: [display]) }
        let suspended = await waitUntil { await filter.isSuspended }
        #expect(suspended, "Recovery must reach the stalled backend write")

        let neutralRequest = Task {
            if reveal {
                await engine.beginReveal()
            } else {
                await engine.setEnabled(false)
            }
        }
        // Wait for the request, not its completion: a serialized engine may finish it only
        // after the older write is released.
        let requested = await waitUntil {
            let state = await engine.state
            return reveal ? state.isRevealing : !state.isEnabled
        }
        #expect(requested, "The newer neutral request must be accepted before recovery resumes")
        await filter.resumeApply()
        await recovery.value
        await neutralRequest.value

        #expect(await filter.applied[display] == .neutral)
        let state = await engine.state
        #expect(state.displays.first?.appliedMethod == .off)
        #expect(reveal ? state.isRevealing : !state.isEnabled)
        await engine.shutdown()
    }

    private func waitUntil(_ predicate: () async -> Bool) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while clock.now < deadline {
            if await predicate() { return true }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return false
    }
}

private actor SuspendedRecoveryColorFilter: WarmthBackend {
    nonisolated let method: DisplayMethod = .colorFilter
    private(set) var applied: [DisplayIdentity: Kelvin] = [:]
    private var shouldSuspend = false
    private var continuation: CheckedContinuation<Void, Never>?
    var isSuspended: Bool { continuation != nil }

    func classify(_ identity: DisplayIdentity) async -> Capability<Void> { .supported(()) }

    func suspendNextApply() { shouldSuspend = true }

    func resumeApply() {
        // Also disarm on a failed rendezvous so a late apply cannot strand the test.
        shouldSuspend = false
        continuation?.resume()
        continuation = nil
    }

    func apply(_ kelvin: Kelvin, to identity: DisplayIdentity) async throws {
        if shouldSuspend {
            shouldSuspend = false
            await withCheckedContinuation { continuation = $0 }
        }
        applied[identity] = kelvin
    }

    func reset(_ identity: DisplayIdentity) async throws {
        applied[identity] = .neutral
    }
}
