import Foundation
import CoreGraphics
import ColorSync          // CGDisplayCreateUUIDFromDisplayID lives here on modern macOS SDKs
import WarmthCore
import Logging

// MARK: - DisplayRegistry

/// Builds `DisplayIdentity` values from the live display configuration.
///
/// Uses CoreGraphics for the online display list, the stable per-display UUID, frame, and
/// transport heuristics. EDID parsing (vendor/product/serial via CoreDisplay or IOKit) is
/// stubbed for this milestone — see `edidFingerprint(for:)`.
public struct DisplayRegistry: Sendable {
    private let logger = Logger(label: "com.abendrot.WarmthKit.DisplayRegistry")

    public init() {}

    /// Snapshot the currently online displays as stable identities.
    ///
    /// Hotplug/reconfiguration debouncing and re-baselining live in the engine; this is a
    /// pure read of the current configuration.
    public func currentDisplays() -> [DisplayIdentity] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else {
            return []
        }

        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else {
            return []
        }

        return ids.prefix(Int(count)).map(identity(for:))
    }

    /// Build a `DisplayIdentity` for a single `CGDirectDisplayID`.
    public func identity(for displayID: CGDirectDisplayID) -> DisplayIdentity {
        DisplayIdentity(
            cgUUID: stableUUID(for: displayID),
            edid: edidFingerprint(for: displayID),
            transport: transport(for: displayID),
            ioRegistryPath: ioRegistryPath(for: displayID),
            currentDisplayID: displayID,
            frame: CGDisplayBounds(displayID),
            backingScale: 1
        )
    }

    // MARK: Stable UUID

    private func stableUUID(for displayID: CGDirectDisplayID) -> UUID {
        guard let cfUUID = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else {
            // Deterministic fallback so a missing UUID still keys consistently within a run.
            return deterministicUUID(seed: UInt64(displayID))
        }
        let cfString = CFUUIDCreateString(nil, cfUUID) as String
        return UUID(uuidString: cfString) ?? deterministicUUID(seed: UInt64(displayID))
    }

    private func deterministicUUID(seed: UInt64) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        var s = seed
        for i in 0..<8 {
            bytes[i] = UInt8(truncatingIfNeeded: s)
            s >>= 8
        }
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    // MARK: Transport heuristic

    private func transport(for displayID: CGDirectDisplayID) -> DisplayTransport {
        if CGDisplayIsBuiltin(displayID) != 0 { return .builtIn }
        // TODO(milestone): derive DisplayPort / HDMI / Thunderbolt / USB-C from the IORegistry
        // transport node. CoreGraphics alone can't distinguish external transports.
        return .unknown
    }

    // MARK: EDID (stub)

    private func edidFingerprint(for displayID: CGDirectDisplayID) -> EDIDFingerprint? {
        // TODO(milestone): parse EDID via CoreDisplay_DisplayCreateInfoDictionary (CInterop,
        // dlsym-resolved) or the IORegistry EDID blob to fill vendor/product/serial/name.
        // For now return CoreGraphics vendor/model so duplicate-monitor disambiguation has
        // *something* to key on, without the (redaction-sensitive) serial.
        let vendor = CGDisplayVendorNumber(displayID)
        let model = CGDisplayModelNumber(displayID)
        guard vendor != 0xFFFF_FFFF, model != 0xFFFF_FFFF else { return nil }
        return EDIDFingerprint(
            vendorID: UInt16(truncatingIfNeeded: vendor),
            productID: UInt16(truncatingIfNeeded: model),
            serial: nil,        // deliberately not populated — see redaction policy
            displayName: nil    // TODO(milestone): human label from EDID descriptor
        )
    }

    private func ioRegistryPath(for displayID: CGDirectDisplayID) -> String? {
        // TODO(milestone): resolve the AppleCLCD2 / DCPAVServiceProxy IORegistry path used by
        // the DDC layer to bind an IOAVService to this display.
        nil
    }
}
