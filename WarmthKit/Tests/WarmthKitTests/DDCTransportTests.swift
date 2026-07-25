import Darwin
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

    @Test("malformed gain replies above the reported maximum are never snapshotted or written")
    func rejectsMalformedNativeGain() async {
        let id = DisplayIdentity.fixture()
        let bus = FakeI2CBus(native: [
            0x16: (101, 100), 0x18: (100, 100), 0x1A: (100, 100),
        ])
        let provider = FakeBusProvider(); provider.install(bus, for: id)
        let store = InMemoryDDCSnapshotStore()
        let ddc = transport(provider, store)

        await #expect(throws: DDCError.nativeReadFailed) {
            try await ddc.writeRGBGain(rgbGain(for: Kelvin(3000)), to: id)
        }
        #expect(await store.snapshot(for: id.persistentKey) == nil)
    }

    @Test("invalid persisted native gains are not restored to hardware")
    func rejectsInvalidPersistedGain() async {
        let id = DisplayIdentity.fixture()
        let bus = FakeI2CBus(native: [
            0x16: (100, 100), 0x18: (100, 100), 0x1A: (100, 100),
        ])
        let provider = FakeBusProvider(); provider.install(bus, for: id)
        let store = InMemoryDDCSnapshotStore()
        await store.preseed(
            DDCDisplaySnapshot(
                native: DDCNativeState(
                    red: .init(current: .max, max: 100),
                    green: .init(current: 100, max: 100),
                    blue: .init(current: 100, max: 100)
                ),
                isDirty: true
            ),
            for: id.persistentKey
        )
        let ddc = transport(provider, store)

        await #expect(throws: DDCError.nativeReadFailed) {
            try await ddc.restoreNativeGain(for: id)
        }
        #expect(bus.totalWrites == 0)
    }

    @Test("corrupt file snapshot store fails closed before any DDC bus write")
    func corruptFileStorePreventsBusWrites() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ddc-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("snapshots.json")
        try Data("not json".utf8).write(to: url)

        let id = DisplayIdentity.fixture()
        let bus = FakeI2CBus(native: [
            0x16: (100, 100), 0x18: (100, 100), 0x1A: (100, 100),
        ])
        let provider = FakeBusProvider(); provider.install(bus, for: id)
        let ddc = IOAVServiceDDCTransport(
            provider: provider,
            store: FileDDCSnapshotStore(url: url),
            timing: .immediate
        )

        await #expect(throws: DDCError.self) {
            try await ddc.writeRGBGain(rgbGain(for: Kelvin(3000)), to: id)
        }
        #expect(bus.totalWrites == 0)
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
    func filePersistsAcrossInstances() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ddc-test-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("snapshots.json")
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o755]
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = "display-B"

        let first = FileDDCSnapshotStore(url: url)
        try await first.saveNative(
            DDCNativeState(red: .init(current: 50, max: 100), green: .init(current: 50, max: 100), blue: .init(current: 50, max: 100)),
            for: key
        )
        try await first.setDirty(true, for: key)

        let second = FileDDCSnapshotStore(url: url)
        #expect(try await second.dirtyKeys() == [key])
        #expect(try await second.snapshot(for: key)?.native?.red.current == 50)
        #expect(posixMode(of: directory) == 0o700)
        #expect(posixMode(of: url) == 0o600)
    }

    @Test("file store refuses a snapshot symlink without modifying its referent")
    func fileStoreRejectsSnapshotSymlink() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ddc-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let referent = directory.appendingPathComponent("referent.json")
        let url = directory.appendingPathComponent("snapshots.json")
        try Data("keep".utf8).write(to: referent)
        try FileManager.default.createSymbolicLink(atPath: url.path, withDestinationPath: referent.path)

        let store = FileDDCSnapshotStore(url: url)
        await #expect(throws: Error.self) {
            try await store.saveNative(
                DDCNativeState(red: .init(current: 50, max: 100), green: .init(current: 50, max: 100), blue: .init(current: 50, max: 100)),
                for: "display-C"
            )
        }

        #expect(try String(contentsOf: referent, encoding: .utf8) == "keep")
        #expect(isSymlink(url))
        try FileManager.default.removeItem(at: url)
        #expect(try await store.snapshot(for: "display-C") == nil)
    }

    @Test("file store refuses a final directory symlink")
    func fileStoreRejectsDirectorySymlink() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ddc-test-\(UUID().uuidString)", isDirectory: true)
        let realDirectory = root.appendingPathComponent("real", isDirectory: true)
        let linkDirectory = root.appendingPathComponent("link", isDirectory: true)
        try FileManager.default.createDirectory(at: realDirectory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: linkDirectory.path, withDestinationPath: realDirectory.path)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = FileDDCSnapshotStore(url: linkDirectory.appendingPathComponent("snapshots.json"))
        await #expect(throws: Error.self) {
            try await store.saveNative(
                DDCNativeState(red: .init(current: 50, max: 100), green: .init(current: 50, max: 100), blue: .init(current: 50, max: 100)),
                for: "display-D"
            )
        }

        #expect(!FileManager.default.fileExists(atPath: realDirectory.appendingPathComponent("snapshots.json").path))
        try FileManager.default.removeItem(at: linkDirectory)
        #expect(try await store.snapshot(for: "display-D") == nil)
    }
}

private func posixMode(of url: URL) -> Int {
    var info = stat()
    guard lstat(url.path, &info) == 0 else { return -1 }
    return Int(info.st_mode & 0o777)
}

private func isSymlink(_ url: URL) -> Bool {
    var info = stat()
    guard lstat(url.path, &info) == 0 else { return false }
    return (info.st_mode & S_IFMT) == S_IFLNK
}
