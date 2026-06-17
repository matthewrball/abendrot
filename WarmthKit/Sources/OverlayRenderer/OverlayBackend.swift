import Foundation
import WarmthCore
import Logging
#if canImport(AppKit)
import AppKit
#endif

// MARK: - OverlayBackend

/// The universal default layer: one borderless, click-through `NSPanel` + `CAMetalLayer`
/// multiply veil per `NSScreen` at `CGShieldingWindowLevel()`. Works on buttonless Apple
/// panels and on M5 Tahoe where gamma silently no-ops, so it is `.supported` everywhere.
///
/// Main-actor isolated because it owns AppKit windows. Draws on change only (~0% idle GPU).
/// Documented limits (§21‑E2): native fullscreen Spaces, Mission Control, the login/lock
/// window, and protected/HDR/EDR video may not be covered.
@MainActor
public final class OverlayBackend: WarmthBackend {
    public nonisolated let method: DisplayMethod = .overlay

    private let logger = Logger(label: "com.abendrot.WarmthKit.OverlayBackend")

    /// Per-display veil panels, keyed by stable identity. Populated lazily on first apply.
    private var panels: [DisplayIdentity: OverlayPanel] = [:]

    /// Nonisolated so the `WarmthEngine` actor can construct the backend from its own
    /// (nonisolated) initializer without a main-actor hop. The stored `panels` dictionary is
    /// initialized from a literal, so no main-actor state is touched here; AppKit windows are
    /// only created later, on the main actor, in `apply`/`reset`.
    public nonisolated init() {}

    public nonisolated func classify(_ identity: DisplayIdentity) async -> Capability<Void> {
        // Overlay is the always-available safe default.
        .supported(())
    }

    public func apply(_ kelvin: Kelvin, to identity: DisplayIdentity) async throws {
        let gain = rgbGain(for: kelvin)
        let panel = panel(for: identity)
        panel.setVeilGain(gain)
        // TODO(milestone): mount the panel on the matching NSScreen at CGShieldingWindowLevel,
        // configure click-through + multi-space collection behaviour, and drive a CAMetalLayer
        // multiply shader from `gain`. Draw-on-change only.
    }

    public func reset(_ identity: DisplayIdentity) async throws {
        panels[identity]?.setVeilGain(.identity)
        // TODO(milestone): tear the panel down / order it out so the display returns to native.
    }

    private func panel(for identity: DisplayIdentity) -> OverlayPanel {
        if let existing = panels[identity] { return existing }
        let created = OverlayPanel(identity: identity)
        panels[identity] = created
        return created
    }
}

// MARK: - OverlayPanel (stub)

/// Stub for the per-`NSScreen` veil window. The real implementation owns a borderless
/// `NSPanel` hosting a `CAMetalLayer` that multiplies the screen by the warmth gain.
@MainActor
final class OverlayPanel {
    let identity: DisplayIdentity
    private(set) var currentGain: RGBGain = .identity

    init(identity: DisplayIdentity) {
        self.identity = identity
        // TODO(milestone): create the borderless NSPanel + CAMetalLayer here.
    }

    func setVeilGain(_ gain: RGBGain) {
        guard gain != currentGain else { return }   // draw-on-change only
        currentGain = gain
        // TODO(milestone): push `gain` into the Metal multiply shader and request a redraw.
    }
}
