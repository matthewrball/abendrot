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
        /// The corner radius of the visible surface, as WindowServer or this app reports it. Nil,
        /// zero, or a value that is not finite means unknown.
        public var cornerRadius: CGFloat?
        /// Owned by Stage Manager (`com.apple.WindowManager`), which lists a window of its own at
        /// the bounds of each thumbnail in its strip.
        public var isStageManager: Bool

        public init(
            bounds: CGRect,
            layer: Int,
            owner: Int32,
            alpha: Double = 1,
            isRegularApp: Bool = true,
            isMeasured: Bool = false,
            cornerRadius: CGFloat? = nil,
            isStageManager: Bool = false
        ) {
            self.bounds = bounds
            self.layer = layer
            self.owner = owner
            self.alpha = alpha
            self.isRegularApp = isRegularApp
            self.isMeasured = isMeasured
            self.cornerRadius = cornerRadius
            self.isStageManager = isStageManager
        }

        /// `cornerRadius` when it is a usable radius.
        var knownCornerRadius: CGFloat? {
            guard let cornerRadius, cornerRadius.isFinite, cornerRadius > 0 else { return nil }
            return cornerRadius
        }
    }

    /// `kCGPopUpMenuWindowLevel`: menus, context menus, and menu-bar extra windows. On some Macs
    /// the window is the menu. On others it carries a wide transparent margin on every side, and
    /// the window list reports nothing that tells the two apart. See `observedMenuMargin`.
    public static let popUpMenuLayer = Int(CGWindowLevelForKey(.popUpMenuWindow))

    /// `kCGMainMenuWindowLevel`: the menu bar, one window per display that shows it.
    public static let mainMenuLayer = Int(CGWindowLevelForKey(.mainMenuWindow))

    /// `kCGStatusWindowLevel`: menu-bar extras and the popovers they open.
    public static let statusLayer = Int(CGWindowLevelForKey(.statusWindow))

    /// How far an `NSPopover`'s window reaches past the popover on every side: room for the arrow
    /// and the shadow. WindowServer lists the whole window. Measured on macOS 26.7 (a 340 x 400 pt
    /// popover in a 366 x 426 pt window) and matching the reporter's macOS 27.2 screenshot.
    static let popoverMargin: CGFloat = 13
    /// The radius of the popover's glass on macOS 26, which this app reads from its own popover.
    /// The window reports none.
    static let popoverCornerRadius: CGFloat = 20
    /// A menu-bar extra's popover window starts this far above the bottom of the menu bar: 28 pt
    /// under a 33 pt bar, for this app's popover on macOS 26.6 and SoloFan's on the reporter's 27.2.
    static let popoverOverlapsMenuBar: CGFloat = 5
    /// How far from that line a popover window's top may sit.
    static let popoverTopSlack: CGFloat = 1.5

    /// A menu opens this far below the menu bar.
    static let menuGapBelowMenuBar: CGFloat = 1
    /// How far a menu's top may sit from that line and still count as hanging from the menu bar.
    static let menuAttachSlack: CGFloat = 2
    /// The smallest menu a padded menu window can hold.
    static let minMenuBody: CGFloat = 16

    /// The corner radius of the menu inside a padded menu window. WindowServer reports the
    /// window's radius, which is 0 there: the menu is drawn inside a larger transparent window.
    /// Without this the hole fell back to the titled-window radius (16 pt), leaving a warm sliver
    /// inside an excluded app's menu corners and a warm square outside another app's menu.
    /// Measured on macOS 27.2: a circle fitted to the drawn corner of three menus in the
    /// reporter's screenshots gave 13.0 pt each. Only padded menus use it.
    static let paddedMenuCornerRadius: CGFloat = 13

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
    /// Each window is cut at its own `cornerRadius` when one is known, so the square outside the
    /// curve keeps the colour of what is behind it: warm around a neutral window, neutral around a
    /// warm menu or popover in front of one. `cornerRadius` is the fallback for a neutral window
    /// whose radius is unknown (a titled window's). A warm window with no known radius is cut
    /// square. A menu inside a padded window with no known radius takes `paddedMenuCornerRadius`.
    /// A window that fills the display is square: its corners are the screen's corners.
    /// A menu-bar extra's popover counts at the popover, not its window, and stays warm like a menu
    /// when its app is not excluded. Only with `reportsCornerRadii`, true where WindowServer reports
    /// window radii: elsewhere every radius is unknown, and status-level windows keep the old rules.
    /// The excluded app's thumbnail in the Stage Manager strip is not a hole: it is drawn tilted,
    /// so a rectangle at its bounds misses its corners and shows the wallpaper beside it neutral.
    public static func neutralRegion(
        windows: [Window],
        owner: Int32,
        display: CGRect,
        cornerRadius: CGFloat = 0,
        floatingOwners: Set<Int32> = [],
        menuMargin: CGFloat = 0,
        reportsCornerRadii: Bool = false
    ) -> [CGRect] {
        var region: [CGRect] = []
        var occluders: [Occluder] = []
        let shadows = shadowFrames(in: windows, display: display)
        let menuBar = menuBar(in: windows, display: display)
        let menuOwners = ownersWithMenuBarMenu(in: windows, menuBar: menuBar, menuMargin: menuMargin)
        let thumbnails = stageThumbnailFrames(in: windows)
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
            if neutral, window.layer == 0, isStageThumbnail(window, frames: thumbnails) { continue }
            var bounds = window.bounds
            var reportedRadius = window.knownCornerRadius
            if window.layer == popUpMenuLayer, !window.isMeasured {
                // Another accessory app's window is trusted as a menu only while that app has a
                // menu hanging from the menu bar. The volume control has other margins.
                let isMenu = neutral || window.isRegularApp || menuOwners.contains(window.owner)
                guard isMenu, let body = menuBody(of: window.bounds, menuMargin: menuMargin) else { continue }
                if body != window.bounds, reportedRadius == nil { reportedRadius = paddedMenuCornerRadius }
                bounds = body
            }
            // Only where WindowServer reports radii (macOS 26 and later) is a missing radius a sign of
            // a popover, and only there were its margin and radius measured.
            let popover = reportsCornerRadii && window.layer == statusLayer && !window.isMeasured
                && reportedRadius == nil
                ? popoverBody(of: window, in: windows, menuBar: menuBar) : nil
            if let popover {
                bounds = popover
                reportedRadius = popoverCornerRadius
            }
            if neutral {
                let radius = covers ? 0 : (reportedRadius ?? cornerRadius)
                for piece in roundedInterior(bounds, radius: radius) {
                    let clipped = piece.intersection(display)
                    if !clipped.isNull, !clipped.isEmpty {
                        region += subtract(occluders, from: clipped)
                    }
                }
                continue
            }
            if popover != nil || countsAsOccluder(window, display: display) {
                let radius = covers ? 0 : (reportedRadius ?? 0)
                occluders.append(Occluder(bounds: bounds, radius: radius))
            }
        }
        return region
    }

    // MARK: Stage Manager

    /// Bounds of Stage Manager's own normal-level windows: one per thumbnail in its strip.
    private static func stageThumbnailFrames(in windows: [Window]) -> [CGRect] {
        windows.filter { $0.isStageManager && $0.layer == 0 && $0.alpha > 0.01 && !$0.bounds.isEmpty }
            .map(\.bounds)
    }

    /// An app window that Stage Manager is showing as a thumbnail in its strip: it lists the app's
    /// window at the thumbnail's bounds, and a window of its own at the same bounds. A window on
    /// the stage has no such twin.
    private static func isStageThumbnail(_ window: Window, frames: [CGRect]) -> Bool {
        guard !window.isStageManager else { return false }
        let bounds = window.bounds
        return frames.contains { frame in
            abs(frame.minX - bounds.minX) <= 1 && abs(frame.minY - bounds.minY) <= 1
                && abs(frame.width - bounds.width) <= 1 && abs(frame.height - bounds.height) <= 1
        }
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

    /// The popover inside a menu-bar extra's popover window: a status-level window whose top sits
    /// where a popover's arrow puts it, `popoverOverlapsMenuBar` above the bottom of the menu bar,
    /// under a status item. Nil for anything else, or with no menu bar listed. The item may belong
    /// to any process: on macOS 26 Control Center owns every app's status item. A notch tool's
    /// panel at the top edge or just under the bar, and a strip with no item above it, are not
    /// popovers.
    private static func popoverBody(of window: Window, in windows: [Window], menuBar: CGRect?) -> CGRect? {
        let bounds = window.bounds
        guard let menuBar,
              abs(bounds.minY - (menuBar.maxY - popoverOverlapsMenuBar)) <= popoverTopSlack,
              bounds.width >= 2 * popoverMargin + minMenuBody,
              bounds.height >= 2 * popoverMargin + minMenuBody else { return nil }
        let body = bounds.insetBy(dx: popoverMargin, dy: popoverMargin)
        let hasItem = windows.contains { item in
            item.layer == statusLayer && item.alpha > 0.01 && !item.bounds.isEmpty
                && item.bounds.minY >= menuBar.minY - 1 && item.bounds.maxY <= menuBar.maxY + 1
                && item.bounds.minX >= menuBar.minX - 1 && item.bounds.maxX <= menuBar.maxX + 1
                && item.bounds.midX >= body.minX && item.bounds.midX <= body.maxX
        }
        return hasItem ? body : nil
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
        let r = clampedRadius(radius, in: rect)
        guard r >= 1 else { return [rect] }
        var pieces = [
            CGRect(x: rect.minX + r, y: rect.minY, width: rect.width - 2 * r, height: rect.height),
            CGRect(x: rect.minX, y: rect.minY + r, width: r, height: rect.height - 2 * r),
            CGRect(x: rect.maxX - r, y: rect.minY + r, width: r, height: rect.height - 2 * r),
        ]
        for row in cornerRows(r) where r - row.inset > 0 {
            let width = r - row.inset
            let height = row.y1 - row.y0
            pieces.append(CGRect(x: rect.minX + row.inset, y: rect.minY + row.y0, width: width, height: height))
            pieces.append(CGRect(x: rect.maxX - r, y: rect.minY + row.y0, width: width, height: height))
            pieces.append(CGRect(x: rect.minX + row.inset, y: rect.maxY - row.y1, width: width, height: height))
            pieces.append(CGRect(x: rect.maxX - r, y: rect.maxY - row.y1, width: width, height: height))
        }
        return pieces
    }

    /// The parts of `rect` outside its rounded corners: what `roundedInterior` leaves out, row for
    /// row, less the rows narrower than `minExteriorWidth`. Those slivers cannot be seen and would
    /// each cost a warm tile; they count as inside. Empty for a square rect.
    static func roundedExterior(_ rect: CGRect, radius: CGFloat) -> [CGRect] {
        let r = clampedRadius(radius, in: rect)
        guard r >= 1 else { return [] }
        var pieces: [CGRect] = []
        for row in cornerRows(r) where row.inset >= minExteriorWidth {
            let height = row.y1 - row.y0
            pieces.append(CGRect(x: rect.minX, y: rect.minY + row.y0, width: row.inset, height: height))
            pieces.append(CGRect(x: rect.maxX - row.inset, y: rect.minY + row.y0, width: row.inset, height: height))
            pieces.append(CGRect(x: rect.minX, y: rect.maxY - row.y1, width: row.inset, height: height))
            pieces.append(CGRect(x: rect.maxX - row.inset, y: rect.maxY - row.y1, width: row.inset, height: height))
        }
        return pieces
    }

    /// The narrowest part outside a corner that a warm window in front gives back to the hole.
    static let minExteriorWidth: CGFloat = 0.25

    private static func clampedRadius(_ radius: CGFloat, in rect: CGRect) -> CGFloat {
        guard radius.isFinite else { return 0 }
        return min(max(0, radius), min(rect.width, rect.height) / 2)
    }

    /// The 1 pt rows of a corner square, from the outer edge in, with how far the curve sits in
    /// from the side at each row's middle. A row whose inside part would be under 0.2 pt is left
    /// wholly outside. The interior and the exterior both read these rows, so they tile exactly.
    private static func cornerRows(_ r: CGFloat) -> [(y0: CGFloat, y1: CGFloat, inset: CGFloat)] {
        (0..<Int(r.rounded(.up))).map { step in
            let y0 = CGFloat(step)
            let y1 = min(CGFloat(step + 1), r)
            let dy = r - (y0 + y1) / 2
            let inset = r - (r * r - dy * dy).squareRoot()
            return (y0, y1, r - inset > 0.2 ? inset : r)
        }
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

        // Sweep down the bands, keeping only the holes that span the current one.
        let byTop = holes.sorted { $0.minY < $1.minY }
        var nextHole = 0
        var active: [CGRect] = []

        for (top, bottom) in zip(ys, ys.dropFirst()) where bottom > top {
            let mid = (top + bottom) / 2
            while nextHole < byTop.count, byTop[nextHole].minY <= mid {
                active.append(byTop[nextHole])
                nextHole += 1
            }
            active.removeAll { $0.maxY <= mid }
            let spans = active
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

    /// A warm window in front of the excluded one: its bounds, minus the parts outside its
    /// rounded corners, which keep showing what is behind it. Those parts are built the first time
    /// the occluder touches a piece of the hole.
    private final class Occluder {
        let bounds: CGRect
        private let radius: CGFloat
        private var corners: [CGRect]?

        init(bounds: CGRect, radius: CGFloat) {
            self.bounds = bounds
            self.radius = radius
        }

        var outsideCorners: [CGRect] {
            if let corners { return corners }
            let built = WindowHolePolicy.roundedExterior(bounds, radius: radius)
            corners = built
            return built
        }
    }

    /// `rect` minus every occluder, as non-overlapping pieces. Each piece loses the occluder's
    /// bounds and gets back what lies outside its corners, so a rounded occluder costs a few
    /// intersections rather than one cut per corner row.
    private static func subtract(_ occluders: [Occluder], from rect: CGRect) -> [CGRect] {
        var pieces = [rect]
        for occluder in occluders where occluder.bounds.intersects(rect) {
            pieces = pieces.flatMap { piece -> [CGRect] in
                guard piece.intersects(occluder.bounds) else { return [piece] }
                var kept = subtract([occluder.bounds], from: [piece])
                for corner in occluder.outsideCorners {
                    let overlap = piece.intersection(corner)
                    if !overlap.isNull, !overlap.isEmpty { kept.append(overlap) }
                }
                return kept
            }
        }
        return pieces
    }

    /// `pieces` minus every rectangle in `cuts`, as non-overlapping pieces.
    private static func subtract(_ cuts: [CGRect], from rects: [CGRect]) -> [CGRect] {
        var pieces = rects
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
