import Foundation
import CoreGraphics
import WarmthCore
import Logging
import Darwin

// MARK: - GammaBackend

/// The gamma layer: per-channel `CGSetDisplayTransferByTable` ramps, reset via
/// `CGDisplayRestoreColorSyncSettings`.
///
/// Gamma is capability-CLASSIFIED, never measured by a runtime screen-capture probe (which
/// would need Screen Recording permission). The decision itself lives in the pure
/// `GammaClassifier` (so it is unit-testable headlessly); this backend only gathers the runtime
/// facts (CPU architecture, OS major version, exact chip/display combination, kill-switch) and
/// feeds them in. Policy: gamma is the **automatic warm
/// path for ANY display** where supported (`LayerResolver` routes both built-in and external panels
/// to it — it is OS-level, so it warms buttonless Apple displays that expose no DDC). It is
/// `.unsupported(.gammaBrokenOnThisOS)` only on configurations where the macOS ≥ 26 no-op has
/// actually been reproduced. The overlay remains the guaranteed floor there.
public struct GammaBackend: WarmthBackend {
    public let method: DisplayMethod = .gamma

    private let logger = Logger(label: "com.abendrot.WarmthKit.GammaBackend")

    /// The per-channel ramp resolution. 256 entries is the standard transfer-table size and is
    /// universally accepted by `CGSetDisplayTransferByTable`.
    private static let rampSize = 256

    public init() {}

    // MARK: Classification

    /// Classify the *device/OS* gamma capability. The kill switch is NOT folded in here — that
    /// denylisting lives in `LayerResolver` so the published capability reflects the hardware
    /// truth ("gamma is broken on this OS") independent of the runtime toggle, and the UI can
    /// explain *why* it is unavailable.
    public func classify(_ identity: DisplayIdentity) async -> Capability<Void> {
        #if DEBUG
        // DEV/preview hook: ABENDROT_FORCE_TINT_ONLY simulates an incompatible config (gamma
        // classified broken) on ANY Mac, so the "this display can only be tinted" UI can be
        // designed + tested without affected hardware. With gamma forced off and DDC opt-in off,
        // every display falls to the overlay floor — the exact tint-only state.
        if ProcessInfo.processInfo.environment["ABENDROT_FORCE_TINT_ONLY"] != nil {
            return .unsupported(reason: .gammaBrokenOnThisOS)
        }
        #endif
        return GammaClassifier.classify(Self.currentEnvironment(for: identity))
    }

    /// Snapshot the cheap, permission-free runtime facts the classifier decides from. Passes
    /// `privateAPIsEnabled: true` because this backend reports pure device capability; the kill
    /// switch is applied separately by `LayerResolver`.
    static func currentEnvironment(for identity: DisplayIdentity) -> GammaClassifier.Environment {
        GammaClassifier.Environment(
            isAppleSilicon: isAppleSilicon,
            osMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
            appleSiliconHasKnownGammaBug: GammaClassifier.hasKnownGammaBug(
                chipBrand: appleSiliconBrand ?? "",
                isBuiltInDisplay: identity.transport == .builtIn
            ),
            privateAPIsEnabled: true
        )
    }

    /// Apple Silicon detection without spawning a process: `arm64` builds run on Apple Silicon.
    /// (Rosetta-translated x86_64 builds aren't shipped here; the package targets arm64.)
    static var isAppleSilicon: Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }

    /// CPU brand used by the exact known-broken hardware list. Unknown hardware is not
    /// automatically condemned to a tint; gamma is the documented CoreGraphics path and remains
    /// the default unless a configuration has reproduced the silent no-op.
    static var appleSiliconBrand: String? {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0) == 0 else {
            return nil
        }
        // sysctl's length includes the C string's NUL terminator; decode up to (not including) it.
        let brand = String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
            .trimmingCharacters(in: .whitespaces)
        return brand.isEmpty ? nil : brand
    }

    // MARK: Apply / reset (only reachable via an explicit override; see LayerResolver)

    public func apply(_ kelvin: Kelvin, to identity: DisplayIdentity) async throws {
        // Guard: never write the transfer table where it is classified unreliable. The engine
        // already gates this behind LayerResolver, but defend in depth so a stray call can't
        // silently no-op (or worse) on a denylisted OS.
        guard case .supported = await classify(identity) else {
            throw GammaError.classifiedUnsupported
        }

        let gain = rgbGain(for: kelvin)
        let (red, green, blue) = Self.ramps(for: gain)

        let status = red.withUnsafeBufferPointer { r in
            green.withUnsafeBufferPointer { g in
                blue.withUnsafeBufferPointer { b in
                    CGSetDisplayTransferByTable(
                        identity.currentDisplayID,
                        UInt32(Self.rampSize),
                        r.baseAddress!,
                        g.baseAddress!,
                        b.baseAddress!
                    )
                }
            }
        }
        guard status == .success else {
            logger.error("CGSetDisplayTransferByTable failed: \(status.rawValue)")
            throw GammaError.applyFailed(status)
        }
    }

    public func reset(_ identity: DisplayIdentity) async throws {
        // Drop any applied ramp back to the ColorSync-calibrated default. This is global (it
        // restores every display's gamma to its profile), which is the documented, safe reset
        // for the transfer table and the same call the emergency restore uses.
        CGDisplayRestoreColorSyncSettings()
    }

    // MARK: Ramp construction (pure)

    /// Build the three per-channel transfer-table ramps for a target gain. Each ramp is a linear
    /// 0…1 identity scaled by that channel's gain, so the panel's white point is pulled toward
    /// the warm target while preserving relative tone within the channel.
    static func ramps(for gain: RGBGain) -> (red: [Float], green: [Float], blue: [Float]) {
        var red = [Float](repeating: 0, count: rampSize)
        var green = [Float](repeating: 0, count: rampSize)
        var blue = [Float](repeating: 0, count: rampSize)
        let last = Float(rampSize - 1)
        for i in 0..<rampSize {
            let x = Float(i) / last            // identity ramp position 0…1
            red[i] = x * Float(gain.red)
            green[i] = x * Float(gain.green)
            blue[i] = x * Float(gain.blue)
        }
        return (red, green, blue)
    }
}

// MARK: - GammaError

public enum GammaError: Error, Sendable {
    case classifiedUnsupported
    case applyFailed(CGError)
}
