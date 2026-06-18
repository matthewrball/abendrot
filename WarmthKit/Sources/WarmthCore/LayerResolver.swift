import Foundation

// MARK: - LayerResolver (pure)

/// Pure, testable resolution of which warmth *layer* a display should be driven with.
///
/// This encodes the engine's safety policy in one place so it can be unit-tested headlessly:
/// - **External, opted-in DDC** is the highest-quality automatic path (real hardware RGB gain),
///   requiring per-display opt-in AND a supported capability AND private APIs enabled.
/// - **Gamma is the universal true-warm default** for ANY display where the transfer table is
///   supported — a real per-channel multiply (not a tint). It is OS-level and display-agnostic, so
///   it warms built-in AND external panels (incl. buttonless Apple displays that expose no DDC).
///   DDC, when opted in, ranks above it as a hardware upgrade. (§25.)
/// - **Overlay is the guaranteed floor** (the universal fallback): built-in panels where gamma is
///   broken, and externals without a DDC opt-in.
/// - The kill switch (`privateAPIsEnabled == false`) removes DDC *and* gamma, dropping to overlay.
/// - A user **override** (`setPreferredMethod`) is honored only when it is actually *usable*.
///
/// Crucially this never returns `.off`: "off" is a *warmth* decision (engine disabled, schedule
/// inactive, or revealing), not a *layer*. Keeping the layer stable across off↔on transitions is
/// what lets a display resume warming after it has gone neutral — conflating the two is the bug
/// that traps a display cold once it turns off.
public enum LayerResolver {

    /// Resolve the layer for a display under the current policy.
    ///
    /// - Parameters:
    ///   - capabilities: per-display, per-method classification.
    ///   - isHardwareDDCEnabled: the user's per-display DDC opt-in.
    ///   - override: an explicit user layer choice, or `nil` for automatic best-available.
    ///   - privateAPIsEnabled: the global kill switch; when `false`, DDC is unavailable.
    /// - Returns: the layer to drive this display with — never `.off`.
    public static func resolveLayer(
        capabilities: DisplayCapabilities,
        isHardwareDDCEnabled: Bool,
        override: DisplayMethod?,
        privateAPIsEnabled: Bool
    ) -> DisplayMethod {
        // An explicit override wins, but only if it is genuinely usable right now.
        if let override, override != .off,
           isUsable(
               override,
               capabilities: capabilities,
               isHardwareDDCEnabled: isHardwareDDCEnabled,
               privateAPIsEnabled: privateAPIsEnabled
           ) {
            return override
        }

        // Automatic best-available, in order of warmth quality.
        // External panels: real hardware warmth via DDC when opted-in, supported, private APIs on.
        if privateAPIsEnabled, isHardwareDDCEnabled, isSupported(capabilities.hardware) {
            return .hardware
        }
        // Gamma is the universal TRUE white-point warm path — a real per-channel multiply that
        // removes blue, not an overlay tint — for ANY display where the transfer table is supported
        // (base M-series / Intel / pre-26; NOT the M5 Pro/Max no-op bracket). It is OS-level and
        // display-agnostic, so it warms the built-in AND external panels identically and needs no
        // per-monitor DDC support. Crucially it is the ONLY true-warm path for buttonless Apple
        // displays (LG UltraFine / Studio Display / Pro Display XDR), which expose no DDC gain VCP —
        // verified warming an LG UltraFine over Thunderbolt on a base M5. DDC (checked above) stays
        // the opt-in hardware upgrade for monitors that support it; gamma is the default.
        // (§25 — the "external gamma is unreliable" assumption was disproven on hardware.)
        if privateAPIsEnabled, isSupported(capabilities.gamma) {
            return .gamma
        }

        // Overlay is the guaranteed floor (built-in where gamma is unavailable, external w/o DDC).
        return .overlay
    }

    /// Is `method` actually usable for this display under the current policy?
    public static func isUsable(
        _ method: DisplayMethod,
        capabilities: DisplayCapabilities,
        isHardwareDDCEnabled: Bool,
        privateAPIsEnabled: Bool
    ) -> Bool {
        switch method {
        case .hardware:
            return privateAPIsEnabled && isHardwareDDCEnabled && isSupported(capabilities.hardware)
        case .gamma:
            // Gamma is a best-effort path; the kill switch denylists it alongside the private
            // APIs so an engaged kill switch drops the whole machine to the overlay-only floor.
            return privateAPIsEnabled && isSupported(capabilities.gamma)
        case .overlay:
            return true                 // the always-available safe floor
        case .off:
            return false                // not a layer
        }
    }

    private static func isSupported<T>(_ cap: Capability<T>) -> Bool {
        if case .supported = cap { return true }
        return false
    }
}
