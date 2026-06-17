import Foundation
import WarmthCore
import Logging
#if canImport(AppKit)
import AppKit
import QuartzCore
#endif

// MARK: - OverlayBackend

/// The universal default layer: one borderless, click-through `NSPanel` hosting a `CALayer`
/// warm-tint veil per active `NSScreen`, sitting at `CGShieldingWindowLevel()`. Works on
/// buttonless Apple panels and on M5 Tahoe where gamma silently no-ops, so it is `.supported`
/// everywhere — it is the reliable floor under DDC (opt-in) and gamma (classified).
///
/// Main-actor isolated because it owns AppKit windows. The veil is drawn on *change only*
/// (a single `backgroundColor`/`opacity` assignment, no continuous animation), so idle GPU
/// cost is ~0%.
///
/// ## Compositing model — alpha tint today, true multiply is the plan §18 follow-up
/// Warming is currently achieved by an **alpha-blended warm tint**: a low-alpha amber layer
/// composited *over* the screen by the window server (standard source-over). We do NOT use a
/// CALayer `compositingFilter` multiply here: `compositingFilter` only blends a layer against
/// other content **inside the same window's layer tree**, and this overlay window is a
/// standalone transparent panel floating above arbitrary other apps — there is no in-tree
/// content behind the veil for it to multiply against. A *true* per-channel window-level
/// multiply (so blacks stay black instead of being tinted) requires either a Metal layer
/// reading the framebuffer or a private screen-blend mode; that is the plan §18 ("ColorSync
/// ICC injection / true multiply") follow-up. The alpha tint is the correct, shippable M0
/// floor: it warms the image without washing it to grey, at the cost of slightly lifting true
/// blacks.
///
/// ## Documented limits (§21‑E2) — the badge says `Overlay`, never "hardware"
/// A standalone shielding-level panel may NOT cover, and warmth may be absent on:
/// - **native fullscreen Spaces** — a fullscreen window can sit above auxiliary panels;
/// - **Mission Control / Exposé** — the window server takes over compositing;
/// - **the login window and the lock screen** — owned by `loginwindow`, out of our process;
/// - **protected / HDR / EDR video** (DRM surfaces, EDR tone-mapping) — composited past us;
/// - **screenshots & screen recordings** — see `sharingType` below;
/// - **multi-Space ordering** — ordering across Spaces is best-effort, not guaranteed.
@MainActor
public final class OverlayBackend: WarmthBackend {
    public nonisolated let method: DisplayMethod = .overlay

    private let logger = Logger(label: "com.abendrot.WarmthKit.OverlayBackend")

    /// Per-display veil panels, keyed by stable identity (NOT by `CGDirectDisplayID`).
    /// Populated lazily on first `apply`.
    private var panels: [DisplayIdentity: OverlayPanel] = [:]

    /// Nonisolated so the `WarmthEngine` actor can construct the backend from its own
    /// (nonisolated) initializer without a main-actor hop. The stored `panels` dictionary is
    /// initialized from a literal, so no main-actor state is touched here; AppKit windows are
    /// only created later, on the main actor, in `apply`/`reset`.
    public nonisolated init() {}

    public nonisolated func classify(_ identity: DisplayIdentity) async -> Capability<Void> {
        // Overlay is the always-available safe default — the universal floor.
        .supported(())
    }

    public func apply(_ kelvin: Kelvin, to identity: DisplayIdentity) async throws {
        #if canImport(AppKit)
        let gain = rgbGain(for: kelvin)
        guard let panel = panel(for: identity) else {
            // No matching `NSScreen` (display gone / not yet enumerated) → no-op gracefully.
            logger.debug("apply: no NSScreen matches display; skipping veil")
            return
        }
        panel.setVeilGain(gain)
        #endif
    }

    public func reset(_ identity: DisplayIdentity) async throws {
        #if canImport(AppKit)
        // Return this display to neutral: drop the veil to the identity gain (invisible) and
        // order the panel out. Keep the instance cached so a later `apply` can reuse it.
        guard let panel = panels[identity] else { return }
        panel.setVeilGain(.identity)
        panel.orderOut()
        #endif
    }

    #if canImport(AppKit)
    /// Resolve (and lazily create) the veil panel for `identity`, re-homing it onto the current
    /// matching `NSScreen`. Returns `nil` if no live screen matches (display disconnected).
    private func panel(for identity: DisplayIdentity) -> OverlayPanel? {
        guard let screen = Self.screen(for: identity) else { return nil }
        if let existing = panels[identity] {
            existing.attach(to: screen)
            return existing
        }
        let created = OverlayPanel(identity: identity, screen: screen)
        panels[identity] = created
        return created
    }

    /// Bridge `DisplayIdentity.currentDisplayID` → `NSScreen` by matching the screen's
    /// `NSScreenNumber` device-description key (the documented `NSScreen → CGDirectDisplayID`
    /// bridge). The reference recipe omits this; it is essential for per-display panels.
    private static func screen(for identity: DisplayIdentity) -> NSScreen? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[key] as? NSNumber else { return false }
            return CGDirectDisplayID(number.uint32Value) == identity.currentDisplayID
        }
    }
    #endif
}

#if canImport(AppKit)

// MARK: - OverlayPanel

/// One borderless, click-through veil window covering a single `NSScreen`'s full frame
/// (menu bar included). Owns an `NSPanel` whose content view is layer-backed; the veil is a
/// child `CALayer` whose colour/opacity encode the warmth gain.
///
/// The window recipe follows the reference `macos-app-skills` overlay playbook exactly:
/// `[.borderless, .nonactivatingPanel]`, transparent, shadowless, click-through, joins all
/// Spaces, and floats at `CGShieldingWindowLevel()`.
@MainActor
final class OverlayPanel {
    let identity: DisplayIdentity
    private(set) var currentGain: RGBGain = .identity

    private let panel: NSPanel
    private let veilLayer: CALayer

    init(identity: DisplayIdentity, screen: NSScreen) {
        self.identity = identity

        panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // ── Transparent, shadowless, click-through, always-floating chrome ──────────────
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true                 // clicks pass through — essential
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false

        // `sharingType` hook (TODO §21‑E7): defaults to `.readOnly` so the veil is VISIBLE in
        // screen captures (warmth shows in screenshots/recordings). The future
        // screenshot-exempt "reveal during captures" toggle flips this to `.none`.
        // (`.readOnly` is the non-deprecated successor to `.readWrite` for capture-visible.)
        panel.sharingType = .readOnly

        // ── Layer-backed content + the veil layer ───────────────────────────────────────
        let content = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.clear.cgColor

        let veil = CALayer()
        veil.frame = content.bounds
        veil.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        veil.backgroundColor = NSColor.clear.cgColor
        veil.actions = ["backgroundColor": NSNull(), "opacity": NSNull()]   // no implicit anim
        content.layer?.addSublayer(veil)
        veilLayer = veil

        panel.contentView = content
    }

    /// Re-home the panel onto `screen` (its frame may have moved across a reconfiguration) and
    /// resize the content/veil to cover the full frame.
    func attach(to screen: NSScreen) {
        panel.setFrame(screen.frame, display: false)
        panel.contentView?.frame = NSRect(origin: .zero, size: screen.frame.size)
        veilLayer.frame = panel.contentView?.bounds ?? veilLayer.frame
    }

    /// Push a new warmth gain into the veil. Idempotent: no-ops when unchanged (draw-on-change
    /// only). At the neutral gain (≈ identity, e.g. a 6500K apply) the veil is fully transparent,
    /// so the display is effectively native.
    func setVeilGain(_ gain: RGBGain) {
        guard gain != currentGain else { return }   // draw-on-change only → ~0% idle GPU
        currentGain = gain

        let (color, alpha) = Self.veil(for: gain)
        CATransaction.begin()
        CATransaction.setDisableActions(true)        // no implicit animation; instant update
        veilLayer.backgroundColor = color
        veilLayer.opacity = Float(alpha)
        CATransaction.commit()

        if alpha <= 0 {
            // Identity (neutral) → nothing to show; order out so the panel stops participating.
            panel.orderOut(nil)
        } else if !panel.isVisible {
            // Float above everything without stealing key/main focus.
            panel.orderFrontRegardless()
        }
    }

    func orderOut() {
        panel.orderOut(nil)
    }

    /// Translate a per-channel RGB gain (0...1, identity = 1,1,1) into the alpha-tint veil:
    /// the tint colour is the *warm light* implied by the gain, and the alpha is the amount of
    /// cool-channel attenuation we are simulating. This warms the image (cool channels darkened)
    /// without washing it to grey.
    ///
    /// Note: this is the alpha-tint fallback (see `OverlayBackend` header). A true per-channel
    /// multiply (blacks-stay-black) is the plan §18 follow-up.
    private static func veil(for gain: RGBGain) -> (CGColor, Double) {
        // How far the coolest channel has been pulled below the (always-≈1.0) red anchor is a
        // good proxy for "how warm" the target is: 0 at neutral, ~0.6+ at the warmest point.
        let attenuation = max(0, gain.red - gain.blue)

        // Cap the veil's strength so even the warmest setting stays a tint, not an opaque wash.
        // (~0.55 alpha at the warmest end keeps the screen legible.)
        let alpha = min(0.55, attenuation)

        // The tint colour is the warm light itself (the gain), so the residue the tint adds is
        // amber rather than grey. Drawn at full per-channel intensity; the `alpha` above governs
        // how strongly it is laid over the screen.
        let color = CGColor(
            srgbRed: gain.red,
            green: gain.green,
            blue: gain.blue,
            alpha: 1.0
        )
        return (color, alpha)
    }
}

#endif
