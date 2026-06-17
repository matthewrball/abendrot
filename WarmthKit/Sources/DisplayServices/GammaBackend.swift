import Foundation
import WarmthCore
import Logging

// MARK: - GammaBackend

/// The gamma layer: `CGSetDisplayTransferByTable` RGB ramps, reset via
/// `CGDisplayRestoreColorSyncSettings`.
///
/// Gamma is capability-CLASSIFIED, never measured by a runtime screen-capture probe (which
/// would need Screen Recording permission). It is default-OFF on M5 Tahoe because the OS
/// silently no-ops the transfer table there. This stub classifies as
/// `.unsupported(.gammaBrokenOnThisOS)` by default; real device/OS classification is a later
/// milestone.
public struct GammaBackend: WarmthBackend {
    public let method: DisplayMethod = .gamma

    private let logger = Logger(label: "com.abendrot.WarmthKit.GammaBackend")

    public init() {}

    public func classify(_ identity: DisplayIdentity) async -> Capability<Void> {
        // TODO: real classification by device/OS build. On M5 Tahoe the gamma
        // transfer table is a silent no-op, so we conservatively report it unsupported until
        // a device-specific allowlist proves otherwise. No screen-capture measurement.
        .unsupported(reason: .gammaBrokenOnThisOS)
    }

    public func apply(_ kelvin: Kelvin, to identity: DisplayIdentity) async throws {
        // TODO: build per-channel ramps from rgbGain(for:) and push them via
        // CGSetDisplayTransferByTable on identity.currentDisplayID. No-op while classified
        // unsupported.
    }

    public func reset(_ identity: DisplayIdentity) async throws {
        // TODO: CGDisplayRestoreColorSyncSettings() to drop any applied ramp.
    }
}
