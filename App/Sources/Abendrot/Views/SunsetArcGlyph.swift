import SwiftUI
import AppKit

// MARK: - SunsetArcGlyph
//
// The brand mark, "One Ripple (minimal nod)" — a half-sun dome cresting a horizon with a single
// reflection ripple below it on the water, echoing the app icon's sun-on-water reflection reduced to
// its most legible element (chosen 2026-06-20 from the menu-bar icon lab; geometry mirrors
// brand/explorations/menubar-appicon-lab.html, id `appicon-1ripple`).
//
// Drawn on a 24-unit grid: dome center (12,12) radius 6.5, horizon at y=12 (x 4→20), one ripple at
// y=16.5 (x 8.5→15.5), stroke 2.8u, round caps. Canvas is y-DOWN (SwiftUI), so smaller y = higher.
struct SunsetArcGlyph: View {
    var tint: Color = Theme.Color.accent
    var horizon: Color = Theme.Color.accentHighlight
    /// `true` renders the lit/active sun (solid half-disc); `false` the resting hollow outline.
    var filled: Bool = true

    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height) / 24
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
            let lw = max(1.0, 2.8 * s)

            // Half-sun dome — upper semicircle (same arc convention as the prior provisional glyph).
            var dome = Path()
            dome.addArc(center: p(12, 12), radius: 6.5 * s,
                        startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
            if filled {
                dome.closeSubpath()                       // chord along the horizon → solid half-disc
                context.fill(dome, with: .color(tint))
            } else {
                context.stroke(dome, with: .color(tint),
                               style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))
            }

            // Horizon line + the single reflection ripple below it.
            var lines = Path()
            lines.move(to: p(4, 12));   lines.addLine(to: p(20, 12))
            lines.move(to: p(8.5, 16.5)); lines.addLine(to: p(15.5, 16.5))
            context.stroke(lines, with: .color(horizon),
                           style: StrokeStyle(lineWidth: lw, lineCap: .round))
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Menu-bar status-item glyph
//
// The single most-seen surface. Resting = the original shipped sunset glyph (a filled half-sun on a
// horizon). Warming keeps the EXACT same shape and same width — it just adds ember-amber + a soft glow
// + one reflection ripple on the water below (founder pick, 2026-06-21; same-width states → no jump).
//   • `template()` — resting/inactive. MONOCHROME template; `isTemplate = true` is CRITICAL (plan §6.5):
//     macOS tints it to match light/dark bars. Without it the icon vanishes on light bars.
//   • `active()`   — warming on. Identical sun + horizon, now ember-amber with a soft glow and the
//     reflection ripple added. Non-template so the amber/glow survive the menu bar's auto-tinting.
// `AbendrotApp` swaps between them on `AppModel.isWarmingActive`.
enum MenuBarGlyph {
    /// Inactive (resting) glyph: the filled half-sun + horizon, as a tintable template image.
    static func template(pointSize: CGFloat = 18) -> NSImage {
        let image = draw(pointSize: pointSize, color: .black, withRipple: false, glow: false)
        image.isTemplate = true   // CRITICAL — adapts to the menu bar; see note above.
        return image
    }

    /// Active (warming) glyph: identical shape/width, ember-amber + soft glow + the reflection ripple.
    static func active(pointSize: CGFloat = 18) -> NSImage {
        // ponytail: one amber (--accent #FD9228) that reads on both light & dark bars; deepen
        // per-appearance only if it ever looks washed-out on a light bar.
        let amber = NSColor(srgbRed: 253 / 255, green: 146 / 255, blue: 40 / 255, alpha: 1)
        let image = draw(pointSize: pointSize, color: amber, withRipple: true, glow: true)
        image.isTemplate = false
        return image
    }

    /// Shared drawing on a 24-unit grid. `flipped: false` → y-UP AppKit space, so the upper dome is the
    /// 0°→180° arc. Matches the original shipped geometry: horizon at 0.40·h (y=9.6), sun radius 0.30·w
    /// (7.2), line 0.08·w (1.92). The ripple (active only) sits below the horizon; both states share the
    /// identical sun + horizon footprint, so the icon never resizes between states.
    private static func draw(pointSize: CGFloat, color: NSColor, withRipple: Bool, glow: Bool) -> NSImage {
        NSImage(size: NSSize(width: pointSize, height: pointSize), flipped: false) { rect in
            let s = rect.width / 24.0
            func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * s, y: y * s) }
            let horizonY: CGFloat = 9.6
            let lw = 1.92 * s

            NSGraphicsContext.current?.saveGraphicsState()
            if glow {
                let shadow = NSShadow()
                shadow.shadowColor = color.withAlphaComponent(0.85)
                shadow.shadowBlurRadius = 2.6 * s
                shadow.shadowOffset = .zero
                shadow.set()
            }
            color.set()

            // Filled half-sun dome — center (12, 9.6), radius 7.2, upper semicircle.
            let dome = NSBezierPath()
            dome.appendArc(withCenter: p(12, horizonY), radius: 7.2 * s, startAngle: 0, endAngle: 180)
            dome.close()        // chord along the horizon → solid half-disc
            dome.fill()

            // Horizon line, plus the reflection ripple below it when active.
            var segments: [(NSPoint, NSPoint)] = [(p(2.88, horizonY), p(21.12, horizonY))]
            if withRipple { segments.append((p(8.5, 5.5), p(15.5, 5.5))) }
            for (a, b) in segments {
                let line = NSBezierPath()
                line.lineWidth = lw
                line.lineCapStyle = .round
                line.move(to: a)
                line.line(to: b)
                line.stroke()
            }
            NSGraphicsContext.current?.restoreGraphicsState()
            return true
        }
    }
}

#Preview("Sunset arc glyph — lit") {
    SunsetArcGlyph()
        .frame(width: 64, height: 64)
        .padding(40)
        .background(Theme.Color.groundIndigo)
}

#Preview("Sunset arc glyph — resting") {
    SunsetArcGlyph(filled: false)
        .frame(width: 64, height: 64)
        .padding(40)
        .background(Theme.Color.groundIndigo)
}
