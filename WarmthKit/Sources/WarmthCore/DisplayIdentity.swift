import Foundation
import CoreGraphics

// MARK: - DisplayIdentity

/// Stable, hotplug-survivable identity for a display. NEVER key state on CGDirectDisplayID.
///
/// Equality and hashing are keyed on `cgUUID` (+ `edid` to disambiguate identical twin
/// monitors). The transient fields — `currentDisplayID`, `frame`, `backingScale` — are
/// refreshed on every reconfiguration and are deliberately excluded from identity.
public struct DisplayIdentity: Hashable, Sendable, Codable {
    public let cgUUID: UUID                 // CGDisplayCreateUUIDFromDisplayID — primary key
    public let edid: EDIDFingerprint?       // vendor/product/serial — disambiguates duplicates
    public let transport: DisplayTransport  // builtIn / displayPort / hdmi / thunderbolt / unknown
    public let ioRegistryPath: String?      // AppleCLCD2 / DCPAVServiceProxy path, if resolvable

    // Transient (NOT part of identity equality) — refreshed on every reconfiguration:
    public var currentDisplayID: CGDirectDisplayID  // changes across hotplug/sleep
    public var frame: CGRect                        // NSScreen frame
    public var backingScale: CGFloat

    public init(
        cgUUID: UUID,
        edid: EDIDFingerprint? = nil,
        transport: DisplayTransport = .unknown,
        ioRegistryPath: String? = nil,
        currentDisplayID: CGDirectDisplayID = 0,
        frame: CGRect = .zero,
        backingScale: CGFloat = 1
    ) {
        self.cgUUID = cgUUID
        self.edid = edid
        self.transport = transport
        self.ioRegistryPath = ioRegistryPath
        self.currentDisplayID = currentDisplayID
        self.frame = frame
        self.backingScale = backingScale
    }

    // MARK: Identity = (cgUUID, edid) only — transient fields excluded.

    public static func == (lhs: DisplayIdentity, rhs: DisplayIdentity) -> Bool {
        lhs.cgUUID == rhs.cgUUID && lhs.edid == rhs.edid
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(cgUUID)
        hasher.combine(edid)
    }
}

// MARK: - EDIDFingerprint

public struct EDIDFingerprint: Hashable, Sendable, Codable {
    public let vendorID: UInt16
    public let productID: UInt16
    public let serial: UInt32?              // may be absent; do NOT log/transmit (see redaction)
    public let displayName: String?         // human label for the UI

    public init(vendorID: UInt16, productID: UInt16, serial: UInt32? = nil, displayName: String? = nil) {
        self.vendorID = vendorID
        self.productID = productID
        self.serial = serial
        self.displayName = displayName
    }
}

// MARK: - DisplayTransport

public enum DisplayTransport: String, Sendable, Codable {
    case builtIn, displayPort, hdmi, thunderbolt, usbC, unknown
}
