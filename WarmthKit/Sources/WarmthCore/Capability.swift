import Foundation

// MARK: - Capability

/// Every private/backend lookup returns a typed capability result, so "we don't know" is a
/// first-class value the UI can render — never a silent nil.
public enum Capability<Detail: Sendable>: Sendable {
    case supported(Detail)
    case unsupported(reason: CapabilityReason)
    case unknown(reason: CapabilityReason)      // e.g. private symbol missing on this OS build
}

public enum CapabilityReason: String, Sendable, Codable {
    case ok
    case buttonlessAppleDisplay     // exposes no DDC colour VCP → overlay
    case gammaBrokenOnThisOS        // M5 Tahoe silent no-op → overlay
    case privateSymbolUnavailable   // dlsym returned null on this OS build → kill-switch path
    case ddcProbeFailed             // VCP 0x16 read failed
    case osDenylisted               // OS build on the private-API denylist
    case notYetProbed
}

// MARK: - DisplayCapabilities

/// Per-display, per-method classification the engine computes at baseline.
public struct DisplayCapabilities: Sendable {
    public let identity: DisplayIdentity
    public let hardware: Capability<DDCColorCaps>    // DDC gain support
    public let gamma: Capability<Void>               // classified, NOT measured
    public let overlay: Capability<Void>             // ~always .supported
    /// Best layer the engine will use by default given current opt-ins.
    public var recommendedMethod: DisplayMethod

    public init(
        identity: DisplayIdentity,
        hardware: Capability<DDCColorCaps>,
        gamma: Capability<Void>,
        overlay: Capability<Void>,
        recommendedMethod: DisplayMethod
    ) {
        self.identity = identity
        self.hardware = hardware
        self.gamma = gamma
        self.overlay = overlay
        self.recommendedMethod = recommendedMethod
    }
}

public struct DDCColorCaps: Sendable {
    public let supportsRGBGain: Bool /* VCP 0x16/0x18/0x1A */

    public init(supportsRGBGain: Bool) {
        self.supportsRGBGain = supportsRGBGain
    }
}
