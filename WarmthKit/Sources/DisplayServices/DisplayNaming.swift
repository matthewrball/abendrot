import AppKit
import CoreGraphics

// MARK: - DisplayNaming
//
// Resolves the OS-localized display name ("Built-in Display", "LG UltraFine") — the same label
// macOS shows in System Settings — so per-display rows read like the user's own configuration
// instead of a generic "Display". CoreGraphics/EDID gives us only vendor/model *numbers*;
// `NSScreen.localizedName` is the public, no-permission source of the friendly label, mapped back
// to a display by the documented `NSScreenNumber` device-description key (same bridge the
// `OverlayBackend` uses).
//
// `NSScreen` is main-actor isolated, so this is `@MainActor`; the engine actor hops here once per
// (re)baseline — a cheap, change-only path, never per frame.
public enum DisplayNaming {

    /// OS-localized names keyed by `CGDirectDisplayID`, for the requested IDs only. An ID with no
    /// matching live `NSScreen`, or an empty name, is omitted — so callers keep their own fallback.
    @MainActor
    public static func localizedNames(for ids: [CGDirectDisplayID]) -> [CGDirectDisplayID: String] {
        guard !ids.isEmpty else { return [:] }
        let wanted = Set(ids)
        let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
        var byID: [CGDirectDisplayID: String] = [:]
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[screenNumberKey] as? NSNumber else { continue }
            let id = CGDirectDisplayID(number.uint32Value)
            guard wanted.contains(id) else { continue }
            let name = screen.localizedName
            if !name.isEmpty { byID[id] = name }
        }
        return byID
    }
}
