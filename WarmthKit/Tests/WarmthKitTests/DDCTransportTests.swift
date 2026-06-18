import Testing
import Foundation
@testable import HardwareDDC
@testable import WarmthCore

// MARK: - Transport: native snapshot, scaling, verify/retry

@Suite("DDC transport — snapshot, scaling, verify/retry")
struct DDCTransportTests {

    private func transport(_ provider: FakeBusProvider, _ store: InMemoryDDCSnapshotStore = InMemoryDDCSnapshotStore())
        -> IOAVServiceDDCTransport {
        IOAVServiceDDCTransport(provider: provider, store: store, timing: .immediate)
    }

    @Test("writeRGBGain snapshots native then writes each channel scaled relative to native")
    func writesScaledRelativeToNative() async throws {
        let id = DisplayIdentity.fixture()
        let bus = FakeI2CBus(native: [0x16: (100, 100), 0x18: (100, 100), 0x1A: (100, 100)])
        let provider = FakeBusProvider(); provider.install(bus, for: id)
        let store = InMemoryDDCSnapshotStore()
        let ddc = transport(provider, store)

        let gain = rgbGain(for: Kelvin(3000))
        try await ddc.writeRGBGain(gain, to: id)

        #expect(bus.currentValue(0x16) == DDCProtocol.scaledGain(native: 100, multiplier: gain.red, max: 100))
        #expect(bus.currentValue(0x18) == DDCProtocol.scaledGain(native: 100, multiplier: gain.green, max: 100))
        #expect(bus.currentValue(0x1A) == DDCProtocol.scaledGain(native: 100, multiplier: gain.blue, max: 100))

        // Native was persisted for restore-after-relaunch.
        let snapshot = await store.snapshot(for: id.persistentKey)
        #expect(snapshot?.native?.red.current == 100)
        #expect(snapshot?.native?.blue.max == 100)
    }

    @Test("a neutral (6500K) target leaves the panel at its native gain")
    func neutralIsNative() async throws {
        let id = DisplayIdentity.fixture()
        let bus = FakeI2CBus(native: [0x16: (90, 100), 0x18: (88, 100), 0x1A: (86, 100)])
        let provider = FakeBusProvider(); provider.install(bus, for: id)
        let ddc = transport(provider)

        try await ddc.writeRGBGain(rgbGain(for: Kelvin(6500)), to: id)
        #expect(bus.currentValue(0x16) == 90)
        #expect(bus.currentValue(0x18) == 88)
        #expect(bus.currentValue(0x1A) == 86)
    }

    @Test("restoreNativeGain writes back the snapshotted native values")
    func restoresNative() async throws {
        let id = DisplayIdentity.fixture()
        let bus = FakeI2CBus(native: [0x16: (90, 100), 0x18: (85, 100), 0x1A: (80, 100)])
        let provider = FakeBusProvider(); provider.install(bus, for: id)
        let ddc = transport(provider)

        try await ddc.writeRGBGain(rgbGain(for: Kelvin(2700)), to: id)
        #expect(bus.currentValue(0x16) != 90 || bus.currentValue(0x1A) != 80)   // warmed away from native

        try await ddc.restoreNativeGain(for: id)
        #expect(bus.currentValue(0x16) == 90)
        #expect(bus.currentValue(0x18) == 85)
        #expect(bus.currentValue(0x1A) == 80)
    }

    @Test("restoreNativeGain throws when a channel never verifies back to native (keeps display recoverable)")
    func restoreReportsPartialFailure() async throws {
        let id = DisplayIdentity.fixture()
        let bus = FakeI2CBus(native: [0x16: (90, 100), 0x18: (85, 100), 0x1A: (80, 100)])
        let provider = FakeBusProvider(); provider.install(bus, for: id)
        let ddc = transport(provider)

        try await ddc.writeRGBGain(rgbGain(for: Kelvin(2700)), to: id)   // snapshots native, warms
        bus.setIgnoreSets(true)                                          // panel now refuses writes
        await #expect(throws: DDCError.self) {                           // restore can't verify → must throw
            try await ddc.restoreNativeGain(for: id)
        }
    }

    @Test("verify mismatch throws after retries when the panel ignores gain writes")
    func verifyMismatchThrows() async throws {
        let id = DisplayIdentity.fixture()
        let bus = FakeI2CBus(native: [0x16: (100, 100), 0x18: (100, 100), 0x1A: (100, 100)])
        let provider = FakeBusProvider(); provider.install(bus, for: id)
        let ddc = transport(provider)

        bus.setIgnoreSets(true)   // panel locks gain → read-back never matches a warm target
        await #expect(throws: DDCError.self) {
            try await ddc.writeRGBGain(rgbGain(for: Kelvin(2700)), to: id)
        }
    }

    @Test("a single flaky read is retried and the probe still succeeds")
    func flakyReadRetried() async throws {
        let id = DisplayIdentity.fixture()
        let bus = FakeI2CBus(native: [0x16: (70, 100)])
        bus.failNextReads(1)
        let provider = FakeBusProvider(); provider.install(bus, for: id)
        let ddc = transport(provider)

        let capability = await ddc.probeRGBGainSupport(for: id)
        guard case .supported = capability else {
            Issue.record("expected .supported despite one flaky read, got \(capability)")
            return
        }
    }
}

// MARK: - Transport: capability classification

@Suite("DDC transport — capability classification")
struct DDCCapabilityTests {
    private func transport(_ provider: FakeBusProvider) -> IOAVServiceDDCTransport {
        IOAVServiceDDCTransport(provider: provider, store: InMemoryDDCSnapshotStore(), timing: .immediate)
    }

    @Test("supported when the panel answers get-VCP 0x16")
    func supported() async {
        let id = DisplayIdentity.fixture()
        let bus = FakeI2CBus(native: [0x16: (75, 100)])
        let provider = FakeBusProvider(); provider.install(bus, for: id)
        if case .supported = await transport(provider).probeRGBGainSupport(for: id) {} else {
            Issue.record("expected .supported")
        }
    }

    @Test("unsupported(buttonlessAppleDisplay) when no external AV service resolves")
    func noBus() async {
        let id = DisplayIdentity.fixture()
        let provider = FakeBusProvider()   // no bus installed → built-in / no service
        if case .unsupported(reason: .buttonlessAppleDisplay) = await transport(provider).probeRGBGainSupport(for: id) {} else {
            Issue.record("expected .unsupported(buttonlessAppleDisplay)")
        }
    }

    @Test("unknown(privateSymbolUnavailable) when the IOAVService symbols are missing")
    func symbolsUnavailable() async {
        let id = DisplayIdentity.fixture()
        let provider = FakeBusProvider(); provider.setAvailable(false)
        if case .unknown(reason: .privateSymbolUnavailable) = await transport(provider).probeRGBGainSupport(for: id) {} else {
            Issue.record("expected .unknown(privateSymbolUnavailable)")
        }
    }
}

// MARK: - Snapshot store

@Suite("DDC snapshot store")
struct DDCSnapshotStoreTests {
    @Test("in-memory: native + dirty round-trip, native survives the dirty toggle")
    func inMemoryRoundTrip() async {
        let store = InMemoryDDCSnapshotStore()
        let key = "display-A"
        await store.saveNative(
            DDCNativeState(red: .init(current: 90, max: 100), green: .init(current: 85, max: 100), blue: .init(current: 80, max: 100)),
            for: key
        )
        await store.setDirty(true, for: key)
        #expect(await store.dirtyKeys() == [key])
        #expect(await store.snapshot(for: key)?.native?.green.current == 85)

        await store.setDirty(false, for: key)
        #expect(await store.dirtyKeys().isEmpty)
        #expect(await store.snapshot(for: key)?.native?.blue.current == 80)   // native retained
    }

    @Test("file store persists native + dirty across instances")
    func filePersistsAcrossInstances() async {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ddc-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let key = "display-B"

        let first = FileDDCSnapshotStore(url: url)
        await first.saveNative(
            DDCNativeState(red: .init(current: 50, max: 100), green: .init(current: 50, max: 100), blue: .init(current: 50, max: 100)),
            for: key
        )
        await first.setDirty(true, for: key)

        let second = FileDDCSnapshotStore(url: url)
        #expect(await second.dirtyKeys() == [key])
        #expect(await second.snapshot(for: key)?.native?.red.current == 50)
    }
}
