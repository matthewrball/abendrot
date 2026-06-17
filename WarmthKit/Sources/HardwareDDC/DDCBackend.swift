import Foundation
import WarmthCore
import CInterop
import Logging

// MARK: - DDCTransport (swappable protocol)

/// The low-level DDC/CI transaction surface, behind a protocol so the real IOAVService
/// implementation and a test double are interchangeable.
public protocol DDCTransport: Sendable {
    /// Write VCP RGB-gain values for a display. Throws on failure.
    func writeRGBGain(_ gain: RGBGain, to identity: DisplayIdentity) async throws
    /// Restore the display's snapshotted native gain.
    func restoreNativeGain(for identity: DisplayIdentity) async throws
    /// Probe whether this display exposes the RGB-gain VCP codes.
    func probeRGBGainSupport(for identity: DisplayIdentity) async -> Capability<DDCColorCaps>
}

// MARK: - DDCError

public enum DDCError: Error, Sendable {
    case notYetImplemented
    case privateSymbolUnavailable
    case probeFailed
    case verifyMismatch
}

// MARK: - IOAVServiceDDCTransport (stub)

/// The real transport will resolve IOAVServiceWriteI2C / IOAVServiceReadI2C at runtime via
/// dlsym (declared in CInterop) and run write-then-read verification. Stubbed for now.
public struct IOAVServiceDDCTransport: DDCTransport {
    private let logger = Logger(label: "com.abendrot.WarmthKit.DDCTransport")

    public init() {}

    public func writeRGBGain(_ gain: RGBGain, to identity: DisplayIdentity) async throws {
        // TODO(milestone): resolve IOAVServiceWriteI2C via dlsym (CInterop), build the VCP
        // 0x16/0x18/0x1A gain transactions, write-then-read verify, rate-limit/backoff.
        throw DDCError.notYetImplemented
    }

    public func restoreNativeGain(for identity: DisplayIdentity) async throws {
        // TODO(milestone): restore from the persisted EDID native-state snapshot.
        throw DDCError.notYetImplemented
    }

    public func probeRGBGainSupport(for identity: DisplayIdentity) async -> Capability<DDCColorCaps> {
        // TODO(milestone): VCP 0x16 read to detect RGB-gain capability.
        .unknown(reason: .notYetProbed)
    }
}

// MARK: - DDCBackend

/// The hardware DDC layer (`IOAVServiceWriteI2C` VCP gain). Opt-in PER display; not a default
/// in v1.0. Requires EDID snapshot, per-display transaction queue, write-then-read verify, and
/// launch-time stale-state recovery before it may even be offered (§21‑E3).
public struct DDCBackend: WarmthBackend {
    public let method: DisplayMethod = .hardware

    private let transport: any DDCTransport
    private let warmestPoint: Kelvin

    public init(transport: any DDCTransport = IOAVServiceDDCTransport(), warmestPoint: Kelvin = Kelvin(2700)) {
        self.transport = transport
        self.warmestPoint = warmestPoint
    }

    public func classify(_ identity: DisplayIdentity) async -> Capability<Void> {
        // Surface the typed "not yet probed" state rather than a silent nil.
        switch await transport.probeRGBGainSupport(for: identity) {
        case .supported:                 return .supported(())
        case let .unsupported(reason):   return .unsupported(reason: reason)
        case let .unknown(reason):       return .unknown(reason: reason)
        }
    }

    public func apply(_ kelvin: Kelvin, to identity: DisplayIdentity) async throws {
        let gain = rgbGain(for: kelvin)
        try await transport.writeRGBGain(gain, to: identity)
    }

    public func reset(_ identity: DisplayIdentity) async throws {
        try await transport.restoreNativeGain(for: identity)
    }
}
