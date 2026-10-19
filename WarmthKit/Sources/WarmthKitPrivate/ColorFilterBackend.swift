import Foundation
import WarmthCore
import DisplayServices
import CInterop

/// A display output transform includes surfaces above ordinary application windows.
/// The helper owns restoration if the main app terminates unexpectedly.
@MainActor
final class ColorFilterBackend: WarmthBackend {
    nonisolated let method: DisplayMethod = .colorFilter

    nonisolated init() {}

    nonisolated static func supports(chipBrand: String, os: OperatingSystemVersion, builtIn: Bool) -> Bool {
        builtIn && chipBrand == "Apple M5 Pro" && os.majorVersion == 26 && os.minorVersion >= 6
    }

    nonisolated func classify(_ identity: DisplayIdentity) async -> Capability<Void> {
        guard Self.supports(chipBrand: GammaBackend.appleSiliconBrand ?? "",
                            os: ProcessInfo.processInfo.operatingSystemVersion,
                            builtIn: identity.transport == .builtIn), WKNativeColorFilterAvailable() else {
            return .unsupported(reason: .privateSymbolUnavailable)
        }
        return .supported(())
    }

    func apply(_ kelvin: Kelvin, to identity: DisplayIdentity) async throws {
        guard case .supported = await classify(identity) else { throw ColorFilterError.unavailable }
        let gain = rgbGain(for: kelvin)
        try await NativeColorFilterController.shared.apply(displayUUID: identity.cgUUID,
            red: Self.linearGain(gain.red), green: Self.linearGain(gain.green), blue: Self.linearGain(gain.blue))
    }

    // The output matrix acts on linear light; the existing Kelvin gains are sRGB encoded.
    nonisolated static func linearGain(_ encoded: Double) -> Float {
        Float(encoded <= 0.04045 ? encoded / 12.92 : pow((encoded + 0.055) / 1.055, 2.4))
    }

    func reset(_ identity: DisplayIdentity) async throws {
        try await NativeColorFilterController.shared.reset(displayUUID: identity.cgUUID)
    }
}

private enum ColorFilterError: Error { case unavailable }
