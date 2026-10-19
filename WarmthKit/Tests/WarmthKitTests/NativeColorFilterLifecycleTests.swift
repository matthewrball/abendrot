import CInterop
import Darwin
import Foundation
import Testing
@testable import WarmthKitPrivate

@Suite("Native matrix lease recovery")
struct NativeColorFilterLifecycleTests {
    private final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let uuid = UUID()
        var mapping: [UUID: UInt32] = [:]
        var copies = true
        var writesSucceed = true
        var writes: [(UInt32, UUID, [Float])] = []
        var dirtyAtWrite = false
        var identity: [Float] = [1, 0, 0, 0, 1, 0, 0, 0, 1]
        var native: MatrixNativeAccess {
            MatrixNativeAccess(display: { self.mapping[$0] }, copyBaseline: { output in
                guard self.copies else { return false }
                output = self.identity
                return true
            }, apply: { id, uuid, matrix in
                self.dirtyAtWrite = (try? self.read().displays.contains(uuid)) == true
                self.writes.append((id, uuid, matrix))
                return self.writesSucceed
            })
        }
        func read() throws -> MatrixJournal {
            try JSONDecoder().decode(MatrixJournal.self, from: Data(contentsOf: directory.appendingPathComponent("lease.json")))
        }
        func store() throws -> MatrixLeaseStore { try MatrixLeaseStore(directory: directory, native: native) }
        deinit { try? FileManager.default.removeItem(at: directory) }
    }

    @Test("partial setter failure retains a durable dirty UUID and recovery restores it")
    func dirtyBeforeMutation() throws {
        let f = Fixture()
        f.mapping[f.uuid] = 1
        let store = try f.store()
        try store.lock(timeout: 0.1)
        defer { store.unlock() }
        let generation = UUID()
        try store.begin(generation)
        f.writesSucceed = false
        #expect(throws: (any Error).self) { try store.apply(uuid: f.uuid, gains: [1, 0.5, 0]) }
        #expect(f.dirtyAtWrite)
        #expect(try f.read().displays == [f.uuid])
        #expect(try store.recoveryState(expectedGeneration: generation) == .pending([f.uuid]))
        f.writesSucceed = true
        try store.recover(expectedGeneration: generation)
        #expect(f.writes.last?.2 == f.identity)
        #expect(try f.read().displays.isEmpty)
        #expect(try store.recoveryState(expectedGeneration: generation) == .restored)
    }

    @Test("failed OS filter copy never guesses identity, including during recovery")
    func baselineFailure() throws {
        let f = Fixture()
        f.mapping[f.uuid] = 1
        let store = try f.store()
        try store.begin(UUID())
        f.copies = false
        #expect(throws: (any Error).self) { try store.apply(uuid: f.uuid, gains: [1, 0.5, 0]) }
        #expect(f.writes.isEmpty)
        f.copies = true
        try store.apply(uuid: f.uuid, gains: [1, 0.5, 0])
        f.copies = false
        #expect(throws: (any Error).self) { try store.recover(expectedGeneration: nil) }
        #expect(f.writes.count == 1)
        #expect(try f.read().displays == [f.uuid])
    }

    @Test("disconnected UUID stays dirty and reconnect resolves its new ID")
    func stableUUIDRecovery() throws {
        let f = Fixture()
        f.mapping[f.uuid] = 1
        let store = try f.store()
        try store.begin(UUID())
        try store.apply(uuid: f.uuid, gains: [1, 0.5, 0])
        f.mapping = [UUID(): 1]
        try store.recover(expectedGeneration: nil)
        #expect(f.writes.count == 1)
        #expect(try f.read().displays == [f.uuid])
        f.mapping[f.uuid] = 7
        try store.recover(expectedGeneration: nil)
        #expect(f.writes.last?.0 == 7)
        #expect(f.writes.last?.1 == f.uuid)
        #expect(try f.read().displays.isEmpty)
    }

    @Test("old cleanup cannot restore or erase a newer lease")
    func staleGeneration() throws {
        let f = Fixture()
        f.mapping[f.uuid] = 1
        let store = try f.store()
        let current = UUID()
        try store.begin(current)
        try store.apply(uuid: f.uuid, gains: [1, 0.5, 0])
        try store.recover(expectedGeneration: UUID())
        #expect(f.writes.count == 1)
        #expect(try f.read().generation == current)
        #expect(try f.read().displays == [f.uuid])
    }

    @Test("journal write failure never permits an unjournaled mutation on retry")
    func journalWriteFailure() throws {
        let f = Fixture()
        f.mapping[f.uuid] = 1
        let store = try f.store()
        try store.begin(UUID())
        let path = f.directory.appendingPathComponent("lease.json")
        try FileManager.default.removeItem(at: path)
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: false)
        for _ in 0..<2 {
            #expect(throws: (any Error).self) { try store.apply(uuid: f.uuid, gains: [1, 0.5, 0]) }
        }
        #expect(f.writes.isEmpty)
    }

    @Test("the OS baseline is composed by columns and restored unchanged")
    func existingSystemFilter() throws {
        let f = Fixture()
        f.mapping[f.uuid] = 1
        f.identity = [0.5, 0.25, 0.125, 0.125, 0.5, 0.25, 0.25, 0.125, 0.5]
        let store = try f.store()
        try store.begin(UUID())
        try store.apply(uuid: f.uuid, gains: [1, 0.5, 0])
        #expect(f.writes.last?.2 == [0.5, 0.125, 0, 0.125, 0.25, 0, 0.25, 0.0625, 0])
        try store.restore(uuid: f.uuid)
        #expect(f.writes.last?.2 == f.identity)
    }

    @Test("malformed journals fail closed without native calls")
    func corruptJournal() throws {
        let f = Fixture()
        let store = try f.store()
        try Data("{\"version\":1,\"generation\":\"broken\",\"displays\":[]}".utf8)
            .write(to: f.directory.appendingPathComponent("lease.json"))
        #expect(throws: (any Error).self) { try store.recover(expectedGeneration: nil) }
        #expect(f.writes.isEmpty)
    }

    @Test("persistent lock excludes a second owner and releases without replacing its inode")
    func lockExclusion() throws {
        let f = Fixture()
        let first = try f.store()
        let second = try f.store()
        let lockPath = f.directory.appendingPathComponent("lease.lock").path
        var before = stat()
        #expect(lstat(lockPath, &before) == 0)
        try first.lock(timeout: 0.1)
        #expect(throws: (any Error).self) { try second.lock(timeout: 0.02) }
        first.unlock()
        try second.lock(timeout: 0.1)
        second.unlock()
        var after = stat()
        #expect(lstat(lockPath, &after) == 0)
        #expect(before.st_ino == after.st_ino)
    }

    @Test("wire validates schema, operation, sequential ID, generation and acknowledgments")
    func strictWire() throws {
        let generation = UUID()
        let request = MatrixRequest(id: 1, generation: generation, operation: "apply", uuid: UUID(), gains: [1, 0.5, 0])
        let decoded = try MatrixRequest.decode(JSONEncoder().encode(request))
        try decoded.validate(expectedID: 1, generation: generation)
        #expect(throws: (any Error).self) { try decoded.validate(expectedID: 2, generation: generation) }
        #expect(throws: (any Error).self) { try decoded.validate(expectedID: 1, generation: UUID()) }
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        object["extra"] = true
        #expect(throws: (any Error).self) { try MatrixRequest.decode(JSONSerialization.data(withJSONObject: object)) }
        let pending = [UUID()]
        let ready = try MatrixReply.decode(JSONEncoder().encode(MatrixReply(id: 0, generation: generation, ok: true,
                                                                            pendingDisplayUUIDs: pending)))
        try ready.validate(expectedID: 0, generation: generation)
        #expect(ready.pendingDisplayUUIDs == pending)
        #expect(throws: (any Error).self) {
            try MatrixReply(id: 0, generation: generation, ok: true).validate(expectedID: 0, generation: generation)
        }
        let reply = try MatrixReply.decode(JSONEncoder().encode(MatrixReply(id: 1, generation: generation, ok: true, pendingDisplayUUIDs: [])))
        try reply.validate(expectedID: 1, generation: generation)
        #expect(throws: (any Error).self) { try reply.validate(expectedID: 2, generation: generation) }
        #expect(throws: (any Error).self) { try reply.validate(expectedID: 1, generation: UUID()) }
        #expect(throws: (any Error).self) {
            try MatrixReply(id: 1, generation: generation, ok: false).validate(expectedID: 1, generation: generation)
        }
    }

    @Test("bounded wire rejects truncated and oversized lines")
    func boundedWire() throws {
        for bytes in [Data("{".utf8), Data(repeating: 65, count: 4096)] {
            let pipe = Pipe()
            try pipe.fileHandleForWriting.write(contentsOf: bytes)
            try pipe.fileHandleForWriting.close()
            #expect(throws: (any Error).self) { try MatrixWire.read(from: pipe.fileHandleForReading.fileDescriptor, timeout: 0.1) }
        }
    }
}

@Suite("Native matrix composition")
struct NativeMatrixCompositionTests {
    @Test("identity baseline and unit gains remain identity")
    func identity() {
        var baseline: [Float] = [1, 0, 0, 0, 1, 0, 0, 0, 1]
        var result = [Float](repeating: -99, count: 9)
        #expect(WKComposeNativeColorMatrix(&baseline, 1, 1, 1, &result))
        #expect(result == baseline)
    }

    @Test("non-diagonal baseline multiplies input channel columns")
    func columns() {
        var baseline: [Float] = [1, 2, 3, 4, 5, 6, 7, 8, 9]
        var result = [Float](repeating: -99, count: 9)
        #expect(WKComposeNativeColorMatrix(&baseline, 1, 0.5, 0, &result))
        #expect(result == [1, 1, 0, 4, 2.5, 0, 7, 4, 0])
    }

    @Test("input and output may alias")
    func alias() {
        var matrix: [Float] = [1, 2, 3, 4, 5, 6, 7, 8, 9]
        let success = matrix.withUnsafeMutableBufferPointer { buffer in
            WKComposeNativeColorMatrix(buffer.baseAddress, 1, 0.5, 0, buffer.baseAddress)
        }
        #expect(success)
        #expect(matrix == [1, 1, 0, 4, 2.5, 0, 7, 4, 0])
    }

    @Test("invalid coefficients and gains leave output untouched")
    func invalid() {
        for (coefficient, gain): (Float, Float) in [(Float.nan, 1), (17, 1), (-17, 1), (1, Float.nan), (1, -.infinity), (1, -0.1), (1, 1.1)] {
            var baseline: [Float] = [coefficient, 0, 0, 0, 1, 0, 0, 0, 1]
            let untouched = [Float](repeating: -99, count: 9)
            var result = untouched
            #expect(!WKComposeNativeColorMatrix(&baseline, gain, 1, 1, &result))
            #expect(result == untouched)
        }
    }
}

private actor MatrixFailureGate {
    private(set) var entered = false
    private(set) var completed = false
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?
    func callback() async {
        entered = true
        if released { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func markCompleted() { completed = true }
    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

@Suite("Native matrix controller ordering")
struct NativeMatrixControllerTests {
    @Test("startup failure awaits the unknown recovery notification before throwing")
    func awaitedStartupFailure() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let gate = MatrixFailureGate()
        let controller = NativeColorFilterController(executable: directory.appendingPathComponent("missing-helper"),
                                                     directory: directory, onFailure: { state in
            #expect(state == .unknown)
            await gate.callback()
        })
        let launch = Task {
            do { try await controller.start(); return false }
            catch { await gate.markCompleted(); return true }
        }
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        while !(await gate.entered), ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await gate.entered)
        #expect(await controller.latestRecoveryState == .unknown)
        #expect(!(await gate.completed))
        await gate.release()
        #expect(await launch.value)
    }

    @Test("reset retries a dead helper's pending journal and cannot report success")
    func pendingResetAfterDeath() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let uuid = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        let marker = directory.appendingPathComponent("launches")
        let helper = directory.appendingPathComponent("fake-helper")
        // The all-zero UUID has no hardware target; emergency recovery only retains its journal.
        let script = #"""
        #!/bin/sh
        printf x >> "\#(marker.path)"
        printf '{"version":1,"generation":"%s","displays":["\#(uuid.uuidString)"]}' "$3" > "\#(directory.path)/lease.json"
        printf '{"version":1,"id":0,"generation":"%s","ok":true,"pendingDisplayUUIDs":["\#(uuid.uuidString)"]}\n' "$3"
        exit 1
        """#
        try Data(script.utf8).write(to: helper)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        let gate = MatrixFailureGate()
        let controller = NativeColorFilterController(executable: helper, directory: directory, onFailure: { state in
            #expect(state == .pending([uuid]))
            await gate.callback()
        })
        try await controller.start()
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        while !(await gate.entered), ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await gate.entered)
        await gate.release()
        do {
            try await controller.reset(displayUUID: uuid)
            Issue.record("Reset falsely succeeded with an unresolved native journal")
        } catch { }
        #expect(await controller.latestRecoveryState == .pending([uuid]))
        #expect(try Data(contentsOf: marker).count >= 2)
    }

    @Test("an unrelated retained UUID does not block a healthy target's apply or reset")
    func unrelatedPendingTarget() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let unrelated = UUID()
        let target = UUID()
        let helper = directory.appendingPathComponent("fake-helper")
        // Protocol-only fake: no native API or physical-display writes are available to it.
        let script = #"""
        #!/bin/sh
        printf '{"version":1,"id":0,"generation":"%s","ok":true,"pendingDisplayUUIDs":["\#(unrelated.uuidString)"]}\n' "$3"
        while IFS= read -r request; do
            id=$(printf '%s' "$request" | /usr/bin/sed -n 's/.*"id":\([0-9]*\).*/\1/p')
            case "$request" in
                *apply*) pending='"\#(unrelated.uuidString)","\#(target.uuidString)"';;
                *) pending='"\#(unrelated.uuidString)"';;
            esac
            printf '{"version":1,"id":%s,"generation":"%s","ok":true,"pendingDisplayUUIDs":[%s]}\n' "$id" "$3" "$pending"
            case "$request" in *shutdown*) exit 0 ;; esac
        done
        """#
        try Data(script.utf8).write(to: helper)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        let controller = NativeColorFilterController(executable: helper, directory: directory)
        try await controller.start()
        #expect(await controller.latestRecoveryState == .pending([unrelated]))
        try await controller.apply(displayUUID: target, red: 1, green: 0.5, blue: 0)
        #expect(await controller.latestRecoveryState == .pending([unrelated]))
        try await controller.reset(displayUUID: target)
        #expect(await controller.latestRecoveryState == .pending([unrelated]))
        do {
            try await controller.shutdown()
            Issue.record("Shutdown falsely confirmed all targets restored")
        } catch { }
    }

    @Test("failure notification completes before another helper can report success")
    func delayedFailureNotification() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let marker = directory.appendingPathComponent("launches")
        let helper = directory.appendingPathComponent("fake-helper")
        // This fake only speaks the private pipe protocol; it has no display or native API access.
        let script = #"""
        #!/bin/sh
        printf x >> "\#(marker.path)"
        count=$(/usr/bin/wc -c < "\#(marker.path)")
        printf '{"version":1,"id":0,"generation":"%s","ok":true,"pendingDisplayUUIDs":[]}\n' "$3"
        if [ "$count" -eq 1 ]; then exit 1; fi
        while IFS= read -r request; do
            id=$(printf '%s' "$request" | /usr/bin/sed -n 's/.*"id":\([0-9]*\).*/\1/p')
            printf '{"version":1,"id":%s,"generation":"%s","ok":true,"pendingDisplayUUIDs":[]}\n' "$id" "$3"
            case "$request" in *shutdown*) exit 0 ;; esac
        done
        """#
        try Data(script.utf8).write(to: helper)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        let gate = MatrixFailureGate()
        let controller = NativeColorFilterController(executable: helper, directory: directory,
                                                     onFailure: { _ in await gate.callback() })
        try await controller.start()
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        while !(await gate.entered), ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await gate.entered)
        let nextStart = Task { try await controller.start() }
        try await Task.sleep(for: .milliseconds(50))
        #expect(try Data(contentsOf: marker).count == 1)
        await gate.release()
        try await nextStart.value
        #expect(try Data(contentsOf: marker).count == 2)
        try await controller.shutdown()
    }
}
