import Foundation
import WarmthCore
import Logging

// MARK: - Snapshot value types

/// One channel's native VCP gain: the value the panel shipped with (`current`) and the panel's
/// reported maximum (`max`, per-monitor — never assume 100).
public struct DDCChannelGain: Codable, Equatable, Sendable {
    public var current: UInt16
    public var max: UInt16
    public init(current: UInt16, max: UInt16) {
        self.current = current
        self.max = max
    }
}

/// The native (pre-warming) hardware state of a display: per-channel RGB gain + the native colour
/// preset (VCP 0x14, if readable). Restoring this returns the panel exactly to how the user had it.
public struct DDCNativeState: Codable, Equatable, Sendable {
    public var red: DDCChannelGain
    public var green: DDCChannelGain
    public var blue: DDCChannelGain
    public var preset: UInt16?
    public init(red: DDCChannelGain, green: DDCChannelGain, blue: DDCChannelGain, preset: UInt16? = nil) {
        self.red = red
        self.green = green
        self.blue = blue
        self.preset = preset
    }
}

/// Per-display persisted state. `native` is written by the transport on first contact (and read
/// back to restore); `isDirty` is the engine's write-ahead flag — true while a warm gain is
/// applied and not yet cleanly restored, so a fresh process can recover after a crash/SIGKILL.
public struct DDCDisplaySnapshot: Codable, Equatable, Sendable {
    public var native: DDCNativeState?
    public var isDirty: Bool
    public init(native: DDCNativeState? = nil, isDirty: Bool = false) {
        self.native = native
        self.isDirty = isDirty
    }
}

// MARK: - DDCSnapshotStore

/// Persistence for the DDC native-state snapshot + dirty flag (§9). Two writers by design:
/// the **transport** owns `native` (the values to restore to); the **engine** owns `isDirty`
/// (recovery orchestration). Both go through the same actor-serialized store, keyed by
/// `DisplayIdentity.persistentKey`.
public protocol DDCSnapshotStore: Sendable {
    func snapshot(for key: String) async -> DDCDisplaySnapshot?
    /// Transport: record a display's native gains (creates the record if absent; preserves dirty).
    func saveNative(_ native: DDCNativeState, for key: String) async
    /// Engine: set/clear the write-ahead dirty flag (creates the record if absent; preserves native).
    func setDirty(_ dirty: Bool, for key: String) async
    /// Keys whose snapshot is currently dirty — the launch-time recovery work-list.
    func dirtyKeys() async -> Set<String>
}

// MARK: - InMemoryDDCSnapshotStore

/// Non-persistent store for tests and for hosts where persistence is undesirable. Also exposes a
/// `preseed` hook so a failure-injection test can simulate a prior run that crashed mid-warmth.
public actor InMemoryDDCSnapshotStore: DDCSnapshotStore {
    private var store: [String: DDCDisplaySnapshot] = [:]

    public init() {}

    public func snapshot(for key: String) -> DDCDisplaySnapshot? { store[key] }

    public func saveNative(_ native: DDCNativeState, for key: String) {
        var snapshot = store[key] ?? DDCDisplaySnapshot()
        snapshot.native = native
        store[key] = snapshot
    }

    public func setDirty(_ dirty: Bool, for key: String) {
        var snapshot = store[key] ?? DDCDisplaySnapshot()
        guard snapshot.isDirty != dirty else { return }
        snapshot.isDirty = dirty
        store[key] = snapshot
    }

    public func dirtyKeys() -> Set<String> {
        Set(store.lazy.filter { $0.value.isDirty }.map(\.key))
    }

    /// Test hook: pre-seed a snapshot (e.g. a dirty prior-run state).
    public func preseed(_ snapshot: DDCDisplaySnapshot, for key: String) {
        store[key] = snapshot
    }
}

// MARK: - FileDDCSnapshotStore

/// JSON-on-disk store under Application Support. The whole map is small (a handful of displays),
/// so each mutation rewrites it atomically. All access is actor-serialized; the in-memory `cache`
/// avoids re-reading the file on every query.
public actor FileDDCSnapshotStore: DDCSnapshotStore {
    private let url: URL
    private var cache: [String: DDCDisplaySnapshot]?
    private let logger = Logger(label: "com.abendrot.WarmthKit.DDCSnapshotStore")

    public init(url: URL? = nil) {
        self.url = url ?? Self.defaultURL()
    }

    private static func defaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base
            .appendingPathComponent("Abendrot", isDirectory: true)
            .appendingPathComponent("ddc-snapshots.json")
    }

    public func snapshot(for key: String) -> DDCDisplaySnapshot? { load()[key] }

    public func saveNative(_ native: DDCNativeState, for key: String) {
        var map = load()
        var snapshot = map[key] ?? DDCDisplaySnapshot()
        snapshot.native = native
        map[key] = snapshot
        persist(map)
    }

    public func setDirty(_ dirty: Bool, for key: String) {
        var map = load()
        var snapshot = map[key] ?? DDCDisplaySnapshot()
        guard snapshot.isDirty != dirty else { return }   // no-op write avoidance
        snapshot.isDirty = dirty
        map[key] = snapshot
        persist(map)
    }

    public func dirtyKeys() -> Set<String> {
        Set(load().lazy.filter { $0.value.isDirty }.map(\.key))
    }

    // MARK: Disk I/O (actor-isolated)

    private func load() -> [String: DDCDisplaySnapshot] {
        if let cache { return cache }
        let decoded: [String: DDCDisplaySnapshot]
        if let data = try? Data(contentsOf: url),
           let map = try? JSONDecoder().decode([String: DDCDisplaySnapshot].self, from: data) {
            decoded = map
        } else {
            decoded = [:]
        }
        cache = decoded
        return decoded
    }

    private func persist(_ map: [String: DDCDisplaySnapshot]) {
        cache = map
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(map)
            try data.write(to: url, options: .atomic)
        } catch {
            logger.error("Failed to persist DDC snapshot store: \(error.localizedDescription)")
        }
    }
}
