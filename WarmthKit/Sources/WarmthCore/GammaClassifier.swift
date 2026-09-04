import Foundation

// MARK: - GammaClassifier (pure)

/// Pure, testable classification of whether the **gamma** layer
/// (`CGSetDisplayTransferByTable`) is reliable on a given device/OS — WITHOUT any runtime
/// screen-capture measurement (that would need Screen Recording permission and break the
/// no-permission promise).
///
/// The hard-won fact this encodes (refined by the hardware test): the gamma transfer table
/// silently no-ops on specific 2026 hardware — M5 Pro/Max displays and MacBook Neo external
/// displays — on macOS ≥ 26. `CGSetDisplayTransferByTable` returns success but the panel never
/// warms (FB22273730/FB22273782). Earlier Pro/Max chips are unaffected; Apple DTS reproduced the
/// failure on M5 Max while confirming the same test works on M3 Max. Known-good hardware keeps
/// gamma, known-broken hardware uses the overlay, and unknown Apple-silicon hardware on Tahoe
/// also uses the overlay conservatively. That last rule prevents a future chip from silently
/// reporting success while producing no visible warmth. Where supported, gamma is the **automatic
/// warm path for ANY display** (`LayerResolver` routes both built-in and external panels to it —
/// it is OS-level and display-agnostic, and the only true-warm path for buttonless Apple displays).
///
/// Residual risk: a readback probe CANNOT detect the no-op (the bug makes
/// `CGGetDisplayTransferByTable` read back the written values while the pixels don't change), so
/// this gates on the reproduced hardware + OS list and uses a conservative fallback for unknown
/// Apple-silicon chip strings, not a measurement. A future one-tap "did this warm?" check in
/// onboarding would recover any mis-gated config without needing Screen Recording.
///
/// This is a *decision function over facts the caller already has* (CPU architecture + OS major
/// version + whether the private-API kill switch is engaged). The system layer
/// (`GammaBackend`) gathers those facts at runtime and delegates the decision here so the policy
/// itself is unit-testable headlessly.
public enum GammaClassifier {

    /// The inputs the classification decision is made from. All are cheap, permission-free
    /// facts the system layer reads at runtime (no measurement, no capture).
    public struct Environment: Sendable, Hashable {
        /// `true` on Apple Silicon (arm64), `false` on Intel (x86_64).
        public let isAppleSilicon: Bool
        /// The running macOS major version (e.g. `26` for Tahoe, `15` for Sequoia).
        public let osMajorVersion: Int
        /// `true` only for a hardware/display combination where the macOS ≥ 26 gamma regression
        /// has been reproduced. This is deliberately narrower than "Pro/Max" as a chip class.
        public let appleSiliconHasKnownGammaBug: Bool
        /// `false` when the chip brand is unavailable or is newer than the allowlisted hardware
        /// families. Unknown Apple-silicon hardware uses the overlay on macOS ≥ 26.
        public let appleSiliconChipIsKnown: Bool
        /// The global private-API kill switch. Gamma is not a *private* API, but the kill
        /// switch also denylists best-effort capability paths so the product can fall back to
        /// the overlay-only floor on a problem OS build.
        public let privateAPIsEnabled: Bool

        public init(
            isAppleSilicon: Bool,
            osMajorVersion: Int,
            appleSiliconHasKnownGammaBug: Bool = false,
            appleSiliconChipIsKnown: Bool = true,
            privateAPIsEnabled: Bool
        ) {
            self.isAppleSilicon = isAppleSilicon
            self.osMajorVersion = osMajorVersion
            self.appleSiliconHasKnownGammaBug = appleSiliconHasKnownGammaBug
            self.appleSiliconChipIsKnown = appleSiliconChipIsKnown
            self.privateAPIsEnabled = privateAPIsEnabled
        }
    }

    /// The first macOS major version on which the affected 2026 hardware silently ignores gamma.
    public static let firstBrokenAppleSiliconOSMajor = 26

    /// Match only configurations where the gamma no-op has actually been reproduced. In
    /// particular, M1–M4 Pro/Max/Ultra chips must not be swept into the M5 regression.
    public static func hasKnownGammaBug(chipBrand: String, isBuiltInDisplay: Bool) -> Bool {
        switch chipBrand.trimmingCharacters(in: .whitespaces) {
        case "Apple M5 Pro", "Apple M5 Max":
            return true
        case "Apple A18 Pro":
            return !isBuiltInDisplay // MacBook Neo report is external-display-only.
        default:
            return false
        }
    }

    /// Return whether the chip string is part of a hardware family for which the Tahoe gamma
    /// path is currently an intentional choice. Unknown/future strings must use overlay rather
    /// than optimistic gamma because API success and transfer-table readback do not prove visible
    /// warmth on Tahoe.
    public static func isKnownAppleSiliconChip(chipBrand: String) -> Bool {
        switch chipBrand.trimmingCharacters(in: .whitespaces) {
        case "Apple A18 Pro",
             "Apple M1", "Apple M1 Pro", "Apple M1 Max", "Apple M1 Ultra",
             "Apple M2", "Apple M2 Pro", "Apple M2 Max", "Apple M2 Ultra",
             "Apple M3", "Apple M3 Pro", "Apple M3 Max", "Apple M3 Ultra",
             "Apple M4", "Apple M4 Pro", "Apple M4 Max",
             "Apple M5", "Apple M5 Pro", "Apple M5 Max":
            return true
        default:
            return false
        }
    }

    /// Classify the gamma layer for the given environment.
    ///
    /// - Returns:
    /// - `.unsupported(.osDenylisted)` when the kill switch is engaged (overlay-only floor);
    /// - `.unsupported(.gammaBrokenOnThisOS)` on a known-affected Apple Silicon configuration
    /// on macOS ≥ 26, where the transfer table silently no-ops;
    /// - `.unsupported(.gammaConservativeFallback)` on unknown Apple Silicon running Tahoe;
    /// the overlay is safer than trusting a silent gamma no-op;
    /// - `.supported()` otherwise, where gamma is the automatic true-warm path.
    public static func classify(_ environment: Environment) -> Capability<Void> {
        guard environment.privateAPIsEnabled else {
            // Kill switch: drop best-effort layers and run overlay-only.
            return .unsupported(reason: .osDenylisted)
        }

        // Known-broken hardware gets the precise reason. Unknown/future Apple Silicon uses the
        // conservative overlay floor because the transfer API can report success while doing
        // nothing visible. Apple DTS explicitly confirmed the same test works on M3 Max.
        if environment.isAppleSilicon,
           environment.osMajorVersion >= firstBrokenAppleSiliconOSMajor {
            if environment.appleSiliconHasKnownGammaBug {
                return .unsupported(reason: .gammaBrokenOnThisOS)
            }
            if !environment.appleSiliconChipIsKnown {
                return .unsupported(reason: .gammaConservativeFallback)
            }
        }

        return .supported(())
    }
}
