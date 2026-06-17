import Foundation

// MARK: - LayerResolver (pure)

/// Pure, testable resolution of which warmth *layer* a display should be driven with.
///
/// This encodes the engine's safety policy in one place so it can be unit-tested headlessly:
/// - **Overlay is the guaranteed default** (the universal fallback).
/// - **DDC / hardware requires per-display opt-in AND a supported capability AND private APIs
///   enabled** — the kill switch (`privateAPIsEnabled == false`) removes hardware entirely.
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

        // Automatic best-available: hardware only when opted-in, supported, and private APIs on.
        if privateAPIsEnabled, isHardwareDDCEnabled, isSupported(capabilities.hardware) {
            return .hardware
        }

        // Overlay is the guaranteed default. Gamma is best-effort and reached only via an
        // explicit, usable override (it is default-off — e.g. broken on M5 Tahoe).
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
            return isSupported(capabilities.gamma)
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
