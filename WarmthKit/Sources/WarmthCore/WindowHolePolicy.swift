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
        /// `bounds` is the visible surface, measured by the caller, not the window's shadow frame.
        /// This app's own popover and windows are measured this way and always stay warm.
        public var isMeasured: Bool

        public init(
            bounds: CGRect,
            layer: Int,
            owner: Int32,
            alpha: Double = 1,
            isRegularApp: Bool = true,
            isMeasured: Bool = false
        ) {
            self.bounds = bounds
            self.layer = layer
            self.owner = owner
            self.alpha = alpha
            self.isRegularApp = isRegularApp
            self.isMeasured = isMeasured
        }
    }

    /// `kCGPopUpMenuWindowLevel`: menus, context menus, and menu-bar extra windows. On some Macs
    /// the window is the menu. On others it carries a wide transparent margin on every side, and
    /// the window list reports nothing that tells the two apart. See `observedMenuMargin`.
    public static let popUpMenuLayer = Int(CGWindowLevelForKey(.popUpMenuWindow))

    /// `kCGMainMenuWindowLevel`: the menu bar, one window per display that shows it.
    public static let mainMenuLayer = Int(CGWindowLevelForKey(.mainMenuWindow))

    /// A menu opens this far below the menu bar.
    static let menuGapBelowMenuBar: CGFloat = 1
    /// How far a menu's top may sit from that line and still count as hanging from the menu bar.
    static let menuAttachSlack: CGFloat = 2
    /// The smallest menu a padded menu window can hold.
    static let minMenuBody: CGFloat = 16

    /// The widest shadow margin a window may add around another window of the same app.
    static let maxShadowMargin: CGFloat = 128

    /// The parts of `owner`'s windows on `display` that are actually visible: each window
    /// minus every window listed in front of it. `floatingOwners` add only their floating
    /// windows, so picture in picture stays neutral after that app loses focus. A normal
    /// window of those owners stays warm. Other apps' menus and popovers stay warm, at their
    /// own bounds. The excluded app's menus are neutral, at their own bounds. A window that only
    /// frames another window of the same app with a shadow margin is ignored, so a menu's shadow
    /// is never a hole or a warm box. Desktop windows, including Finder's, are never a hole.
    /// Overlays that are invisible or span the whole display are ignored.
    /// `menuMargin` is the transparent margin of this Mac's menu windows, proven by
    /// `observedMenuMargin`. Menu-level windows count at their bounds inset by it. Zero, the
    /// default, means no margin has been proven: their bounds are then taken as the menu.
    /// `cornerRadius` follows a normal window's rounded corners, so the square outside the curve
    /// stays warm. A window that fills the display keeps a square hole: its corners are the
    /// screen's corners.
    public static func neutralRegion(
        windows: [Window],
        owner: Int32,
        display: CGRect,
        cornerRadius: CGFloat = 0,
        floatingOwners: Set<Int32> = [],
        menuMargin: CGFloat = 0
    ) -> [CGRect] {
        var region: [CGRect] = []
        var occluders: [CGRect] = []
        let shadows = shadowFrames(in: windows, display: display)
        let menuBar = menuBar(in: windows, display: display)
        let menuOwners = ownersWithMenuBarMenu(in: windows, menuBar: menuBar, menuMargin: menuMargin)
        for (index, window) in windows.enumerated() {
            guard window.alpha > 0.01, !window.bounds.isEmpty else { continue }
            // Desktop-level windows sit behind everything. Finder's desktop is one of them, so an
            // excluded Finder never turns the whole desktop neutral.
            guard window.layer >= 0 else { continue }
            guard !shadows.contains(index) else { continue }
            let covers = PausePolicy.coversDisplay(window: window.bounds, display: display)
            // Layer 0 is a normal window. A smaller window on another layer is picture in picture
            // or another floating window, not a full-screen overlay.
            let floating = window.layer > 0 && !covers
            let neutral = (window.owner == owner && (window.layer == 0 || floating))
                || (floating && floatingOwners.contains(window.owner))
            var bounds = window.bounds
            if window.layer == popUpMenuLayer, !window.isMeasured {
                // Another accessory app's window is trusted as a menu only while that app has a
                // menu hanging from the menu bar. The volume control has other margins.
                let isMenu = neutral || window.isRegularApp || menuOwners.contains(window.owner)
                guard isMenu, let body = menuBody(of: window.bounds, menuMargin: menuMargin) else { continue }
                bounds = body
            }
            if neutral {
                let radius = covers ? 0 : cornerRadius
                for piece in roundedInterior(bounds, radius: radius) {
                    let clipped = piece.intersection(display)
                    if !clipped.isNull, !clipped.isEmpty {
                        region += subtract(occluders, from: clipped)
                    }
                }
                continue
            }
            if countsAsOccluder(window, display: display) {
                occluders.append(bounds)
            }
        }
        return region
    }

    // MARK: Menu windows

    /// The transparent margin around this Mac's menus, when a listed window proves one. A menu
    /// opens right under the menu bar, so a menu-level window that starts above the display's top
    /// edge is padded by the distance to that line. Nil without such a window: a context menu, a
    /// menu that starts under the menu bar, or a display with no menu bar listed proves nothing.
    /// Only a regular app's window counts. Notch tools and system overlays are accessory apps and
    /// may sit above the top edge for other reasons.
    public static func observedMenuMargin(in windows: [Window], displays: [CGRect]) -> CGFloat? {
        var seen: CGFloat?
        for display in displays {
            guard let menuBar = menuBar(in: windows, display: display) else { continue }
            let menuTop = menuBar.maxY + menuGapBelowMenuBar
            for window in windows
            where window.layer == popUpMenuLayer && window.isRegularApp && !window.isMeasured {
                let bounds = window.bounds
                guard window.alpha > 0.01, bounds.midX >= display.minX, bounds.midX < display.maxX else { continue }
                let margin = menuTop - bounds.minY
                guard bounds.minY < display.minY, margin <= maxShadowMargin,
                      bounds.width >= 2 * margin + minMenuBody,
                      bounds.height >= 2 * margin + minMenuBody else { continue }
                seen = max(seen ?? 0, margin)
            }
        }
        return seen
    }

    /// The menu inside a menu-level window. Nil when the window is too small to hold a padded menu.
    private static func menuBody(of bounds: CGRect, menuMargin: CGFloat) -> CGRect? {
        guard menuMargin > 0 else { return bounds }
        guard bounds.width > 2 * menuMargin, bounds.height > 2 * menuMargin else { return nil }
        return bounds.insetBy(dx: menuMargin, dy: menuMargin)
    }

    /// Accessory apps whose menu-level windows are menus. Without a proven margin every owner
    /// counts, at its bounds. With one, only an owner with a menu hanging from the menu bar
    /// counts; its other menu-level windows are submenus. With no menu bar listed none counts, so
    /// such a window cuts no warm box.
    private static func ownersWithMenuBarMenu(
        in windows: [Window],
        menuBar: CGRect?,
        menuMargin: CGFloat
    ) -> Set<Int32> {
        let menus = windows.filter { $0.layer == popUpMenuLayer && !$0.isMeasured && $0.alpha > 0.01 }
        guard menuMargin > 0 else { return Set(menus.map(\.owner)) }
        guard let menuBar else { return [] }
        let windowTop = menuBar.maxY + menuGapBelowMenuBar - menuMargin
        return Set(menus.filter { abs($0.bounds.minY - windowTop) <= menuAttachSlack }.map(\.owner))
    }

    /// The menu bar on `display`: a menu-bar-level strip across its top edge.
    private static func menuBar(in windows: [Window], display: CGRect) -> CGRect? {
        windows.first { window in
            let bounds = window.bounds
            return window.layer == mainMenuLayer && window.alpha > 0.01
                && abs(bounds.minX - display.minX) <= 1 && abs(bounds.minY - display.minY) <= 1
                && abs(bounds.width - display.width) <= 1
                && bounds.height >= 1 && bounds.height <= maxShadowMargin
        }?.bounds
    }

    /// The rounded-rect interior of `rect`, as 1 pt rows in the corners plus the straight middle.
    /// A circular arc matches the system corner closely enough that the square outside it stays warm.
    static func roundedInterior(_ rect: CGRect, radius: CGFloat) -> [CGRect] {
        let limit = min(rect.width, rect.height) / 2
        let r = min(max(0, radius), limit)
        guard r >= 1 else { return [rect] }
        var pieces = [
            CGRect(x: rect.minX + r, y: rect.minY, width: rect.width - 2 * r, height: rect.height),
            CGRect(x: rect.minX, y: rect.minY + r, width: r, height: rect.height - 2 * r),
            CGRect(x: rect.maxX - r, y: rect.minY + r, width: r, height: rect.height - 2 * r),
        ]
        let steps = Int(r.rounded(.up))
        for step in 0..<steps {
            let y0 = CGFloat(step)
            let y1 = min(CGFloat(step + 1), r)
            let dy = r - (y0 + y1) / 2
            let inside = (r * r - dy * dy).squareRoot()
            let inset = r - inside
            let width = r - inset
            guard width > 0.2, y1 > y0 else { continue }
            let height = y1 - y0
            pieces.append(CGRect(x: rect.minX + inset, y: rect.minY + y0, width: width, height: height))
            pieces.append(CGRect(x: rect.maxX - r, y: rect.minY + y0, width: width, height: height))
            pieces.append(CGRect(x: rect.minX + inset, y: rect.maxY - y1, width: width, height: height))
            pieces.append(CGRect(x: rect.maxX - r, y: rect.maxY - y1, width: width, height: height))
        }
        return pieces
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
        if window.layer == 0, window.isRegularApp { return true }
        // A non-normal window that spans the whole display is a transparent overlay (dimmers,
        // notch tools, this app's own panels), not something a person reads.
        if window.layer != 0, PausePolicy.coversDisplay(window: window.bounds, display: display) { return false }
        // This app's own popover and windows, measured without their shadow.
        if window.isMeasured || window.isRegularApp { return true }
        // A menu of a menu-bar app or of the system. Its bounds are the menu.
        // The cursor, the volume HUD, and accessory overlays are not regular apps and are not
        // menus. Their shadow bounds must not cut a warm rectangle out of the excluded window.
        return window.layer == popUpMenuLayer
    }

    /// Indices of windows that only frame another window of the same app on the same layer, with a
    /// shadow margin on every side and the same margin left and right. Such a window draws the
    /// shadow of the one inside it; the window inside is what a person sees.
    // Accepted risk: a real floating window that encloses a smaller window of the same app on the
    // same layer with even margins is also skipped. Window-list metadata alone can't tell the two
    // apart without Screen Recording, which this mode avoids.
    static func shadowFrames(in windows: [Window], display: CGRect) -> Set<Int> {
        var frames: Set<Int> = []
        for (index, outer) in windows.enumerated() {
            guard outer.layer > 0, outer.alpha > 0.01, !outer.isMeasured,
                  !PausePolicy.coversDisplay(window: outer.bounds, display: display) else { continue }
            let framesAnother = windows.indices.contains { other in
                guard other != index else { return false }
                let inner = windows[other]
                guard inner.owner == outer.owner, inner.layer == outer.layer,
                      inner.alpha > 0.01, !inner.bounds.isEmpty else { return false }
                return isShadowMargin(around: inner.bounds, in: outer.bounds)
            }
            if framesAnother { frames.insert(index) }
        }
        return frames
    }

    private static func isShadowMargin(around inner: CGRect, in outer: CGRect) -> Bool {
        let left = inner.minX - outer.minX
        let right = outer.maxX - inner.maxX
        let top = inner.minY - outer.minY
        let bottom = outer.maxY - inner.maxY
        let margins = [left, right, top, bottom]
        // A shadow can sit lower than the window, never off to one side.
        return margins.allSatisfy { $0 >= 1 && $0 <= maxShadowMargin } && abs(left - right) <= 4
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

// MARK: - Excluded window filter

/// The engine keeps picture in picture neutral after focus leaves without listing windows
/// itself. Only the window-filter backend conforms; other layers ignore this.
package protocol ExcludedWindowFilter: AnyObject, Sendable {
    func setExcludedApps(_ bundleIDs: Set<String>) async
    func displaysWithExcludedFloatingWindows() async -> Set<CGDirectDisplayID>
    func setOnFloatingWindowsChanged(_ handler: (@Sendable () -> Void)?) async
}
