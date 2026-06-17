import Foundation
import CoreGraphics
@testable import WarmthCore
@testable import HardwareDDC

// MARK: - DisplayIdentity fixture

extension DisplayIdentity {
    /// Convenience identity for headless tests (§21‑E14 requests a fixture seam).
    static func fixture(
        cgUUID: UUID = UUID(),
        edid: EDIDFingerprint? = EDIDFingerprint(vendorID: 0x1234, productID: 0x5678, serial: 42, displayName: "Test Display"),
        transport: DisplayTransport = .displayPort,
        displayID: CGDirectDisplayID = 1
    ) -> DisplayIdentity {
        DisplayIdentity(cgUUID: cgUUID, edid: edid, transport: transport, currentDisplayID: displayID)
    }
}

// MARK: - FakeI2CBus

/// A tiny in-memory "monitor": models per-VCP-code (current, max), honours set-VCP writes, and
/// builds spec-correct get-VCP replies (0x50-seeded checksum) so the transport's write-then-read
/// verify loop can be exercised headlessly. Configurable to ignore sets (panel locks gain) and to
/// drop the next N reads (Apple-Silicon read flakiness). `@unchecked Sendable` + a lock: the
/// transport touches it serially; the test reads it only after awaiting.
final class FakeI2CBus: DDCBus, @unchecked Sendable {
    private let lock = NSLock()
    private var current: [UInt8: UInt16] = [:]
    private var maxValue: [UInt8: UInt16] = [:]
    private var lastGetCode: UInt8?
    private var writeCount = 0
    private var readFailuresRemaining = 0
    private var ignoreSets = false

    init(native: [UInt8: (current: UInt16, max: UInt16)]) {
        for (code, value) in native {
            current[code] = value.current
            maxValue[code] = value.max
        }
    }

    // Test configuration
    func setIgnoreSets(_ value: Bool) { lock.lock(); ignoreSets = value; lock.unlock() }
    func failNextReads(_ n: Int) { lock.lock(); readFailuresRemaining = n; lock.unlock() }
    func currentValue(_ code: UInt8) -> UInt16? { lock.lock(); defer { lock.unlock() }; return current[code] }
    var totalWrites: Int { lock.lock(); defer { lock.unlock() }; return writeCount }

    // DDCBus
    func write(_ bytes: [UInt8], offset: UInt32) -> Bool {
        lock.lock(); defer { lock.unlock() }
        writeCount += 1
        guard bytes.count >= 3 else { return false }
        if bytes[0] == 0x84, bytes[1] == 0x03, bytes.count >= 5 {           // Set VCP
            let code = bytes[2]
            let value = (UInt16(bytes[3]) << 8) | UInt16(bytes[4])
            if !ignoreSets { current[code] = min(value, maxValue[code] ?? value) }
        } else if bytes[0] == 0x82, bytes[1] == 0x01 {                      // Get VCP request
            lastGetCode = bytes[2]
        }
        return true
    }

    func read(count: Int, offset: UInt32) -> [UInt8]? {
        lock.lock(); defer { lock.unlock() }
        if readFailuresRemaining > 0 { readFailuresRemaining -= 1; return nil }
        guard let code = lastGetCode else { return nil }
        return Self.reply(code: code, current: current[code] ?? 0, max: maxValue[code] ?? 100, bufferSize: count)
    }

    /// Build a valid Get-VCP reply frame (11 bytes + optional zero padding to `bufferSize`).
    static func reply(code: UInt8, current: UInt16, max: UInt16, bufferSize: Int) -> [UInt8] {
        var frame: [UInt8] = [
            0x6E, 0x88, 0x02, 0x00, code, 0x00,
            UInt8(max >> 8), UInt8(max & 0xFF),
            UInt8(current >> 8), UInt8(current & 0xFF),
            0,
        ]
        var checksum: UInt8 = 0x50
        for byte in frame[0..<10] { checksum ^= byte }
        frame[10] = checksum
        if bufferSize > frame.count {
            frame += [UInt8](repeating: 0, count: bufferSize - frame.count)
        }
        return frame
    }
}

// MARK: - FakeBusProvider

/// A `DDCBusProvider` whose buses are installed/removed by the test (modelling plug/unplug and the
/// symbols-unavailable kill-switch path).
final class FakeBusProvider: DDCBusProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var buses: [String: any DDCBus] = [:]
    private var available = true

    init() {}

    var isAvailable: Bool { lock.lock(); defer { lock.unlock() }; return available }
    func bus(for identity: DisplayIdentity) -> (any DDCBus)? {
        lock.lock(); defer { lock.unlock() }; return buses[identity.persistentKey]
    }
    func install(_ bus: any DDCBus, for identity: DisplayIdentity) {
        lock.lock(); buses[identity.persistentKey] = bus; lock.unlock()
    }
    func remove(_ identity: DisplayIdentity) {
        lock.lock(); buses[identity.persistentKey] = nil; lock.unlock()
    }
    func setAvailable(_ value: Bool) { lock.lock(); available = value; lock.unlock() }
}

// MARK: - FaultInjectingBackend

/// A `WarmthBackend` that records every call and can be told to fail at a chosen phase. Models a
/// persistent "panel state" (`applied`) so a test can assert what was left on the display
/// (§21‑E14 harness). Used as the DDC layer in the engine recovery scenarios.
enum FaultPhase: Sendable { case beforeApply, midApply, afterApply, onReset }
enum FaultError: Error, Equatable { case injected(FaultPhase) }

actor FaultInjectingBackend: WarmthBackend {
    nonisolated let method: DisplayMethod
    private(set) var applied: [DisplayIdentity: Kelvin] = [:]
    private(set) var callLog: [String] = []
    private var faultAt: FaultPhase?

    init(method: DisplayMethod) { self.method = method }

    func setFault(_ phase: FaultPhase?) { faultAt = phase }
    func forceApplied(_ id: DisplayIdentity, _ kelvin: Kelvin) { applied[id] = kelvin }

    func classify(_ id: DisplayIdentity) async -> Capability<Void> { .supported(()) }

    func apply(_ kelvin: Kelvin, to id: DisplayIdentity) async throws {
        callLog.append("apply")
        if faultAt == .beforeApply { throw FaultError.injected(.beforeApply) }
        if faultAt == .midApply {
            // Half-written: the crux of crash-during-DDC. Panel left non-neutral, non-target.
            applied[id] = Kelvin((kelvin.value + Kelvin.neutral.value) / 2)
            throw FaultError.injected(.midApply)
        }
        applied[id] = kelvin
        if faultAt == .afterApply { throw FaultError.injected(.afterApply) }
    }

    func reset(_ id: DisplayIdentity) async throws {
        callLog.append("reset")
        if faultAt == .onReset { throw FaultError.injected(.onReset) }
        applied[id] = .neutral
    }
}
