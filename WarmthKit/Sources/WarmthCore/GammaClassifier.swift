import Foundation

// MARK: - GammaClassifier (pure)

/// Pure, testable classification of whether the **gamma** layer
/// (`CGSetDisplayTransferByTable`) is reliable on a given device/OS — WITHOUT any runtime
/// screen-capture measurement (that would need Screen Recording permission and break the
/// no-permission promise, §21‑E1).
///
/// The hard-won fact this encodes: on **Apple Silicon + macOS 26 ("Tahoe")** the gamma
/// transfer table is a **silent no-op** — `CGSetDisplayTransferByTable` returns success but the
/// panel never warms. So gamma is classified `.unsupported(.gammaBrokenOnThisOS)` there and the
/// engine keeps the overlay as the default. Gamma is only `.supported` where the transfer table
/// is known to take effect (Intel Macs, and older macOS on Apple Silicon), and even then it is
/// reachable ONLY via an explicit per-display override — never the automatic default
/// (`LayerResolver` enforces that policy).
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
        /// The global private-API kill switch. Gamma is not a *private* API, but the kill
        /// switch also denylists best-effort capability paths so the product can fall back to
        /// the overlay-only floor on a problem OS build.
        public let privateAPIsEnabled: Bool

        public init(isAppleSilicon: Bool, osMajorVersion: Int, privateAPIsEnabled: Bool) {
            self.isAppleSilicon = isAppleSilicon
            self.osMajorVersion = osMajorVersion
            self.privateAPIsEnabled = privateAPIsEnabled
        }
    }

    /// The first macOS major version on which Apple Silicon gamma is known-broken (silent no-op).
    /// macOS 26 "Tahoe" and later on Apple Silicon are denylisted for gamma.
    public static let firstBrokenAppleSiliconOSMajor = 26

    /// Classify the gamma layer for the given environment.
    ///
    /// - Returns:
    ///   - `.unsupported(.osDenylisted)` when the kill switch is engaged (overlay-only floor);
    ///   - `.unsupported(.gammaBrokenOnThisOS)` on Apple Silicon + macOS ≥ 26 (silent no-op);
    ///   - `.supported(())` otherwise (Intel, or Apple Silicon on a pre-26 OS) — still only
    ///     reachable via an explicit override, never the automatic default.
    public static func classify(_ environment: Environment) -> Capability<Void> {
        guard environment.privateAPIsEnabled else {
            // Kill switch: drop best-effort layers and run overlay-only.
            return .unsupported(reason: .osDenylisted)
        }

        if environment.isAppleSilicon, environment.osMajorVersion >= firstBrokenAppleSiliconOSMajor {
            return .unsupported(reason: .gammaBrokenOnThisOS)
        }

        return .supported(())
    }
}
