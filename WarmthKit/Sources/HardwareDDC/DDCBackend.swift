import Foundation
import WarmthCore
import Logging

// MARK: - DDCTransport (swappable protocol)

/// The DDC/CI transaction surface, behind a protocol so the real IOAVService transport and a test
/// double are interchangeable. All methods are async because the real implementation serializes
/// transactions on an actor and sleeps between them.
public protocol DDCTransport: Sendable {
    /// Apply per-channel RGB gain by scaling the display's snapshotted NATIVE gain by `gain`
    /// (red≈1, blue<green<1 for warmer), then verifying by read-back. Throws on failure so the
    /// engine can fall back to overlay and surface a non-fatal error.
    func writeRGBGain(_ gain: RGBGain, to identity: DisplayIdentity) async throws
    /// Restore the display's snapshotted native gain (and native preset). Best-effort: a missing
    /// snapshot or absent service is a clean no-op, never a throw.
    func restoreNativeGain(for identity: DisplayIdentity) async throws
    /// Probe whether this display exposes the RGB-gain VCP codes (read VCP 0x16). Returns a typed
    /// capability — `.unknown(.privateSymbolUnavailable)` when the private symbols are missing,
    /// `.unsupported(.buttonlessAppleDisplay)` when there is no external AV service.
    func probeRGBGainSupport(for identity: DisplayIdentity) async -> Capability<DDCColorCaps>
}

// MARK: - DDCError

public enum DDCError: Error, Sendable, Equatable {
    /// The private IOAVService symbols could not be resolved on this OS build (kill-switch path).
    case privateSymbolUnavailable
    /// No external AV service for this display (built-in panel, HDMI-no-service, or unplugged).
    case busUnavailable
    /// Could not read the display's native gain — refuse to warm without a restore baseline.
    case nativeReadFailed
    /// A set-VCP write did not verify by read-back after all retries.
    case verifyMismatch(code: UInt8, wrote: UInt16)
}

// MARK: - DDCBackend

/// The hardware DDC layer (`IOAVServiceWriteI2C` VCP gain). Opt-in PER display; not a default in
/// v1.0. All the dangerous machinery — native-state snapshot, write-then-read verify,
/// rate-limit/backoff, serialized transactions, restore, and launch-time stale-state recovery —
/// lives in the `DDCTransport`. The backend is the thin `WarmthBackend` adapter the
/// engine drives behind `LayerResolver`.
public struct DDCBackend: WarmthBackend {
    public let method: DisplayMethod = .hardware

    private let transport: any DDCTransport

    public init(transport: any DDCTransport) {
        self.transport = transport
    }

    public func classify(_ identity: DisplayIdentity) async -> Capability<Void> {
        switch await transport.probeRGBGainSupport(for: identity) {
        case .supported:                 return .supported(())
        case let .unsupported(reason):   return .unsupported(reason: reason)
        case let .unknown(reason):       return .unknown(reason: reason)
        }
    }

    public func apply(_ kelvin: Kelvin, to identity: DisplayIdentity) async throws {
        // The Kelvin→RGB gain (red anchored ≈1.0, cooler channels attenuated) becomes the
        // per-channel multiplier the transport applies relative to the panel's NATIVE gain, so a
        // 6500K (identity) target restores native and warmer targets pull blue/green down.
        try await transport.writeRGBGain(rgbGain(for: kelvin), to: identity)
    }

    public func reset(_ identity: DisplayIdentity) async throws {
        try await transport.restoreNativeGain(for: identity)
    }
}
