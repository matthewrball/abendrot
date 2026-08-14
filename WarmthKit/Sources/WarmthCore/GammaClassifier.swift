import Foundation

// MARK: - GammaClassifier (pure)

/// Pure, testable classification of whether the **gamma** layer
/// (`CGSetDisplayTransferByTable`) is reliable on a given device/OS — WITHOUT any runtime
/// screen-capture measurement (that would need Screen Recording permission and break the
/// no-permission promise).
///
/// The hard-won fact this encodes (refined by the hardware test): the gamma transfer table
/// silently no-ops **only on the high-end Apple Silicon variants** (M-series "Pro"/"Max"/"Ultra")
/// on macOS ≥ 26 — `CGSetDisplayTransferByTable` returns success but the panel never warms (Apple
/// DTS confirmed the 2026 regression is isolated to those chips; FB22273782). On **base M-series**
/// (and Intel, and older macOS) the transfer table **takes effect** — verified by direct on-device
/// test. So gamma is classified `.supported` everywhere EXCEPT that known-broken bracket, where it
/// stays `.unsupported(.gammaBrokenOnThisOS)` so the engine keeps the overlay floor rather than
/// falsely badging "Gamma" on a panel that never warms. Where supported, gamma is the **automatic
/// warm path for ANY display** (`LayerResolver` routes both built-in and external panels to it —
/// it is OS-level and display-agnostic, and the only true-warm path for buttonless Apple displays).
///
/// Residual risk: a readback probe CANNOT detect the no-op (the bug makes
/// `CGGetDisplayTransferByTable` read back the written values while the pixels don't change), so
/// this gates on the chip-class + OS allowlist, not a measurement. A future user-confirmed-gamma
/// check (a one-tap "did this warm?" in onboarding) would recover any mis-gated config without
/// needing Screen Recording.
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
        /// `true` on the high-end Apple Silicon variants (M-series "Pro"/"Max"/"Ultra") where the
        /// macOS ≥ 26 gamma transfer-table regression is documented. Base M-series → `false`.
        public let appleSiliconIsProClass: Bool
        /// The global private-API kill switch. Gamma is not a *private* API, but the kill
        /// switch also denylists best-effort capability paths so the product can fall back to
        /// the overlay-only floor on a problem OS build.
        public let privateAPIsEnabled: Bool

        public init(
            isAppleSilicon: Bool,
            osMajorVersion: Int,
            appleSiliconIsProClass: Bool = false,
            privateAPIsEnabled: Bool
        ) {
            self.isAppleSilicon = isAppleSilicon
            self.osMajorVersion = osMajorVersion
            self.appleSiliconIsProClass = appleSiliconIsProClass
            self.privateAPIsEnabled = privateAPIsEnabled
        }
    }

    /// The first macOS major version on which the high-end Apple Silicon (Pro/Max/Ultra) gamma
    /// transfer table is known-broken (silent no-op). macOS 26 "Tahoe"+; base M-series unaffected.
    public static let firstBrokenAppleSiliconOSMajor = 26

    /// Pure predicate: is `brand` (the CPU `machdep.cpu.brand_string`) a **base** M-series chip —
    /// exactly `"Apple M<number>"`, no Pro/Max/Ultra suffix? Only the base class is known to honor
    /// the gamma transfer table on macOS ≥ 26. Everything else — Pro/Max/Ultra, OR any unrecognized
    /// Apple-Silicon brand string (format drift, empty read) — returns `false` so the caller fails
    /// SAFE toward the honest overlay floor rather than risk a false "Gamma" badge on a panel that
    /// silently no-ops. `GammaBackend` passes the negation as `Environment.appleSiliconIsProClass`.
    ///
    public static func isBaseAppleSiliconBrand(_ brand: String) -> Bool {
        let trimmed = brand.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("Apple M") else { return false }
        let suffix = trimmed.dropFirst("Apple M".count)   // e.g. "5" for "Apple M5"
        return !suffix.isEmpty && suffix.allSatisfy(\.isNumber)
    }

    /// Classify the gamma layer for the given environment.
    ///
    /// - Returns:
    /// - `.unsupported(.osDenylisted)` when the kill switch is engaged (overlay-only floor);
    /// - `.unsupported(.gammaBrokenOnThisOS)` on high-end Apple Silicon (Pro/Max/Ultra) on
    /// macOS ≥ 26, where the transfer table silently no-ops;
    /// - `.supported()` otherwise (Intel, pre-26 Apple Silicon, and **base M-series on Tahoe**
    /// verified working) — where it is the automatic built-in warm path.
    public static func classify(_ environment: Environment) -> Capability<Void> {
        guard environment.privateAPIsEnabled else {
            // Kill switch: drop best-effort layers and run overlay-only.
            return .unsupported(reason: .osDenylisted)
        }

        // Known-broken bracket ONLY: high-end Apple Silicon (Pro/Max/Ultra) on macOS ≥ 26. Base
        // M-series round-trips correctly (verified on hardware), so it is NOT denylisted.
        if environment.isAppleSilicon,
           environment.osMajorVersion >= firstBrokenAppleSiliconOSMajor,
           environment.appleSiliconIsProClass {
            return .unsupported(reason: .gammaBrokenOnThisOS)
        }

        return .supported(())
    }
}
