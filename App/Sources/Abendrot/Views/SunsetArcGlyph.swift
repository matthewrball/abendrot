import SwiftUI
import AppKit

// MARK: - SunsetArcGlyph
//
// PROVISIONAL placeholder glyph — a half-sun arc rising on a horizon line, mirroring
// the SVG in brand/explorations/components.html. The REAL icon is deferred to the
// brand-lock pass; this is a clear,
// non-faked stand-in so the structure reads.
struct SunsetArcGlyph: View {
    var tint: Color = Theme.Color.accent
    var horizon: Color = Theme.Color.accentHighlight

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let horizonY = h * 0.62
            let radius = w * 0.30

            // Half-sun arc sitting on the horizon.
            var sun = Path()
            sun.addArc(
                center: CGPoint(x: w / 2, y: horizonY),
                radius: radius,
                startAngle: .degrees(180),
                endAngle: .degrees(360),
                clockwise: false
            )
            sun.closeSubpath()
            context.fill(sun, with: .color(tint))

            // Horizon line.
            var line = Path()
            line.move(to: CGPoint(x: w * 0.12, y: horizonY))
            line.addLine(to: CGPoint(x: w * 0.88, y: horizonY))
            context.stroke(line, with: .color(horizon), style: StrokeStyle(lineWidth: max(1.4, w * 0.08), lineCap: .round))
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Menu-bar template image
//
// The status-item glyph. `isTemplate = true` is CRITICAL:
// without it the icon is invisible in light menu bars. macOS tints template images to
// match the bar; the "glows amber when active" treatment is deferred to
// brand-lock — TODO: swap a vibrant template + amber active state then.
enum MenuBarGlyph {
    /// A small sunset-arc template image rendered programmatically (provisional).
    static func image(pointSize: CGFloat = 18) -> NSImage {
        let size = NSSize(width: pointSize, height: pointSize)
        let image = NSImage(size: size, flipped: false) { rect in
            let w = rect.width
            let h = rect.height
            let horizonY = h * 0.40
            let radius = w * 0.30

            NSColor.black.setFill()
            let sun = NSBezierPath()
            sun.appendArc(
                withCenter: NSPoint(x: w / 2, y: horizonY),
                radius: radius,
                startAngle: 0,
                endAngle: 180
            )
            sun.close()
            sun.fill()

            let line = NSBezierPath()
            line.lineWidth = max(1.2, w * 0.08)
            line.lineCapStyle = .round
            line.move(to: NSPoint(x: w * 0.12, y: horizonY))
            line.line(to: NSPoint(x: w * 0.88, y: horizonY))
            NSColor.black.setStroke()
            line.stroke()

            return true
        }
        image.isTemplate = true   // CRITICAL — see note above.
        return image
    }
}

#Preview("Sunset arc glyph") {
    SunsetArcGlyph()
        .frame(width: 64, height: 64)
        .padding(40)
        .background(Theme.Color.groundIndigo)
}
