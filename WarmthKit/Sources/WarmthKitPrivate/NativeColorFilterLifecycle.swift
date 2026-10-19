import CoreGraphics
import ColorSync
import CInterop
import Darwin
import Foundation
import WarmthCore

/// The helper is the only normal matrix writer. Its input pipe is also the parent-life lease.
/// Dispatch this mode before constructing the application's model or user interface.
public enum NativeColorFilterHelper {
    public static let argument = "--abendrot-native-color-filter-helper"

    public static func runIfRequested(arguments: [String] = CommandLine.arguments) -> Int32? {
        guard arguments.dropFirst().first == argument else { return nil }
        guard arguments.count == 4, let generation = UUID(uuidString: arguments[3]) else { return 64 }
        do {
            let store = try MatrixLeaseStore(directory: URL(fileURLWithPath: arguments[2], isDirectory: true))
            try store.lock(timeout: 5)
            defer { store.unlock() }
            try store.recover(expectedGeneration: nil)
            try store.begin(generation)
            let pending: [UUID]
            switch try store.recoveryState(expectedGeneration: generation) {
            case .pending(let displays): pending = displays
            case .restored: pending = []
            case .unknown: throw MatrixFailure.journalInvalid
            }
            try MatrixWire.write(MatrixReply(id: 0, generation: generation, ok: true, pendingDisplayUUIDs: pending), to: STDOUT_FILENO)
            defer { try? store.recover(expectedGeneration: generation) }
            var expectedID: UInt64 = 1
            while let data = try MatrixWire.read(from: STDIN_FILENO, timeout: nil) {
                let request = try MatrixRequest.decode(data)
                try request.validate(expectedID: expectedID, generation: generation)
                expectedID += 1
                do {
                    switch request.operation {
                    case "apply":
                        guard let uuid = request.uuid, let gains = request.gains else { throw MatrixFailure.invalidProtocol }
                        try store.apply(uuid: uuid, gains: gains)
                    case "reset":
                        guard let uuid = request.uuid else { throw MatrixFailure.invalidProtocol }
                        try store.restore(uuid: uuid)
                    case "shutdown":
                        try store.recover(expectedGeneration: generation)
                    default: throw MatrixFailure.invalidProtocol
                    }
                    let remaining: [UUID]
                    switch try store.recoveryState(expectedGeneration: generation) {
                    case .pending(let displays): remaining = displays
                    case .restored: remaining = []
                    case .unknown: throw MatrixFailure.journalInvalid
                    }
                    try MatrixWire.write(MatrixReply(id: request.id, generation: generation, ok: true,
                                                     pendingDisplayUUIDs: remaining), to: STDOUT_FILENO)
                    if request.operation == "shutdown" { return 0 }
                } catch {
                    try MatrixWire.write(MatrixReply(id: request.id, generation: generation, ok: false), to: STDOUT_FILENO)
                }
            }
            // EOF includes a parent SIGKILL. Restore while the exclusive lease is still held.
            try store.recover(expectedGeneration: generation)
            return 0
        } catch { return 1 }
    }
}

/// Durable recovery outcome. `restored` means scoped baseline writes were accepted and journaled;
/// it is not an optical readback. Pending or unknown must not be reported as confirmed neutral.
public enum NativeColorFilterRecoveryState: Sendable, Equatable {
    case restored
    case pending([UUID])
    case unknown
}

/// One controller per app process. Failures finish notifying the owner before a new lease starts.
public actor NativeColorFilterController {
    public static let shared = NativeColorFilterController()
    public typealias FailureHandler = @Sendable (NativeColorFilterRecoveryState) async -> Void
    private let directory: URL
    private let executable: URL
    private var onFailure: FailureHandler
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var generation: UUID?
    private var nextID: UInt64 = 1
    private var activeDisplays: Set<UUID> = []
    private var stopping = false
    public private(set) var latestRecoveryState: NativeColorFilterRecoveryState = .unknown
    private var failureNotification: (id: UUID, task: Task<Void, Never>)?

    public init(executable: URL = URL(fileURLWithPath: CommandLine.arguments[0]),
                directory: URL? = nil, onFailure: @escaping FailureHandler = { _ in }) {
        self.executable = executable
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Abendrot/NativeColorFilter", isDirectory: true)
        self.onFailure = onFailure
    }

    public func setFailureHandler(_ handler: @escaping FailureHandler) { onFailure = handler }

    /// Call at direct-distribution startup even when warmth or private APIs are disabled.
    /// Starting the helper recovers a stale journal before acknowledging readiness.
    public func start() async throws {
        await awaitFailureNotification()
        if process != nil { return }
        latestRecoveryState = .unknown
        let lease = UUID()
        let child = Process()
        let commands = Pipe()
        let replies = Pipe()
        for handle in [commands.fileHandleForReading, commands.fileHandleForWriting,
                       replies.fileHandleForReading, replies.fileHandleForWriting] {
            guard fcntl(handle.fileDescriptor, F_SETFD, FD_CLOEXEC) == 0 else { throw POSIXError(.EIO) }
        }
        child.executableURL = executable
        child.arguments = [NativeColorFilterHelper.argument, directory.path, lease.uuidString]
        child.standardInput = commands
        child.standardOutput = replies
        child.standardError = FileHandle.nullDevice
        child.terminationHandler = { [weak self] terminated in
            let status = terminated.terminationStatus
            Task { await self?.childExited(generation: lease, status: status) }
        }
        do { try child.run() }
        catch {
            failAndRecover()
            await awaitFailureNotification()
            throw error
        }
        // Close the parent's copies of child-only endpoints. All surviving endpoints are CLOEXEC.
        try? commands.fileHandleForReading.close()
        try? replies.fileHandleForWriting.close()
        process = child
        input = commands.fileHandleForWriting
        output = replies.fileHandleForReading
        generation = lease
        nextID = 1
        stopping = false
        do {
            let reply = try readReply(id: 0, generation: lease, timeout: 7)
            let pending = reply.pendingDisplayUUIDs ?? []
            latestRecoveryState = pending.isEmpty ? .restored : .pending(pending)
        } catch {
            failAndRecover()
            await awaitFailureNotification()
            throw error
        }
    }

    public func apply(displayUUID: UUID, red: Float, green: Float, blue: Float) async throws {
        guard [red, green, blue].allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
            throw MatrixFailure.invalidProtocol
        }
        try await start()
        guard restorationAllows(displayUUID) else {
            failAndRecover()
            await awaitFailureNotification()
            throw MatrixFailure.nativeUnavailable
        }
        try await send(operation: "apply", uuid: displayUUID, gains: [red, green, blue])
    }

    public func reset(displayUUID: UUID) async throws {
        await awaitFailureNotification()
        if process == nil {
            if latestRecoveryState == .restored { return }
            try await start()
        }
        try await send(operation: "reset", uuid: displayUUID)
    }

    public func shutdown() async throws {
        await awaitFailureNotification()
        if process == nil {
            if latestRecoveryState == .restored { return }
            try await start()
        }
        stopping = true
        try await send(operation: "shutdown")
        try? input?.close()
        process?.waitUntilExit()
        clearProcess()
    }

    private func send(operation: String, uuid: UUID? = nil, gains: [Float]? = nil) async throws {
        guard let generation, let input else { throw MatrixFailure.helperUnavailable }
        let id = nextID
        nextID += 1
        do {
            try MatrixWire.write(MatrixRequest(id: id, generation: generation, operation: operation,
                                               uuid: uuid, gains: gains), to: input.fileDescriptor)
            let reply = try readReply(id: id, generation: generation, timeout: 3)
            if operation == "apply", let uuid { activeDisplays.insert(uuid) }
            if operation == "reset", let uuid { activeDisplays.remove(uuid) }
            if operation == "shutdown" { activeDisplays.removeAll() }
            let remaining = (reply.pendingDisplayUUIDs ?? []).filter { !activeDisplays.contains($0) }
            latestRecoveryState = remaining.isEmpty ? .restored : .pending(remaining)
            if !restorationAllows(operation == "shutdown" ? nil : uuid) { throw MatrixFailure.nativeUnavailable }
        } catch {
            failAndRecover()
            await awaitFailureNotification()
            throw error
        }
    }

    private func restorationAllows(_ displayUUID: UUID?) -> Bool {
        switch latestRecoveryState {
        case .restored: return true
        case .pending(let displays):
            // An absent old panel remains recoverable without blocking another healthy target.
            return displayUUID.map { !displays.contains($0) } ?? false
        case .unknown: return false
        }
    }

    private func readReply(id: UInt64, generation: UUID, timeout: Double) throws -> MatrixReply {
        guard let output, let data = try MatrixWire.read(from: output.fileDescriptor, timeout: timeout) else {
            throw MatrixFailure.helperUnavailable
        }
        let reply = try MatrixReply.decode(data)
        try reply.validate(expectedID: id, generation: generation)
        return reply
    }

    private func failAndRecover() {
        let lease = generation
        stopping = true
        try? input?.close()
        if let process, process.isRunning {
            kill(process.processIdentifier, SIGKILL)
            process.waitUntilExit()
        }
        clearProcess()
        // A confirmed dead child cannot race this recovery. A newer helper's lock/generation wins.
        var recovery: NativeColorFilterRecoveryState = .unknown
        if let lease, let store = try? MatrixLeaseStore(directory: directory) {
            do {
                try store.lock(timeout: 2)
                defer { store.unlock() }
                try? store.recover(expectedGeneration: lease)
                recovery = try store.recoveryState(expectedGeneration: lease)
            } catch { /* Unknown recovery is reported; retained journal is retried at startup. */ }
        }
        latestRecoveryState = recovery
        let handler = onFailure
        let outcome = recovery
        failureNotification = (UUID(), Task { await handler(outcome) })
    }

    private func awaitFailureNotification() async {
        while let notification = failureNotification {
            await notification.task.value
            if failureNotification?.id == notification.id { failureNotification = nil }
        }
    }

    private func childExited(generation lease: UUID, status: Int32) {
        guard generation == lease, !stopping else { return }
        // EOF cleanup may have succeeded; recovery is idempotent and also covers helper SIGKILL.
        _ = status
        failAndRecover()
    }

    private func clearProcess() {
        try? input?.close()
        try? output?.close()
        input = nil
        output = nil
        process = nil
        generation = nil
        activeDisplays.removeAll()
    }
}

enum MatrixFailure: Error {
    case invalidProtocol, helperUnavailable, displayUnavailable, nativeUnavailable, journalInvalid
}

struct MatrixJournal: Codable {
    let version: Int
    var generation: UUID
    var displays: [UUID]
}

final class MatrixLeaseStore {
    private let journalURL: URL
    private let lockFD: Int32
    private let native: MatrixNativeAccess
    private var journal: MatrixJournal?

    init(directory: URL, native: MatrixNativeAccess = .live) throws {
        self.native = native
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let dirFD = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard dirFD >= 0 else { throw POSIXError(.EIO) }
        defer { close(dirFD) }
        lockFD = openat(dirFD, "lease.lock", O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard lockFD >= 0 else { throw POSIXError(.EIO) }
        var info = stat()
        guard fstat(lockFD, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_uid == getuid(), info.st_nlink == 1 else {
            close(lockFD)
            throw MatrixFailure.journalInvalid
        }
        journalURL = directory.appendingPathComponent("lease.json")
    }

    deinit { close(lockFD) }

    func lock(timeout: Double) throws {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while flock(lockFD, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK || errno == EINTR else { throw POSIXError(.EIO) }
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw POSIXError(.EBUSY) }
            usleep(20_000)
        }
    }

    func unlock() { _ = flock(lockFD, LOCK_UN) }

    func begin(_ generation: UUID) throws {
        let old = try load()
        try persist(MatrixJournal(version: 1, generation: generation, displays: old?.displays ?? []))
    }

    func apply(uuid: UUID, gains: [Float]) throws {
        guard gains.count == 3, gains.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
              let display = native.display(uuid) else { throw MatrixFailure.displayUnavailable }
        var baseline = [Float](repeating: 0, count: 9)
        var matrix = baseline
        guard native.copyBaseline(&baseline),
              WKComposeNativeColorMatrix(&baseline, gains[0], gains[1], gains[2], &matrix) else {
            throw MatrixFailure.nativeUnavailable
        }
        guard var current = journal else { throw MatrixFailure.journalInvalid }
        if !current.displays.contains(uuid) {
            current.displays.append(uuid)
            // Commit in-memory ownership only after durable persistence succeeds.
            try persist(current) // Persist before any mutation, including a partial setter failure.
        }
        guard native.apply(display, uuid, matrix) else {
            throw MatrixFailure.nativeUnavailable
        }
    }

    func restore(uuid: UUID) throws {
        guard journal?.displays.contains(uuid) == true else { return }
        guard let display = native.display(uuid) else { return } // Keep disconnected displays dirty.
        var baseline = [Float](repeating: 0, count: 9)
        guard native.copyBaseline(&baseline),
              native.apply(display, uuid, baseline) else {
            throw MatrixFailure.nativeUnavailable
        }
        guard var current = journal else { throw MatrixFailure.journalInvalid }
        current.displays.removeAll { $0 == uuid }
        try persist(current)
    }

    func recover(expectedGeneration: UUID?) throws {
        journal = try load()
        guard let current = journal else { return }
        guard expectedGeneration == nil || current.generation == expectedGeneration else { return }
        var failed = false
        for uuid in current.displays {
            do { try restore(uuid: uuid) } catch { failed = true }
        }
        if failed { throw MatrixFailure.nativeUnavailable }
    }

    func recoveryState(expectedGeneration: UUID) throws -> NativeColorFilterRecoveryState {
        guard let value = try load() else { return .restored }
        guard value.generation == expectedGeneration else { return .unknown }
        return value.displays.isEmpty ? .restored : .pending(value.displays)
    }

    private func load() throws -> MatrixJournal? {
        guard let data = try SecureAtomicFileWriter.readRegularFileIfExists(from: journalURL) else { return nil }
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let object, Set(object.keys) == ["version", "generation", "displays"] else {
            throw MatrixFailure.journalInvalid
        }
        let value = try JSONDecoder().decode(MatrixJournal.self, from: data)
        guard value.version == 1, value.displays.count <= 32,
              Set(value.displays).count == value.displays.count else { throw MatrixFailure.journalInvalid }
        return value
    }

    private func persist(_ value: MatrixJournal) throws {
        try SecureAtomicFileWriter.write(JSONEncoder().encode(value), to: journalURL)
        journal = value
    }


}


/// Internal seam keeps crash-journal tests independent of actual display hardware.
struct MatrixNativeAccess {
    var display: (UUID) -> CGDirectDisplayID?
    var copyBaseline: (inout [Float]) -> Bool
    var apply: (CGDirectDisplayID, UUID, [Float]) -> Bool

    static var live: Self {
        Self(display: liveDisplay, copyBaseline: { WKCopySystemColorFilterMatrix(&$0) }, apply: { id, uuid, values in
            var matrix = values
            return WKApplyNativeColorMatrix(id, uuid.uuidString as CFString, &matrix)
        })
    }
    private static func liveDisplay(_ uuid: UUID) -> CGDirectDisplayID? {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count <= 32 else { return nil }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return nil }
        return ids.prefix(Int(count)).first { id in
            guard id != 0, CGDisplayIsActive(id) != 0, CGDisplayIsBuiltin(id) != 0,
                  CGDisplayIsInMirrorSet(id) == 0, let value = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return false }
            return CFUUIDCreateString(nil, value) as String == uuid.uuidString
        }
    }
}

struct MatrixRequest: Codable {
    var version = 1
    let id: UInt64
    let generation: UUID
    let operation: String
    let uuid: UUID?
    let gains: [Float]?

    func validate(expectedID: UInt64, generation: UUID) throws {
        guard id == expectedID, self.generation == generation else { throw MatrixFailure.invalidProtocol }
    }

    static func decode(_ data: Data) throws -> Self {
        let keys = try MatrixWire.keys(data)
        guard keys.isSubset(of: ["version", "id", "generation", "operation", "uuid", "gains"]),
              keys.isSuperset(of: ["version", "id", "generation", "operation"]) else { throw MatrixFailure.invalidProtocol }
        let request = try JSONDecoder().decode(Self.self, from: data)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard object?["version"] as? Int == 1, request.id > 0 else { throw MatrixFailure.invalidProtocol }
        switch request.operation {
        case "apply": guard request.uuid != nil, request.gains?.count == 3 else { throw MatrixFailure.invalidProtocol }
        case "reset": guard request.uuid != nil, request.gains == nil else { throw MatrixFailure.invalidProtocol }
        case "shutdown": guard request.uuid == nil, request.gains == nil else { throw MatrixFailure.invalidProtocol }
        default: throw MatrixFailure.invalidProtocol
        }
        return request
    }
}

struct MatrixReply: Codable {
    var version = 1
    let id: UInt64
    let generation: UUID
    let ok: Bool
    var pendingDisplayUUIDs: [UUID]? = nil

    func validate(expectedID: UInt64, generation: UUID) throws {
        guard id == expectedID, self.generation == generation, ok,
              pendingDisplayUUIDs != nil else { throw MatrixFailure.helperUnavailable }
    }

    static func decode(_ data: Data) throws -> Self {
        let keys = try MatrixWire.keys(data)
        guard keys == ["version", "id", "generation", "ok"] || keys == ["version", "id", "generation", "ok", "pendingDisplayUUIDs"],
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["version"] as? Int == 1 else { throw MatrixFailure.invalidProtocol }
        let reply = try JSONDecoder().decode(Self.self, from: data)
        if let pending = reply.pendingDisplayUUIDs {
            guard pending.count <= 32, Set(pending).count == pending.count else { throw MatrixFailure.invalidProtocol }
        }
        return reply
    }
}

enum MatrixWire {
    static func keys(_ data: Data) throws -> Set<String> {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw MatrixFailure.invalidProtocol }
        return Set(object.keys)
    }

    static func write<T: Encodable>(_ value: T, to fd: Int32) throws {
        var data = try JSONEncoder().encode(value)
        guard data.count < 4096 else { throw MatrixFailure.invalidProtocol }
        data.append(10)
        // A dead helper must produce EPIPE rather than terminating the app with SIGPIPE.
        _ = fcntl(fd, F_SETNOSIGPIPE, 1)
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count > 0 { offset += count }
                else if count < 0 && errno == EINTR { continue }
                else { throw MatrixFailure.helperUnavailable }
            }
        }
    }

    static func read(from fd: Int32, timeout: Double?) throws -> Data? {
        let deadline = timeout.map { ProcessInfo.processInfo.systemUptime + $0 }
        var data = Data()
        while data.count < 4096 {
            let milliseconds: Int32
            if let deadline {
                let remaining = deadline - ProcessInfo.processInfo.systemUptime
                guard remaining > 0 else { throw MatrixFailure.helperUnavailable }
                milliseconds = Int32(min(remaining * 1000, Double(Int32.max)))
            } else { milliseconds = -1 }
            var descriptor = pollfd(fd: fd, events: Int16(POLLIN | POLLHUP), revents: 0)
            let ready = poll(&descriptor, 1, milliseconds)
            if ready < 0 && errno == EINTR { continue }
            guard ready > 0 else { throw MatrixFailure.helperUnavailable }
            var byte: UInt8 = 0
            let count = Darwin.read(fd, &byte, 1)
            if count == 0 {
                guard data.isEmpty else { throw MatrixFailure.invalidProtocol }
                return nil
            }
            if count < 0 && errno == EINTR { continue }
            guard count == 1 else { throw MatrixFailure.helperUnavailable }
            if byte == 10 { return data }
            data.append(byte)
        }
        throw MatrixFailure.invalidProtocol
    }
}
