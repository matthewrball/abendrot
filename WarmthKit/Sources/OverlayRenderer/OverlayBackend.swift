import Foundation
import WarmthCore
import Logging
#if canImport(AppKit)
import AppKit
import QuartzCore
#endif

// MARK: - OverlayVeil (tunable alpha-tint parameters)

/// The alpha-over warm-tint parameters. Both are **visual-QA knobs**: the black-lift math is
/// certain (a black pixel lifts to `tint·alpha`), but how warm/legible it looks on real content is
/// an on-screen judgement. See `docs/engine/overlay-multiply-decision.md`.
enum OverlayVeil {
    /// A **saturated, low-luminance** amber (sRGB). Source-over lifts blacks to `tint·alpha`, so a
    /// low-luma amber keeps blacks darker — and reads as *amber* rather than a desaturated warm
    /// "white" wash — for the same hue shift. Intensity is carried by `alpha`, NOT by this hue.
    static let tint = (red: 1.0, green: 0.45, blue: 0.0)
    /// Cap on veil opacity so even the warmest setting stays a legible tint, never an opaque wash.
    static let maxAlpha = 0.5
}

/// The veil's opacity for a target gain (pure, testable). **0 at neutral** so the veil fully
/// vanishes when warmth is off (a non-zero alpha at 6500K would tint an "off" screen); rises with
/// warmth — the red-minus-blue attenuation — and is capped so it stays a legible tint.
package func veilAlpha(for gain: RGBGain) -> Double {
    let warmth = max(0, gain.red - gain.blue)
    return min(OverlayVeil.maxAlpha, warmth)
}

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
/// ## Compositing model — alpha-over warm tint (§18 RESOLVED: a true multiply is impossible here)
/// Warming is an **alpha-blended warm tint**: a saturated low-luminance amber layer composited
/// *over* the screen by the window server (standard source-over), opacity scaled by warmth. We do
/// NOT use a CALayer `compositingFilter` multiply: it blends a layer only against other content
/// **inside the same window's layer tree**, and the window server then composites this standalone
/// transparent panel over the apps/desktop behind it using the **resulting alpha only** — so a
/// multiply filter has nothing behind-window to act on (Apple DTS, forums 133177).
///
/// §18 RESOLVED (2026-06-17, see `docs/engine/overlay-multiply-decision.md`): a *true* per-channel
/// multiply (blacks-stay-black, blue actually removed from the signal) is **not achievable via a
/// permissionless public overlay**. The only true-multiply paths are framebuffer capture (needs
/// Screen Recording — rejected: breaks the no-permission promise) or the LUT — so **true warming
/// lives in the DDC (`HardwareDDC`) and gamma (`GammaBackend`) layers**, and the overlay is
/// deliberately an alpha tint. Source-over can only *lift* a black pixel toward the tint
/// (`dst·(1−a) + tint·a`), never `dst·k` — so the overlay washes amber over the image rather than
/// removing blue from it. The tint is tuned (`OverlayVeil`: saturated amber + gated alpha) to get
/// the most warmth per unit of black-lift, but it is the universal *fallback floor*, not the way
/// the product truly warms.
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

    /// Translate a per-channel RGB gain into the alpha-tint veil: a fixed saturated amber (the
    /// hue), with opacity from `veilAlpha(for:)` (the warmth). This is the alpha-tint FALLBACK
    /// (see the `OverlayBackend` header / `docs/engine/overlay-multiply-decision.md`): it washes
    /// amber over the screen rather than removing blue from the signal — a true warm comes from
    /// the DDC / gamma layers, not the overlay.
    private static func veil(for gain: RGBGain) -> (CGColor, Double) {
        let alpha = veilAlpha(for: gain)
        let color = CGColor(
            srgbRed: OverlayVeil.tint.red,
            green: OverlayVeil.tint.green,
            blue: OverlayVeil.tint.blue,
            alpha: 1.0
        )
        return (color, alpha)
    }
}

#endif
