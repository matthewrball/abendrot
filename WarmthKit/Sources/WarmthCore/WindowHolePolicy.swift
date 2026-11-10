import Foundation
import CoreGraphics

// MARK: - WindowHolePolicy

/// Pure geometry for keeping one app's windows neutral while the rest of a display stays warm.
///
/// All rectangles share the CoreGraphics global space that `kCGWindowBounds` and
/// `CGDisplayBounds` report in: top-left origin, y grows downward.
public enum WindowHolePolicy {

    /// One on-screen window, front to back as `CGWindowListCopyWindowInfo` lists them.
    public struct Window: Equatable, Sendable {
        public var bounds: CGRect
        public var layer: Int
        public var owner: Int32
        public var alpha: Double
        /// A normal dock app. Accessory overlays at layer 0 (Cua Driver covers a whole display)
        /// are invisible and must not hide the excluded window.
        public var isRegularApp: Bool

        public init(bounds: CGRect, layer: Int, owner: Int32, alpha: Double = 1, isRegularApp: Bool = true) {
            self.bounds = bounds
            self.layer = layer
            self.owner = owner
            self.alpha = alpha
            self.isRegularApp = isRegularApp
        }
    }

    /// The parts of `owner`'s normal windows on `display` that are actually visible: each window
    /// minus every window listed in front of it. Menus, popovers, the Dock and other apps' windows
    /// in front stay warm. Overlays that are invisible or span the whole display are ignored.
    public static func neutralRegion(
        windows: [Window],
        owner: Int32,
        display: CGRect
    ) -> [CGRect] {
        var region: [CGRect] = []
        var occluders: [CGRect] = []
        for window in windows {
            guard window.alpha > 0.01, !window.bounds.isEmpty else { continue }
            // Desktop-level windows sit behind everything.
            guard window.layer >= 0 else { continue }
            if window.owner == owner, window.layer == 0 {
                let clipped = window.bounds.intersection(display)
                if !clipped.isNull, !clipped.isEmpty {
                    region += subtract(occluders, from: clipped)
                }
                continue
            }
            if countsAsOccluder(window, display: display) {
                occluders.append(window.bounds)
            }
        }
        return region
    }

    /// `display` minus `region`, as non-overlapping tiles. Horizontal bands are cut at every
    /// region edge; tiles with the same columns in neighbouring bands are merged.
    public static func warmTiles(around region: [CGRect], in display: CGRect) -> [CGRect] {
        let holes = region.compactMap { rect -> CGRect? in
            let clipped = rect.intersection(display)
            return clipped.isNull || clipped.isEmpty ? nil : clipped
        }
        guard !holes.isEmpty else { return [display] }

        var edges = Set([display.minY, display.maxY])
        for hole in holes {
            edges.insert(hole.minY)
            edges.insert(hole.maxY)
        }
        let ys = edges.sorted()
        var tiles: [CGRect] = []
        var open: [CGFloat: (minX: CGFloat, maxX: CGFloat, minY: CGFloat)] = [:]

        for (top, bottom) in zip(ys, ys.dropFirst()) where bottom > top {
            let mid = (top + bottom) / 2
            let spans = holes
                .filter { $0.minY <= mid && $0.maxY > mid }
                .map { ($0.minX, $0.maxX) }
                .sorted { $0.0 < $1.0 }
            var gaps: [(CGFloat, CGFloat)] = []
            var cursor = display.minX
            for (minX, maxX) in spans {
                if minX > cursor { gaps.append((cursor, minX)) }
                cursor = max(cursor, maxX)
            }
            if cursor < display.maxX { gaps.append((cursor, display.maxX)) }

            var next: [CGFloat: (minX: CGFloat, maxX: CGFloat, minY: CGFloat)] = [:]
            for (minX, maxX) in gaps {
                if let running = open[minX], running.maxX == maxX {
                    next[minX] = running
                } else {
                    next[minX] = (minX, maxX, top)
                }
            }
            for (key, running) in open where next[key].map({ $0 != running }) ?? true {
                tiles.append(CGRect(x: running.minX, y: running.minY,
                                    width: running.maxX - running.minX, height: top - running.minY))
            }
            open = next
        }
        for running in open.values {
            tiles.append(CGRect(x: running.minX, y: running.minY,
                                width: running.maxX - running.minX, height: display.maxY - running.minY))
        }
        return tiles.sorted { ($0.minY, $0.minX) < ($1.minY, $1.minX) }
    }

    /// A window in front of the excluded app that should stay warm.
    private static func countsAsOccluder(_ window: Window, display: CGRect) -> Bool {
        if window.layer == 0 { return window.isRegularApp }
        // A non-normal window that spans the whole display is a transparent overlay (dimmers,
        // notch tools, this app's own panels), not something a person reads.
        return !PausePolicy.coversDisplay(window: window.bounds, display: display)
    }

    /// `rect` minus every rectangle in `cuts`, as non-overlapping pieces.
    private static func subtract(_ cuts: [CGRect], from rect: CGRect) -> [CGRect] {
        var pieces = [rect]
        for cut in cuts {
            pieces = pieces.flatMap { piece -> [CGRect] in
                let overlap = piece.intersection(cut)
                guard !overlap.isNull, !overlap.isEmpty else { return [piece] }
                var out: [CGRect] = []
                if overlap.minY > piece.minY {
                    out.append(CGRect(x: piece.minX, y: piece.minY, width: piece.width, height: overlap.minY - piece.minY))
                }
                if overlap.maxY < piece.maxY {
                    out.append(CGRect(x: piece.minX, y: overlap.maxY, width: piece.width, height: piece.maxY - overlap.maxY))
                }
                if overlap.minX > piece.minX {
                    out.append(CGRect(x: piece.minX, y: overlap.minY, width: overlap.minX - piece.minX, height: overlap.height))
                }
                if overlap.maxX < piece.maxX {
                    out.append(CGRect(x: overlap.maxX, y: overlap.minY, width: piece.maxX - overlap.maxX, height: overlap.height))
                }
                return out
            }
        }
        return pieces
    }
}
