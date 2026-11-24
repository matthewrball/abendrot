import Testing
import Foundation
import CoreGraphics
@testable import WarmthCore

@Suite("Window hole geometry")
struct WindowHolePolicyTests {
    private let display = CGRect(x: 0, y: 0, width: 1512, height: 982)

    private func area(_ rects: [CGRect]) -> CGFloat {
        rects.reduce(0) { $0 + $1.width * $1.height }
    }

    /// Every sample point is warm exactly when it is outside the hole, and never covered twice.
    private func expectTilesMatch(_ tiles: [CGRect], hole: [CGRect], in display: CGRect) {
        for x in stride(from: display.minX + 3, to: display.maxX, by: 37) {
            for y in stride(from: display.minY + 3, to: display.maxY, by: 29) {
                let point = CGPoint(x: x, y: y)
                let covering = tiles.filter { $0.contains(point) }.count
                let inHole = hole.contains { $0.contains(point) }
                #expect(covering == (inHole ? 0 : 1), "point \(point)")
            }
        }
    }

    @Test("The excluded app's window is the hole, and the tiles cover everything else once")
    func singleWindow() {
        let window = CGRect(x: 300, y: 250, width: 400, height: 300)
        let region = WindowHolePolicy.neutralRegion(
            windows: [.init(bounds: window, layer: 0, owner: 7)], owner: 7, display: display)
        #expect(region == [window])

        let tiles = WindowHolePolicy.warmTiles(around: region, in: display)
        #expect(area(tiles) == display.width * display.height - window.width * window.height)
        expectTilesMatch(tiles, hole: region, in: display)
    }

    @Test("Another app's window and a menu in front stay warm")
    func occludersStayWarm() {
        let excluded = CGRect(x: 300, y: 250, width: 400, height: 300)
        let other = CGRect(x: 600, y: 200, width: 300, height: 200)
        let menu = CGRect(x: 320, y: 260, width: 120, height: 80)
        let region = WindowHolePolicy.neutralRegion(windows: [
            .init(bounds: menu, layer: 101, owner: 3),
            .init(bounds: other, layer: 0, owner: 9),
            .init(bounds: excluded, layer: 0, owner: 7),
        ], owner: 7, display: display)

        #expect(area(region) == excluded.width * excluded.height
            - excluded.intersection(other).width * excluded.intersection(other).height
            - menu.width * menu.height)
        #expect(!region.contains { $0.contains(CGPoint(x: 650, y: 300)) })
        #expect(!region.contains { $0.contains(CGPoint(x: 350, y: 300)) })
        #expect(region.contains { $0.contains(CGPoint(x: 500, y: 500)) })
    }

    @Test("Invisible and full-display overlays in front do not hide the excluded window")
    func overlaysIgnored() {
        let excluded = CGRect(x: 300, y: 250, width: 400, height: 300)
        let region = WindowHolePolicy.neutralRegion(windows: [
            // An accessory app's invisible layer-0 overlay (Cua Driver) and a dimmer above everything.
            .init(bounds: display, layer: 0, owner: 4, isRegularApp: false),
            .init(bounds: display, layer: 2_000, owner: 5),
            .init(bounds: CGRect(x: 0, y: 0, width: 50, height: 50), layer: 0, owner: 6, alpha: 0),
            .init(bounds: excluded, layer: 0, owner: 7),
        ], owner: 7, display: display)
        #expect(region == [excluded])
    }

    @Test("A non-regular overlay overlapping an excluded window does not shrink the hole")
    func nonRegularOverlayDoesNotShrinkHole() {
        let excluded = CGRect(x: 300, y: 250, width: 400, height: 300)
        let hud = CGRect(x: 360, y: 300, width: 160, height: 90)
        let region = WindowHolePolicy.neutralRegion(windows: [
            .init(bounds: hud, layer: 25, owner: 4, isRegularApp: false),
            .init(bounds: excluded, layer: 0, owner: 7),
        ], owner: 7, display: display)
        #expect(region == [excluded])
        #expect(region.contains { $0.contains(CGPoint(x: hud.midX, y: hud.midY)) })
    }

    @Test("A floating window of the excluded app, such as picture in picture, is neutral")
    func floatingWindowOfExcludedAppIsNeutral() {
        let pip = CGRect(x: 1100, y: 40, width: 320, height: 180)
        let region = WindowHolePolicy.neutralRegion(windows: [
            .init(bounds: pip, layer: 3, owner: 7),
            .init(bounds: CGRect(x: 200, y: 200, width: 800, height: 500), layer: 0, owner: 7),
        ], owner: 7, display: display)
        #expect(region.contains { $0.contains(CGPoint(x: pip.midX, y: pip.midY)) })
    }

    @Test("An unfocused floating window of an excluded app stays neutral")
    func unfocusedFloatingWindowStaysNeutral() {
        let pip = CGRect(x: 1100, y: 40, width: 320, height: 180)
        let background = CGRect(x: 200, y: 200, width: 800, height: 500)
        let front = CGRect(x: 40, y: 80, width: 140, height: 100)
        let windows: [WindowHolePolicy.Window] = [
            .init(bounds: pip, layer: 3, owner: 7),
            .init(bounds: front, layer: 0, owner: 9),
            .init(bounds: background, layer: 0, owner: 7),
        ]
        let region = WindowHolePolicy.neutralRegion(
            windows: windows, owner: 9, display: display, floatingOwners: [7])
        #expect(region.contains(pip))
        #expect(region.contains(front))
        #expect(!region.contains { $0.contains(CGPoint(x: background.midX, y: background.midY)) })

        let focusedOnly = WindowHolePolicy.neutralRegion(windows: windows, owner: 9, display: display)
        #expect(!focusedOnly.contains { $0.contains(CGPoint(x: pip.midX, y: pip.midY)) })
    }


    @Test("Windows behind another app are not a hole, and other displays are clipped away")
    func hiddenAndOffDisplay() {
        let cover = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let behind = WindowHolePolicy.neutralRegion(windows: [
            .init(bounds: cover, layer: 0, owner: 9),
            .init(bounds: CGRect(x: 100, y: 100, width: 300, height: 300), layer: 0, owner: 7),
        ], owner: 7, display: display)
        #expect(behind.isEmpty)

        let straddling = CGRect(x: 1400, y: 100, width: 400, height: 300)
        let clipped = WindowHolePolicy.neutralRegion(
            windows: [.init(bounds: straddling, layer: 0, owner: 7)], owner: 7, display: display)
        #expect(clipped == [CGRect(x: 1400, y: 100, width: 112, height: 300)])
    }

    @Test("No hole covers the whole display, and overlapping holes leave no gaps or double cover")
    func tilesForManyHoles() {
        #expect(WindowHolePolicy.warmTiles(around: [], in: display) == [display])

        let holes = [
            CGRect(x: 100, y: 100, width: 300, height: 200),
            CGRect(x: 250, y: 150, width: 300, height: 300),
            CGRect(x: 900, y: 600, width: 200, height: 200),
            CGRect(x: 1400, y: 900, width: 300, height: 300),
        ]
        let tiles = WindowHolePolicy.warmTiles(around: holes, in: display)
        expectTilesMatch(tiles, hole: holes, in: display)
        #expect(tiles.allSatisfy { display.contains($0) })
    }

    @Test("A rounded window leaves its square corners warm")
    func roundedCornersStayWarm() {
        let window = CGRect(x: 300, y: 250, width: 400, height: 300)
        let region = WindowHolePolicy.neutralRegion(
            windows: [.init(bounds: window, layer: 0, owner: 7)],
            owner: 7, display: display, cornerRadius: 16)
        let corner = CGPoint(x: window.minX + 0.5, y: window.minY + 0.5)
        let alongEdge = CGPoint(x: window.minX + 16, y: window.minY + 1)
        let center = CGPoint(x: window.midX, y: window.midY)
        #expect(!region.contains { $0.contains(corner) })
        #expect(region.contains { $0.contains(alongEdge) })
        #expect(region.contains { $0.contains(center) })
        #expect(area(region) < window.width * window.height)

        let tiles = WindowHolePolicy.warmTiles(around: region, in: display)
        #expect(tiles.contains { $0.contains(corner) })
        expectTilesMatch(tiles, hole: region, in: display)
    }

    @Test("A window that fills the display keeps a square hole")
    func fullDisplayStaysSquare() {
        let region = WindowHolePolicy.neutralRegion(
            windows: [.init(bounds: display, layer: 0, owner: 7)],
            owner: 7, display: display, cornerRadius: 16)
        #expect(region.contains { $0.contains(CGPoint(x: 0.5, y: 0.5)) })
    }

    @Test("A fractional radius still covers the window up to the side strips")
    func fractionalRadiusHasNoGap() {
        let window = CGRect(x: 40, y: 40, width: 100, height: 31)
        let region = WindowHolePolicy.neutralRegion(
            windows: [.init(bounds: window, layer: 0, owner: 7)],
            owner: 7, display: display, cornerRadius: 16)
        // Height 31 clamps the radius to 15.5. The point just above the side strips is still window.
        let seam = CGPoint(x: window.minX + 8, y: window.minY + 15.25)
        #expect(region.contains { $0.contains(seam) })
        #expect(region.contains { $0.contains(CGPoint(x: window.midX, y: window.midY)) })
    }

    // MARK: Menus and popovers (#30)

    private func isNeutral(_ region: [CGRect], _ point: CGPoint) -> Bool {
        region.contains { $0.contains(point) }
    }

    @Test("The excluded app's menu is neutral at its own bounds, and its shadow frame is ignored")
    func excludedAppMenuIsNeutralAtItsBounds() {
        // FreeTube's menu drops from the menu bar over its window and past its top edge.
        let freeTube = CGRect(x: 130, y: 38, width: 900, height: 700)
        let menu = CGRect(x: 210, y: 33, width: 172, height: 190)
        let shadow = menu.insetBy(dx: -75, dy: -75)
        let region = WindowHolePolicy.neutralRegion(windows: [
            .init(bounds: shadow, layer: 101, owner: 7),
            .init(bounds: menu, layer: 101, owner: 7),
            .init(bounds: CGRect(x: 0, y: 0, width: 1512, height: 33), layer: 24, owner: 1, isRegularApp: false),
            .init(bounds: freeTube, layer: 0, owner: 7),
        ], owner: 7, display: display)

        // The whole menu is neutral, including the part above the window.
        for point in [CGPoint(x: menu.minX + 2, y: menu.minY + 1), CGPoint(x: menu.midX, y: 35),
                      CGPoint(x: menu.maxX - 2, y: menu.maxY - 2), CGPoint(x: menu.midX, y: menu.midY)] {
            #expect(isNeutral(region, point), "menu point \(point)")
        }
        // The shadow margin and the menu bar beside the menu stay warm.
        for point in [CGPoint(x: menu.minX - 40, y: 20), CGPoint(x: menu.maxX + 40, y: 20),
                      CGPoint(x: menu.midX, y: 10)] {
            #expect(!isNeutral(region, point), "shadow point \(point)")
        }
        #expect(isNeutral(region, CGPoint(x: freeTube.maxX - 5, y: freeTube.maxY - 5)))
        #expect(!isNeutral(region, CGPoint(x: freeTube.minX - 5, y: freeTube.midY)))
        let tiles = WindowHolePolicy.warmTiles(around: region, in: display)
        expectTilesMatch(tiles, hole: region, in: display)
    }

    @Test("Another app's menu over the excluded window stays warm at its own bounds")
    func otherAppMenuStaysWarm() {
        let excluded = CGRect(x: 300, y: 250, width: 600, height: 400)
        let shadowedMenu = CGRect(x: 400, y: 300, width: 160, height: 120)
        // A menu-bar app's menu: not a regular app, at the pop-up menu level.
        let extraMenu = CGRect(x: 700, y: 260, width: 150, height: 100)
        let windows: [WindowHolePolicy.Window] = [
            .init(bounds: shadowedMenu.insetBy(dx: -75, dy: -75), layer: 101, owner: 3),
            .init(bounds: shadowedMenu, layer: 101, owner: 3),
            .init(bounds: extraMenu, layer: 101, owner: 5, isRegularApp: false),
            .init(bounds: excluded, layer: 0, owner: 7),
        ]
        let region = WindowHolePolicy.neutralRegion(windows: windows, owner: 7, display: display)
        for menu in [shadowedMenu, extraMenu] {
            #expect(!isNeutral(region, CGPoint(x: menu.midX, y: menu.midY)))
            #expect(!isNeutral(region, CGPoint(x: menu.minX + 1, y: menu.minY + 1)))
            #expect(!isNeutral(region, CGPoint(x: menu.maxX - 1, y: menu.maxY - 1)))
        }
        // The shadow margin around the menu is not cut out of the excluded window.
        #expect(isNeutral(region, CGPoint(x: shadowedMenu.minX - 30, y: shadowedMenu.midY)))
        #expect(isNeutral(region, CGPoint(x: shadowedMenu.midX, y: shadowedMenu.maxY + 30)))
        #expect(area(region) == excluded.width * excluded.height
            - shadowedMenu.width * shadowedMenu.height - extraMenu.width * extraMenu.height)

        let tiles = WindowHolePolicy.warmTiles(around: region, in: display)
        expectTilesMatch(tiles, hole: region, in: display)
    }

    @Test("Excluded Finder: the desktop is never a hole, and a desktop menu is neutral only at its bounds")
    func finderDesktopIsNeverAHole() {
        let desktopIconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))
        let desktopLevel = Int(CGWindowLevelForKey(.desktopWindow))
        let menu = CGRect(x: 600, y: 300, width: 184, height: 304)
        let finder: Int32 = 7
        let region = WindowHolePolicy.neutralRegion(windows: [
            .init(bounds: menu.insetBy(dx: -75, dy: -75), layer: 101, owner: finder),
            .init(bounds: menu, layer: 101, owner: finder),
            .init(bounds: display, layer: desktopIconLevel, owner: finder),
            .init(bounds: display, layer: desktopLevel, owner: 2, isRegularApp: false),
        ], owner: finder, display: display, cornerRadius: 12)
        #expect(isNeutral(region, CGPoint(x: menu.midX, y: menu.midY)))
        #expect(!isNeutral(region, CGPoint(x: menu.minX - 30, y: menu.midY)))
        #expect(!isNeutral(region, CGPoint(x: menu.midX, y: menu.minY - 30)))
        #expect(!isNeutral(region, CGPoint(x: 100, y: 800)))
        #expect(region.allSatisfy { menu.contains($0) })

        let desktopOnly = WindowHolePolicy.neutralRegion(windows: [
            .init(bounds: display, layer: desktopIconLevel, owner: finder),
        ], owner: finder, display: display)
        #expect(desktopOnly.isEmpty)
    }

    @Test("This app's measured popover stays warm over an excluded window")
    func ownPopoverStaysWarm() {
        // Finder's window runs under the popover's lower part.
        let finderWindow = CGRect(x: 0, y: 80, width: 1300, height: 900)
        let popover = CGRect(x: 1000, y: 24, width: 330, height: 520)
        let region = WindowHolePolicy.neutralRegion(windows: [
            .init(bounds: popover, layer: 25, owner: 2, isRegularApp: false, isMeasured: true),
            .init(bounds: finderWindow, layer: 0, owner: 7),
        ], owner: 7, display: display)
        #expect(!isNeutral(region, CGPoint(x: popover.midX, y: popover.midY)))
        #expect(!isNeutral(region, CGPoint(x: popover.minX + 1, y: popover.maxY - 1)))
        #expect(isNeutral(region, CGPoint(x: popover.minX - 1, y: popover.midY)))
        #expect(isNeutral(region, CGPoint(x: popover.midX, y: popover.maxY + 1)))
        let overlap = finderWindow.intersection(popover)
        #expect(area(region) == finderWindow.width * finderWindow.height - overlap.width * overlap.height)

        // A menu-bar extra panel sits at the pop-up menu level and is sized to its content.
        let extra = WindowHolePolicy.neutralRegion(windows: [
            .init(bounds: popover, layer: 101, owner: 2, isRegularApp: false),
            .init(bounds: finderWindow, layer: 0, owner: 7),
        ], owner: 7, display: display)
        #expect(!isNeutral(extra, CGPoint(x: popover.midX, y: popover.midY)))
    }

    @Test("Only an even margin around a window of the same app on the same layer is a shadow frame")
    func shadowFrameNeedsEvenMargins() {
        let inner = CGRect(x: 400, y: 300, width: 200, height: 100)
        let windows: [WindowHolePolicy.Window] = [
            // 10 left and 90 right: a palette around a smaller panel, not a shadow.
            .init(bounds: CGRect(x: 390, y: 290, width: 300, height: 120), layer: 3, owner: 7),
            .init(bounds: inner, layer: 3, owner: 7),
            // A display-wide overlay, another layer, another owner, and a margin too wide for a shadow.
            .init(bounds: display, layer: 3, owner: 7),
            .init(bounds: inner.insetBy(dx: -20, dy: -20), layer: 8, owner: 7),
            .init(bounds: inner.insetBy(dx: -20, dy: -20), layer: 3, owner: 9),
            .init(bounds: inner.insetBy(dx: -200, dy: -200), layer: 3, owner: 7),
        ]
        #expect(WindowHolePolicy.shadowFrames(in: windows, display: display).isEmpty)

        let framed: [WindowHolePolicy.Window] = [
            .init(bounds: inner.insetBy(dx: -20, dy: -20).offsetBy(dx: 0, dy: 8), layer: 3, owner: 7),
            .init(bounds: inner, layer: 3, owner: 7),
        ]
        #expect(WindowHolePolicy.shadowFrames(in: framed, display: display) == [0])
    }

    // MARK: Padded menu windows (#30 after 1.1.15)

    private let terminal: Int32 = 7
    private let menuBar = CGRect(x: 0, y: 0, width: 1512, height: 33)

    /// The reporter's pasted window list with Terminal's Help menu open, front to back. The menu
    /// is one layer-101 window. Its bounds carry a 75 pt transparent margin on every side, so it
    /// starts 41 pt above the display.
    private var reporterWindows: [WindowHolePolicy.Window] {
        [
            .init(bounds: CGRect(x: 343, y: -4, width: 28, height: 40), layer: 2_147_483_630, owner: 1,
                  isRegularApp: false),
            .init(bounds: display, layer: 2_147_483_628, owner: 2, isRegularApp: false),
            .init(bounds: CGRect(x: 249, y: -41, width: 510, height: 278), layer: 101, owner: terminal),
            .init(bounds: menuBar, layer: 24, owner: 1, isRegularApp: false),
            .init(bounds: display, layer: 24, owner: 3, isRegularApp: false),
            .init(bounds: display, layer: 20, owner: 4, isRegularApp: false),
        ]
    }

    /// The menu the reporter's screenshot shows inside that window: 360 x 128 pt under the menu bar.
    private let helpMenu = CGRect(x: 324, y: 34, width: 360, height: 128)

    @Test("The reporter's menu window shows a 75 pt margin, measured against the menu bar")
    func paddedMenuMarginIsObserved() {
        #expect(WindowHolePolicy.observedMenuMargin(in: reporterWindows, displays: [display]) == 75)
    }

    @Test("A menu window that starts right under the menu bar proves nothing")
    func unpaddedMenuProvesNoMargin() {
        // macOS 26.6: the window is the menu.
        let windows: [WindowHolePolicy.Window] = [
            .init(bounds: CGRect(x: 6, y: 34, width: 263, height: 305), layer: 101, owner: terminal),
            .init(bounds: menuBar, layer: 24, owner: 1, isRegularApp: false),
        ]
        #expect(WindowHolePolicy.observedMenuMargin(in: windows, displays: [display]) == nil)
    }

    @Test("Only a menu window that starts above the display, measured against a menu bar, proves a margin")
    func menuMarginNeedsProof() {
        let contextMenu = WindowHolePolicy.Window(
            bounds: CGRect(x: 600, y: 477, width: 118, height: 106), layer: 101, owner: terminal)
        let bar = WindowHolePolicy.Window(bounds: menuBar, layer: 24, owner: 1, isRegularApp: false)
        #expect(WindowHolePolicy.observedMenuMargin(in: [contextMenu, bar], displays: [display]) == nil)
        #expect(WindowHolePolicy.observedMenuMargin(in: [bar], displays: [display]) == nil)
        // No menu bar on this display (full screen): nothing to measure against.
        let pullDown = WindowHolePolicy.Window(
            bounds: CGRect(x: 249, y: -41, width: 510, height: 278), layer: 101, owner: terminal)
        #expect(WindowHolePolicy.observedMenuMargin(in: [pullDown], displays: [display]) == nil)
        // This app's own measured windows are never evidence.
        let own = WindowHolePolicy.Window(
            bounds: CGRect(x: 249, y: -41, width: 510, height: 278), layer: 101, owner: 2, isMeasured: true)
        #expect(WindowHolePolicy.observedMenuMargin(in: [own, bar], displays: [display]) == nil)
        // The bottom margin of a menu on the display above pokes over this display's top edge.
        let above = CGRect(x: 0, y: -1080, width: 1920, height: 1080)
        let straddling = WindowHolePolicy.Window(
            bounds: CGRect(x: 300, y: -200, width: 400, height: 240), layer: 101, owner: terminal)
        #expect(WindowHolePolicy.observedMenuMargin(in: [straddling, bar], displays: [above, display]) == nil)
    }

    @Test("The reporter's Terminal menu is neutral at the menu, not at its 510 x 278 pt window")
    func paddedMenuOfExcludedAppIsNeutralAtItsBody() throws {
        let margin = try #require(WindowHolePolicy.observedMenuMargin(in: reporterWindows, displays: [display]))
        let region = WindowHolePolicy.neutralRegion(
            windows: reporterWindows, owner: terminal, display: display, menuMargin: margin)
        #expect(sameRegion(region, WindowHolePolicy.roundedInterior(helpMenu, radius: WindowHolePolicy.paddedMenuCornerRadius)))
        // The menu bar beside the menu and the margin around it stay warm.
        for point in [CGPoint(x: 280, y: 20), CGPoint(x: 720, y: 20), CGPoint(x: 280, y: 100),
                      CGPoint(x: 720, y: 100), CGPoint(x: 500, y: 200), CGPoint(x: 500, y: 20)] {
            #expect(!isNeutral(region, point), "margin point \(point)")
        }
        let tiles = WindowHolePolicy.warmTiles(around: region, in: display)
        expectTilesMatch(tiles, hole: region, in: display)
    }

    @Test("Without proof of a margin, menu windows count at their bounds, as in 1.1.15")
    func unprovenMarginKeepsMenuBounds() {
        // The reporter's list with no margin applied: the old box, the window clipped to the display.
        let box = CGRect(x: 249, y: 0, width: 510, height: 237)
        #expect(WindowHolePolicy.neutralRegion(windows: reporterWindows, owner: terminal, display: display) == [box])

        // An unpadded Mac. The excluded app's context menu runs past its window, and a menu-bar
        // app's menu and a menu-level panel sit over it. None of them hangs under a listed menu bar.
        let window = CGRect(x: 200, y: 60, width: 700, height: 500)
        let contextMenu = CGRect(x: 820, y: 300, width: 180, height: 220)
        let extraMenu = CGRect(x: 300, y: 24, width: 184, height: 294)
        let panel = CGRect(x: 600, y: 100, width: 150, height: 100)
        let windows: [WindowHolePolicy.Window] = [
            .init(bounds: contextMenu, layer: 101, owner: terminal),
            .init(bounds: extraMenu, layer: 101, owner: 5, isRegularApp: false),
            .init(bounds: panel, layer: 101, owner: 6, isRegularApp: false),
            .init(bounds: window, layer: 0, owner: terminal),
        ]
        #expect(WindowHolePolicy.observedMenuMargin(in: windows, displays: [display]) == nil)
        let region = WindowHolePolicy.neutralRegion(windows: windows, owner: terminal, display: display)
        #expect(region == WindowHolePolicy.neutralRegion(
            windows: windows, owner: terminal, display: display, menuMargin: 0))
        // The context menu is neutral at its own bounds, past the window's edge too.
        #expect(region.contains(contextMenu))
        #expect(isNeutral(region, CGPoint(x: contextMenu.maxX - 1, y: contextMenu.maxY - 1)))
        // The other apps' menu and panel stay warm at their own bounds.
        for occluder in [extraMenu, panel] {
            #expect(!isNeutral(region, CGPoint(x: occluder.midX, y: occluder.midY)))
            #expect(!isNeutral(region, CGPoint(x: occluder.minX + 1, y: occluder.maxY - 1)))
            #expect(!isNeutral(region, CGPoint(x: occluder.maxX - 1, y: occluder.maxY - 1)))
            #expect(isNeutral(region, CGPoint(x: occluder.maxX + 1, y: occluder.maxY + 1)))
        }
        // The menu's hole and the window's hole overlap; both are counted.
        #expect(area(region) == window.width * window.height + contextMenu.width * contextMenu.height
            - extraMenu.intersection(window).width * extraMenu.intersection(window).height
            - panel.width * panel.height)
    }

    @Test("With a proven margin and no menu bar listed, nothing is worse than the old box")
    func provenMarginWithoutMenuBar() {
        // An auto-hidden menu bar. The excluded app's menu is still cut at the menu.
        let menuWindow = CGRect(x: 249, y: 100, width: 510, height: 278)
        let own = WindowHolePolicy.neutralRegion(windows: [
            .init(bounds: menuWindow, layer: 101, owner: terminal),
        ], owner: terminal, display: display, menuMargin: 75)
        #expect(sameRegion(own, WindowHolePolicy.roundedInterior(
            menuWindow.insetBy(dx: 75, dy: 75), radius: WindowHolePolicy.paddedMenuCornerRadius)))

        // A menu-bar app's menu cannot be told from an overlay, so it cuts no warm box.
        let excluded = CGRect(x: 60, y: 40, width: 1100, height: 800)
        let other = WindowHolePolicy.neutralRegion(windows: [
            .init(bounds: CGRect(x: 300, y: -41, width: 334, height: 444), layer: 101, owner: 5, isRegularApp: false),
            .init(bounds: excluded, layer: 0, owner: terminal),
        ], owner: terminal, display: display, menuMargin: 75)
        #expect(other == [excluded])
    }

    @Test("Excluded Finder: a padded desktop menu is neutral only at the menu")
    func paddedFinderDesktopMenu() {
        // The neutral box in the reporter's screenshot is 334 x 455 pt around a 184 x 305 pt menu.
        let window = CGRect(x: 500, y: 200, width: 334, height: 455)
        let menu = window.insetBy(dx: 75, dy: 75)
        let finder: Int32 = 9
        let windows: [WindowHolePolicy.Window] = [
            .init(bounds: window, layer: 101, owner: finder),
            .init(bounds: menuBar, layer: 24, owner: 1, isRegularApp: false),
            .init(bounds: display, layer: Int(CGWindowLevelForKey(.desktopIconWindow)), owner: finder),
        ]
        let region = WindowHolePolicy.neutralRegion(
            windows: windows, owner: finder, display: display, menuMargin: 75)
        #expect(sameRegion(region, WindowHolePolicy.roundedInterior(menu, radius: WindowHolePolicy.paddedMenuCornerRadius)))
        // A context menu proves nothing itself. Until a pull-down menu has been seen, the old box stays.
        #expect(WindowHolePolicy.observedMenuMargin(in: windows, displays: [display]) == nil)
        #expect(WindowHolePolicy.neutralRegion(windows: windows, owner: finder, display: display) == [window])
    }

    @Test("A menu-bar app's padded menu stays warm at the menu, without a warm box around it")
    func paddedMenuOfMenuBarAppStaysWarmAtItsBody() {
        // LuLu's menu over an excluded video window. The warm box in the reporter's screenshot is
        // 334 pt wide and reaches 75 pt past the menu on the left, right and bottom.
        let excluded = CGRect(x: 60, y: 40, width: 1100, height: 800)
        let window = CGRect(x: 300, y: -41, width: 334, height: 444)
        let menu = window.insetBy(dx: 75, dy: 75)
        let submenuWindow = CGRect(x: 480, y: 70, width: 300, height: 250)
        let submenu = submenuWindow.insetBy(dx: 75, dy: 75)
        let windows: [WindowHolePolicy.Window] = [
            .init(bounds: submenuWindow, layer: 101, owner: 5, isRegularApp: false),
            .init(bounds: window, layer: 101, owner: 5, isRegularApp: false),
            .init(bounds: menuBar, layer: 24, owner: 1, isRegularApp: false),
            .init(bounds: excluded, layer: 0, owner: terminal),
        ]
        // An accessory app's window is not proof. The margin comes from a regular app's menu.
        #expect(WindowHolePolicy.observedMenuMargin(in: windows, displays: [display]) == nil)
        let region = WindowHolePolicy.neutralRegion(
            windows: windows, owner: terminal, display: display, menuMargin: 75)
        for body in [menu, submenu] {
            #expect(!isNeutral(region, CGPoint(x: body.midX, y: body.midY)))
            #expect(!isNeutral(region, CGPoint(x: body.minX + 1, y: body.midY)))
            #expect(!isNeutral(region, CGPoint(x: body.midX, y: body.maxY - 1)))
        }
        // The margin is not a warm box: the excluded window shows through it.
        #expect(isNeutral(region, CGPoint(x: menu.minX - 30, y: menu.midY)))
        #expect(isNeutral(region, CGPoint(x: menu.midX, y: menu.maxY + 30)))
        #expect(isNeutral(region, CGPoint(x: submenu.maxX + 30, y: submenu.midY)))
        // Outside each menu's rounded corner the excluded window shows, neutral.
        #expect(isNeutral(region, CGPoint(x: menu.minX + 0.5, y: menu.maxY - 0.5)))
        #expect(isNeutral(region, CGPoint(x: submenu.maxX - 0.5, y: submenu.maxY - 0.5)))
        let tiles = WindowHolePolicy.warmTiles(around: region, in: display)
        expectTilesMatch(tiles, hole: region, in: display)
    }

    @Test("A menu-level overlay that does not hang from the menu bar cuts no warm box when menus are padded")
    func paddedOverlayOfAccessoryAppIsIgnored() {
        // The volume control over an excluded video. Its margins are not a menu's, so its visible
        // part cannot be known.
        let excluded = CGRect(x: 60, y: 40, width: 1100, height: 800)
        let overlay = CGRect(x: 1100, y: 10, width: 367, height: 210)
        let region = WindowHolePolicy.neutralRegion(windows: [
            .init(bounds: overlay, layer: 101, owner: 6, isRegularApp: false),
            .init(bounds: menuBar, layer: 24, owner: 1, isRegularApp: false),
            .init(bounds: excluded, layer: 0, owner: terminal),
        ], owner: terminal, display: display, menuMargin: 75)
        #expect(region == [excluded])
    }

    @Test("Another regular app's padded menu stays warm at the menu")
    func paddedMenuOfRegularAppStaysWarmAtItsBody() {
        let excluded = CGRect(x: 60, y: 40, width: 1100, height: 800)
        let window = CGRect(x: 400, y: 300, width: 310, height: 270)
        let menu = window.insetBy(dx: 75, dy: 75)
        let region = WindowHolePolicy.neutralRegion(windows: [
            .init(bounds: window, layer: 101, owner: 3),
            .init(bounds: excluded, layer: 0, owner: terminal),
        ], owner: terminal, display: display, menuMargin: 75)
        let outside = WindowHolePolicy.roundedExterior(menu, radius: WindowHolePolicy.paddedMenuCornerRadius)
        #expect(abs(area(region) - (excluded.width * excluded.height - menu.width * menu.height + area(outside))) < 1e-6)
        #expect(!isNeutral(region, CGPoint(x: menu.midX, y: menu.midY)))
        #expect(isNeutral(region, CGPoint(x: window.minX + 10, y: window.midY)))
    }

    @Test("A menu-level window too small to hold a padded menu is ignored")
    func tooSmallForPaddedMenu() {
        let region = WindowHolePolicy.neutralRegion(windows: [
            .init(bounds: CGRect(x: 400, y: 300, width: 150, height: 120), layer: 101, owner: terminal),
        ], owner: terminal, display: display, menuMargin: 75)
        #expect(region.isEmpty)
    }

    // MARK: Each window's own corner radius (#30)

    /// Same pieces in the same order, to within float rounding from clipping to the display.
    private func sameRegion(_ a: [CGRect], _ b: [CGRect]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { lhs, rhs in
            abs(lhs.minX - rhs.minX) < 1e-9 && abs(lhs.minY - rhs.minY) < 1e-9
                && abs(lhs.width - rhs.width) < 1e-9 && abs(lhs.height - rhs.height) < 1e-9
        }
    }

    /// 4 pt in from a corner, in the 1 pt row 4 pt down. Inside a 12 pt curve, outside a 16 pt one.
    private func between12And16(_ rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + 4, y: rect.minY + 4.5)
    }

    @Test("Inside and outside a rounded corner never overlap, and miss only slivers too thin to see")
    func interiorAndExteriorTile() {
        let rect = CGRect(x: 100.5, y: 40, width: 61, height: 47)
        let sliver = WindowHolePolicy.minExteriorWidth
        for radius: CGFloat in [0, 0.5, 1, 7.3, 12, 16, 20, 23.5, 40] {
            let inside = WindowHolePolicy.roundedInterior(rect, radius: radius)
            let outside = WindowHolePolicy.roundedExterior(rect, radius: radius)
            #expect(area(inside) + area(outside) <= rect.width * rect.height + 1e-6, "radius \(radius)")
            #expect(outside.allSatisfy { $0.width >= sliver }, "radius \(radius)")
            for x in stride(from: rect.minX + 0.13, to: rect.maxX, by: 0.71) {
                for y in stride(from: rect.minY + 0.17, to: rect.maxY, by: 0.53) {
                    let point = CGPoint(x: x, y: y)
                    let count = (inside + outside).filter { $0.contains(point) }.count
                    let nearSide = min(x - rect.minX, rect.maxX - x) < sliver
                    #expect(count == 1 || (count == 0 && nearSide), "radius \(radius) point \(point)")
                }
            }
        }
        #expect(WindowHolePolicy.roundedExterior(rect, radius: 0).isEmpty)
    }

    @Test("A neutral window with no reported radius gets exactly the 1.1.16 hole")
    func unknownRadiusIsPinned() {
        // The 1.1.16 shape: the straight middle and sides, then 1 pt corner rows.
        let window = CGRect(x: 300, y: 250, width: 400, height: 300)
        let region = WindowHolePolicy.neutralRegion(
            windows: [.init(bounds: window, layer: 0, owner: 7)], owner: 7, display: display, cornerRadius: 2)
        let outer: CGFloat = CGFloat(1.75).squareRoot()   // the first row's width inside the curve
        let inner: CGFloat = CGFloat(3.75).squareRoot()   // the second row's
        let rows: [CGRect] = [
            CGRect(x: 302 - outer, y: 250, width: outer, height: 1),
            CGRect(x: 698, y: 250, width: outer, height: 1),
            CGRect(x: 302 - outer, y: 549, width: outer, height: 1),
            CGRect(x: 698, y: 549, width: outer, height: 1),
            CGRect(x: 302 - inner, y: 251, width: inner, height: 1),
            CGRect(x: 698, y: 251, width: inner, height: 1),
            CGRect(x: 302 - inner, y: 548, width: inner, height: 1),
            CGRect(x: 698, y: 548, width: inner, height: 1),
        ]
        #expect(sameRegion(region, [
            CGRect(x: 302, y: 250, width: 396, height: 300),
            CGRect(x: 300, y: 252, width: 2, height: 296),
            CGRect(x: 698, y: 252, width: 2, height: 296),
        ] + rows))

        // A warm menu in front with no radius cuts exactly its rectangle, as before.
        let menu = CGRect(x: 350, y: 300, width: 100, height: 80)
        let cut = WindowHolePolicy.neutralRegion(windows: [
            .init(bounds: menu, layer: 101, owner: 3),
            .init(bounds: window, layer: 0, owner: 7),
        ], owner: 7, display: display)
        #expect(sameRegion(cut, [
            CGRect(x: 300, y: 250, width: 400, height: 50),
            CGRect(x: 300, y: 380, width: 400, height: 170),
            CGRect(x: 300, y: 300, width: 50, height: 80),
            CGRect(x: 450, y: 300, width: 250, height: 80),
        ]))
    }

    @Test("A rounded window in front of another warm window gives no corner back to the hole")
    func stackedOccluders() {
        let excluded = CGRect(x: 100, y: 100, width: 1200, height: 800)
        let front = CGRect(x: 400, y: 300, width: 200, height: 150)
        // The second warm window sits under the front one's top-left corner.
        let behind = CGRect(x: 350, y: 250, width: 100, height: 100)
        let region = WindowHolePolicy.neutralRegion(windows: [
            .init(bounds: front, layer: 0, owner: 9, cornerRadius: 16),
            .init(bounds: behind, layer: 0, owner: 8, cornerRadius: 16),
            .init(bounds: excluded, layer: 0, owner: 7),
        ], owner: 7, display: display)
        // Outside the front window's corner, over the window behind: warm.
        #expect(!isNeutral(region, CGPoint(x: front.minX + 0.5, y: front.minY + 0.5)))
        // Outside its far corners, over the excluded window: neutral.
        #expect(isNeutral(region, CGPoint(x: front.maxX - 0.5, y: front.maxY - 0.5)))
        #expect(isNeutral(region, CGPoint(x: behind.minX + 0.5, y: behind.minY + 0.5)))
        let tiles = WindowHolePolicy.warmTiles(around: region, in: display)
        expectTilesMatch(tiles, hole: region, in: display)
    }

    @Test("Warm tiles cover every band's gaps exactly, for holes in any order")
    func tilesMatchForManyRoundedHoles() {
        // Spelled out step by step: one mixed Int/CGFloat expression here times out the macOS 15
        // runners' type checker.
        var windows: [WindowHolePolicy.Window] = []
        for index in 0..<6 {
            let step = CGFloat(index)
            let bounds = CGRect(x: 60 + step * 170, y: 700 - step * 110, width: 380, height: 260)
            let owner: Int32 = index.isMultiple(of: 2) ? 7 : Int32(20 + index)
            windows.append(WindowHolePolicy.Window(bounds: bounds, layer: 0, owner: owner, cornerRadius: 12 + step))
        }
        let region = WindowHolePolicy.neutralRegion(windows: windows, owner: 7, display: display, cornerRadius: 16)
        let tiles = WindowHolePolicy.warmTiles(around: region, in: display)
        expectTilesMatch(tiles, hole: region, in: display)
        #expect(abs(area(tiles) + area(region) - display.width * display.height) < 1e-3)
        #expect(WindowHolePolicy.warmTiles(around: region.reversed(), in: display).count == tiles.count)
    }

    @Test("A neutral window follows its own corner radius, not the titled-window default")
    func neutralWindowUsesItsOwnRadius() {
        // The reporter's menus have a smaller radius than a titled window, so a 16 pt hole left a
        // warm sliver inside each menu corner.
        let menu = CGRect(x: 600, y: 300, width: 184, height: 120)
        let windowed = WindowHolePolicy.neutralRegion(
            windows: [.init(bounds: menu, layer: 101, owner: 7, cornerRadius: 12)],
            owner: 7, display: display, cornerRadius: 16)
        #expect(isNeutral(windowed, between12And16(menu)))
        #expect(!isNeutral(windowed, CGPoint(x: menu.minX + 0.5, y: menu.minY + 0.5)))
        #expect(sameRegion(windowed, WindowHolePolicy.roundedInterior(menu, radius: 12)))

        // A larger reported radius is followed too (a browser window at 20 pt).
        let browser = CGRect(x: 100, y: 100, width: 400, height: 300)
        let wide = WindowHolePolicy.neutralRegion(
            windows: [.init(bounds: browser, layer: 0, owner: 7, cornerRadius: 20)],
            owner: 7, display: display, cornerRadius: 16)
        #expect(sameRegion(wide, WindowHolePolicy.roundedInterior(browser, radius: 20)))
    }

    @Test("An unknown or zero radius falls back to the titled-window default, as before")
    func unknownRadiusFallsBack() {
        let window = CGRect(x: 300, y: 250, width: 400, height: 300)
        let expected = WindowHolePolicy.roundedInterior(window, radius: 16)
        for reported: CGFloat? in [nil, 0, -3, .nan, .infinity] {
            let region = WindowHolePolicy.neutralRegion(
                windows: [.init(bounds: window, layer: 0, owner: 7, cornerRadius: reported)],
                owner: 7, display: display, cornerRadius: 16)
            #expect(sameRegion(region, expected), "reported \(String(describing: reported))")
        }
    }

    @Test("A window that fills the display stays square whatever radius it reports")
    func fullDisplayIgnoresReportedRadius() {
        let region = WindowHolePolicy.neutralRegion(
            windows: [.init(bounds: display, layer: 0, owner: 7, cornerRadius: 16)],
            owner: 7, display: display, cornerRadius: 16)
        #expect(region == [display])
    }

    @Test("This app's rounded popover leaves the excluded window neutral outside its corners")
    func roundedPopoverKeepsCornersNeutral() {
        // The reporter's screenshot: a warm square around the popover's rounded bottom corners.
        let finderWindow = CGRect(x: 0, y: 80, width: 1300, height: 900)
        let popover = CGRect(x: 1000, y: 24, width: 330, height: 520)
        let region = WindowHolePolicy.neutralRegion(windows: [
            .init(bounds: popover, layer: 25, owner: 2, isRegularApp: false, isMeasured: true, cornerRadius: 20),
            .init(bounds: finderWindow, layer: 0, owner: 7),
        ], owner: 7, display: display)
        // Outside the curve, inside the popover's square: the excluded window shows, neutral.
        #expect(isNeutral(region, CGPoint(x: popover.minX + 1, y: popover.maxY - 1)))
        #expect(isNeutral(region, CGPoint(x: popover.minX + 3, y: popover.maxY - 3)))
        // The popover itself stays warm, right up to its curve.
        #expect(!isNeutral(region, CGPoint(x: popover.midX, y: popover.midY)))
        #expect(!isNeutral(region, CGPoint(x: popover.minX + 1, y: popover.midY)))
        #expect(!isNeutral(region, CGPoint(x: popover.minX + 8, y: popover.maxY - 8)))
        #expect(!isNeutral(region, CGPoint(x: popover.midX, y: popover.maxY - 0.5)))
        // The top corners are above Finder's window and stay warm.
        #expect(!isNeutral(region, CGPoint(x: popover.minX + 1, y: popover.minY + 1)))
        let tiles = WindowHolePolicy.warmTiles(around: region, in: display)
        expectTilesMatch(tiles, hole: region, in: display)
        #expect(tiles.contains { $0.contains(CGPoint(x: popover.midX, y: popover.midY)) })
        #expect(!tiles.contains { $0.contains(CGPoint(x: popover.minX + 1, y: popover.maxY - 1)) })
    }

    @Test("A warm menu or window in front keeps its own rounded corners")
    func roundedOccludersKeepTheirCorners() {
        let excluded = CGRect(x: 100, y: 100, width: 1200, height: 800)
        let menu = CGRect(x: 300, y: 300, width: 160, height: 120)
        let other = CGRect(x: 700, y: 400, width: 300, height: 200)
        let region = WindowHolePolicy.neutralRegion(windows: [
            .init(bounds: menu, layer: 101, owner: 3, cornerRadius: 12),
            .init(bounds: other, layer: 0, owner: 9, cornerRadius: 16),
            .init(bounds: excluded, layer: 0, owner: 7, cornerRadius: 16),
        ], owner: 7, display: display)
        for rect in [menu, other] {
            #expect(isNeutral(region, CGPoint(x: rect.minX + 0.5, y: rect.minY + 0.5)), "corner of \(rect)")
            #expect(isNeutral(region, CGPoint(x: rect.maxX - 0.5, y: rect.maxY - 0.5)), "corner of \(rect)")
            #expect(!isNeutral(region, CGPoint(x: rect.midX, y: rect.midY)))
            #expect(!isNeutral(region, CGPoint(x: rect.minX + 0.5, y: rect.midY)))
        }
        // The other window's curve is 16 pt, so a point inside a 12 pt curve is still neutral there.
        #expect(isNeutral(region, between12And16(other)))
        #expect(!isNeutral(region, between12And16(menu)))
        let tiles = WindowHolePolicy.warmTiles(around: region, in: display)
        expectTilesMatch(tiles, hole: region, in: display)
    }

    @Test("A warm window with no reported radius still cuts a square, as in 1.1.16")
    func unknownOccluderRadiusStaysSquare() {
        let excluded = CGRect(x: 100, y: 100, width: 1200, height: 800)
        let menu = CGRect(x: 300, y: 300, width: 160, height: 120)
        for reported: CGFloat? in [nil, 0] {
            let region = WindowHolePolicy.neutralRegion(windows: [
                .init(bounds: menu, layer: 101, owner: 3, cornerRadius: reported),
                .init(bounds: excluded, layer: 0, owner: 7),
            ], owner: 7, display: display)
            #expect(area(region) == excluded.width * excluded.height - menu.width * menu.height)
            #expect(!isNeutral(region, CGPoint(x: menu.minX + 0.5, y: menu.minY + 0.5)))
        }
    }

    @Test("A padded menu's body takes the radius its window reports")
    func paddedMenuBodyUsesReportedRadius() {
        let excluded = CGRect(x: 60, y: 40, width: 1100, height: 800)
        let window = CGRect(x: 400, y: 300, width: 310, height: 270)
        let menu = window.insetBy(dx: 75, dy: 75)
        let warm = WindowHolePolicy.neutralRegion(windows: [
            .init(bounds: window, layer: 101, owner: 3, cornerRadius: 12),
            .init(bounds: excluded, layer: 0, owner: terminal),
        ], owner: terminal, display: display, menuMargin: 75)
        #expect(isNeutral(warm, CGPoint(x: menu.minX + 0.5, y: menu.minY + 0.5)))
        #expect(!isNeutral(warm, CGPoint(x: menu.midX, y: menu.midY)))

        let neutral = WindowHolePolicy.neutralRegion(windows: [
            .init(bounds: window, layer: 101, owner: terminal, cornerRadius: 12),
        ], owner: terminal, display: display, cornerRadius: 16, menuMargin: 75)
        #expect(sameRegion(neutral, WindowHolePolicy.roundedInterior(menu, radius: 12)))
    }

    // MARK: Padded menus on macOS 27 and the Stage Manager strip (#30 after 1.1.18)

    /// 5 pt in from a corner, in the 1 pt row 3 pt down. The curve sits 4.1 pt in there for a
    /// 13 pt radius and 6.0 pt for a 16 pt one, so the point is inside the first, outside the second.
    private func between13And16(_ rect: CGRect, corner: Int) -> CGPoint {
        switch corner {
        case 0: return CGPoint(x: rect.minX + 5, y: rect.minY + 3.5)
        case 1: return CGPoint(x: rect.maxX - 5, y: rect.minY + 3.5)
        case 2: return CGPoint(x: rect.minX + 5, y: rect.maxY - 3.5)
        default: return CGPoint(x: rect.maxX - 5, y: rect.maxY - 3.5)
        }
    }

    @Test("A padded menu reporting no radius is cut at the menu's own corner, not the titled default")
    func paddedMenuWithoutRadiusUsesMenuCorner() {
        // The reporter's Finder menu on macOS 27.2: one layer-101 window, radius 0. The 16 pt hole
        // left a warm sliver inside every corner of the 13 pt menu.
        let window = CGRect(x: -70, y: -41, width: 379, height: 455)
        let menu = window.insetBy(dx: 75, dy: 75)
        let finder: Int32 = 9
        for reported: CGFloat? in [nil, 0] {
            let region = WindowHolePolicy.neutralRegion(windows: [
                .init(bounds: window, layer: 101, owner: finder, cornerRadius: reported),
                .init(bounds: menuBar, layer: 24, owner: 1, isRegularApp: false),
            ], owner: finder, display: display, cornerRadius: 16, menuMargin: 75)
            #expect(sameRegion(region, WindowHolePolicy.roundedInterior(
                menu.intersection(display), radius: WindowHolePolicy.paddedMenuCornerRadius)))
            for corner in 0...3 {
                #expect(isNeutral(region, between13And16(menu, corner: corner)), "corner \(corner)")
            }
            #expect(!isNeutral(region, CGPoint(x: menu.minX + 0.5, y: menu.maxY - 0.5)))
            #expect(!isNeutral(region, CGPoint(x: menu.maxX - 0.5, y: menu.minY + 0.5)))
        }
    }

    @Test("Another app's padded menu over an excluded window keeps its rounded corners")
    func warmPaddedMenuKeepsRoundedCorners() {
        let excluded = CGRect(x: 60, y: 40, width: 1100, height: 800)
        let window = CGRect(x: 400, y: 300, width: 310, height: 270)
        let menu = window.insetBy(dx: 75, dy: 75)
        let region = WindowHolePolicy.neutralRegion(windows: [
            .init(bounds: window, layer: 101, owner: 3, cornerRadius: 0),
            .init(bounds: excluded, layer: 0, owner: terminal),
        ], owner: terminal, display: display, cornerRadius: 16, menuMargin: 75)
        // Outside the menu's curve the excluded window shows; inside it the menu stays warm.
        #expect(isNeutral(region, CGPoint(x: menu.minX + 0.5, y: menu.minY + 0.5)))
        #expect(isNeutral(region, CGPoint(x: menu.maxX - 0.5, y: menu.maxY - 0.5)))
        for corner in 0...3 {
            #expect(!isNeutral(region, between13And16(menu, corner: corner)), "corner \(corner)")
        }
        #expect(!isNeutral(region, CGPoint(x: menu.midX, y: menu.midY)))
        let tiles = WindowHolePolicy.warmTiles(around: region, in: display)
        expectTilesMatch(tiles, hole: region, in: display)
    }

    @Test("Menus that are not padded keep the old radii exactly")
    func unpaddedMenusUnchanged() {
        // macOS 26: the window is the menu. No margin, so no padded radius, whatever is reported.
        let menu = CGRect(x: 600, y: 300, width: 184, height: 120)
        let excluded = CGRect(x: 100, y: 100, width: 1200, height: 800)
        for reported: CGFloat? in [nil, 0, 12] {
            let neutral = WindowHolePolicy.neutralRegion(
                windows: [.init(bounds: menu, layer: 101, owner: 7, cornerRadius: reported)],
                owner: 7, display: display, cornerRadius: 16)
            #expect(sameRegion(neutral, WindowHolePolicy.roundedInterior(menu, radius: reported.flatMap { $0 > 0 ? $0 : nil } ?? 16)))
            let warm = WindowHolePolicy.neutralRegion(windows: [
                .init(bounds: menu, layer: 101, owner: 3, cornerRadius: reported),
                .init(bounds: excluded, layer: 0, owner: 7),
            ], owner: 7, display: display)
            let square = reported.flatMap { $0 > 0 ? $0 : nil } == nil
            #expect(isNeutral(warm, CGPoint(x: menu.minX + 0.5, y: menu.minY + 0.5)) == !square)
        }
    }

    /// The reporter's list on macOS 27.2 with Stage Manager on, Finder in front and every window
    /// in the strip, front to back. Stage Manager lists a window of its own at each thumbnail.
    private let stageManager: Int32 = 40
    private let finderApp: Int32 = 9
    private var stripWindows: [WindowHolePolicy.Window] {
        [
            .init(bounds: CGRect(x: -7, y: 267, width: 66, height: 82), layer: 0, owner: stageManager,
                  isRegularApp: false, isStageManager: true),
            .init(bounds: CGRect(x: 16, y: 216, width: 160, height: 120), layer: 0, owner: stageManager,
                  isRegularApp: false, isStageManager: true),
            .init(bounds: CGRect(x: 16, y: 216, width: 160, height: 120), layer: 0, owner: finderApp,
                  cornerRadius: 36.9056),
            .init(bounds: CGRect(x: 32, y: 340, width: 138, height: 152), layer: 0, owner: stageManager,
                  isRegularApp: false, isStageManager: true),
            .init(bounds: CGRect(x: 32, y: 340, width: 138, height: 152), layer: 0, owner: 21, cornerRadius: 47.45),
            .init(bounds: CGRect(x: 32, y: 518, width: 138, height: 155), layer: 0, owner: stageManager,
                  isRegularApp: false, isStageManager: true),
            .init(bounds: CGRect(x: 32, y: 518, width: 138, height: 155), layer: 0, owner: 22, cornerRadius: 47.45),
        ]
    }

    @Test("The excluded app's thumbnail in the Stage Manager strip stays warm")
    func stageStripThumbnailIsNoHole() {
        #expect(WindowHolePolicy.neutralRegion(
            windows: stripWindows, owner: finderApp, display: display, cornerRadius: 16).isEmpty)
        // The same with the browser as the excluded front app: its thumbnail stays warm too.
        #expect(WindowHolePolicy.neutralRegion(
            windows: stripWindows, owner: 21, display: display, cornerRadius: 16).isEmpty)
    }

    @Test("A window on the stage is still a hole, and Stage Manager's own windows never are")
    func stageWindowStaysAHole() {
        let stage = CGRect(x: 220, y: 90, width: 1000, height: 700)
        let windows = stripWindows + [.init(bounds: stage, layer: 0, owner: finderApp, cornerRadius: 16)]
        let region = WindowHolePolicy.neutralRegion(windows: windows, owner: finderApp, display: display, cornerRadius: 16)
        #expect(sameRegion(region, WindowHolePolicy.roundedInterior(stage, radius: 16)))
        // A Stage Manager window that matches no app window changes nothing; nor does an app
        // window 2 pt off a Stage Manager window.
        let near = CGRect(x: 18, y: 216, width: 160, height: 120)
        let offset = WindowHolePolicy.neutralRegion(windows: [
            .init(bounds: CGRect(x: 16, y: 216, width: 160, height: 120), layer: 0, owner: stageManager,
                  isRegularApp: false, isStageManager: true),
            .init(bounds: near, layer: 0, owner: finderApp, cornerRadius: 16),
        ], owner: finderApp, display: display, cornerRadius: 16)
        #expect(sameRegion(offset, WindowHolePolicy.roundedInterior(near, radius: 16)))
        // Same corner, another size: a window on the stage that happens to start at a thumbnail.
        let larger = CGRect(x: 16, y: 216, width: 900, height: 600)
        let sized = WindowHolePolicy.neutralRegion(windows: [
            .init(bounds: CGRect(x: 16, y: 216, width: 160, height: 120), layer: 0, owner: stageManager,
                  isRegularApp: false, isStageManager: true),
            .init(bounds: larger, layer: 0, owner: finderApp, cornerRadius: 16),
        ], owner: finderApp, display: display, cornerRadius: 16)
        #expect(sameRegion(sized, WindowHolePolicy.roundedInterior(larger, radius: 16)))
        // Stage Manager excluded (as if): its own windows are not thumbnails of themselves.
        let own = WindowHolePolicy.neutralRegion(windows: [
            .init(bounds: stage, layer: 0, owner: stageManager, isRegularApp: false, isStageManager: true),
        ], owner: stageManager, display: display, cornerRadius: 16)
        #expect(sameRegion(own, WindowHolePolicy.roundedInterior(stage, radius: 16)))
    }

    @Test("Without Stage Manager windows, nothing changes")
    func noStageManagerNoChange() {
        let plain = stripWindows.filter { !$0.isStageManager }
        let region = WindowHolePolicy.neutralRegion(windows: plain, owner: finderApp, display: display, cornerRadius: 16)
        #expect(sameRegion(region, WindowHolePolicy.roundedInterior(
            CGRect(x: 16, y: 216, width: 160, height: 120), radius: 36.9056)))
    }

    // MARK: Menu-bar extra popovers (#30 after 1.1.18)

    /// SoloFan's popover in the reporter's screenshot: a 340 pt popover in a 366 pt window that
    /// starts 5 pt above the bottom of the menu bar, with the arrow under its status item. On
    /// macOS 26 Control Center owns every status item, not the app.
    private let popoverWindow = CGRect(x: 300, y: 28, width: 366, height: 426)
    private var popoverBody: CGRect { popoverWindow.insetBy(dx: 13, dy: 13) }
    private let soloFan: Int32 = 30
    private let controlCenter: Int32 = 33
    private var soloFanItem: WindowHolePolicy.Window {
        .init(bounds: CGRect(x: 460, y: 0, width: 46, height: 33), layer: WindowHolePolicy.statusLayer,
              owner: controlCenter, isRegularApp: false)
    }
    private var bar: WindowHolePolicy.Window {
        .init(bounds: menuBar, layer: 24, owner: 1, isRegularApp: false)
    }
    private let video = CGRect(x: 60, y: 40, width: 1100, height: 800)

    private func popoverPanel(_ bounds: CGRect, owner: Int32 = 30, radius: CGFloat? = nil,
                              measured: Bool = false) -> WindowHolePolicy.Window {
        .init(bounds: bounds, layer: WindowHolePolicy.statusLayer, owner: owner, isRegularApp: false,
              isMeasured: measured, cornerRadius: radius)
    }

    /// The excluded video window with `windows` in front, on a Mac that reports radii.
    private func overVideo(_ windows: [WindowHolePolicy.Window], radii: Bool = true) -> [CGRect] {
        WindowHolePolicy.neutralRegion(
            windows: windows + [bar, .init(bounds: video, layer: 0, owner: terminal)],
            owner: terminal, display: display, cornerRadius: 16, reportsCornerRadii: radii)
    }

    private var plainVideo: [CGRect] { WindowHolePolicy.roundedInterior(video, radius: 16) }

    @Test("An excluded menu-bar app's popover is neutral at the popover, not its window")
    func excludedPopoverIsNeutralAtItsBody() {
        for reported: CGFloat? in [nil, 0] {
            let region = WindowHolePolicy.neutralRegion(
                windows: [popoverPanel(popoverWindow, radius: reported), soloFanItem, bar],
                owner: terminal, display: display, cornerRadius: 16, floatingOwners: [soloFan],
                reportsCornerRadii: true)
            #expect(sameRegion(region, WindowHolePolicy.roundedInterior(
                popoverBody, radius: WindowHolePolicy.popoverCornerRadius)))
            // The margin around it stays warm.
            #expect(!isNeutral(region, CGPoint(x: popoverWindow.minX + 6, y: popoverWindow.midY)))
            #expect(!isNeutral(region, CGPoint(x: popoverWindow.midX, y: popoverWindow.maxY - 6)))
            #expect(isNeutral(region, CGPoint(x: popoverBody.minX + 1, y: popoverBody.midY)))
        }
    }

    @Test("Another menu-bar app's popover over an excluded window stays warm at the popover only")
    func otherPopoverStaysWarmAtItsBody() {
        // Also when the app owns its status item itself, as before macOS 26.
        let ownItem = WindowHolePolicy.Window(bounds: soloFanItem.bounds, layer: WindowHolePolicy.statusLayer,
                                              owner: soloFan, isRegularApp: false)
        #expect(sameRegion(overVideo([popoverPanel(popoverWindow), ownItem]),
                           overVideo([popoverPanel(popoverWindow), soloFanItem])))
        // Within the slack of the arrow's line.
        let lower = popoverWindow.offsetBy(dx: 0, dy: 1.5)
        #expect(!isNeutral(overVideo([popoverPanel(lower), soloFanItem]),
                           CGPoint(x: lower.midX, y: lower.midY)))
        let region = overVideo([popoverPanel(popoverWindow), soloFanItem])
        #expect(!isNeutral(region, CGPoint(x: popoverBody.midX, y: popoverBody.midY)))
        #expect(!isNeutral(region, CGPoint(x: popoverBody.minX + 1, y: popoverBody.midY)))
        // Its shadow margin and the square outside its corners show the excluded window.
        #expect(isNeutral(region, CGPoint(x: popoverWindow.minX + 6, y: popoverBody.midY)))
        #expect(isNeutral(region, CGPoint(x: popoverBody.minX + 0.5, y: popoverBody.maxY - 0.5)))
        let tiles = WindowHolePolicy.warmTiles(around: region, in: display)
        expectTilesMatch(tiles, hole: region, in: display)
    }

    @Test("Status-level windows that are not popovers keep the old behaviour")
    func statusWindowsThatAreNotPopovers() {
        // An accessory app's status-level window is not an occluder unless it is a popover.
        let cases: [(String, [WindowHolePolicy.Window])] = [
            ("the status item alone", [soloFanItem]),
            ("below the menu bar", [popoverPanel(CGRect(x: 300, y: 200, width: 366, height: 426)), soloFanItem]),
            ("reports its own radius", [popoverPanel(popoverWindow, radius: 12), soloFanItem]),
            ("spans the display", [popoverPanel(CGRect(x: -10, y: 5, width: 1532, height: 990)), soloFanItem]),
            ("invisible item", [popoverPanel(popoverWindow),
                                .init(bounds: soloFanItem.bounds, layer: WindowHolePolicy.statusLayer,
                                      owner: controlCenter, alpha: 0, isRegularApp: false)]),
            // The Dock lists empty status-level windows at the origin.
            ("empty item", [popoverPanel(CGRect(x: -20, y: 28, width: 366, height: 426)),
                            .init(bounds: .zero, layer: WindowHolePolicy.statusLayer, owner: 34, isRegularApp: false)]),
            ("item above the bar", [popoverPanel(popoverWindow),
                                    .init(bounds: CGRect(x: 460, y: -30, width: 46, height: 33),
                                          layer: WindowHolePolicy.statusLayer, owner: controlCenter, isRegularApp: false)]),
            // Another status-level panel under the bar is not a status item.
            ("item below the bar", [popoverPanel(popoverWindow),
                                    .init(bounds: CGRect(x: 460, y: 40, width: 46, height: 33),
                                          layer: WindowHolePolicy.statusLayer, owner: controlCenter, isRegularApp: false)]),
            // A notch tool's expanded panel starts at the top edge of the display.
            ("from the top edge", [popoverPanel(CGRect(x: 593, y: 0, width: 325, height: 200), owner: 31),
                                   .init(bounds: CGRect(x: 593, y: 0, width: 325, height: 32),
                                         layer: WindowHolePolicy.statusLayer, owner: 31, isRegularApp: false)]),
            // Aurell on macOS 26.6: its strip in the bar, and a panel it shows just under the bar.
            ("notch panel under the bar", [popoverPanel(CGRect(x: 515, y: 32, width: 480, height: 48), owner: 31),
                                           .init(bounds: CGRect(x: 593, y: 0, width: 325, height: 32),
                                                 layer: WindowHolePolicy.statusLayer, owner: 31, isRegularApp: false)]),
            ("too low for the arrow", [popoverPanel(popoverWindow.offsetBy(dx: 0, dy: 2)), soloFanItem]),
            ("too short", [popoverPanel(CGRect(x: 300, y: 28, width: 366, height: 40)), soloFanItem]),
            ("item on another layer", [popoverPanel(popoverWindow),
                                       .init(bounds: soloFanItem.bounds, layer: 101, owner: controlCenter,
                                             isRegularApp: false)]),
            ("item off the bar", [popoverPanel(CGRect(x: -20, y: 28, width: 366, height: 426)),
                                  .init(bounds: CGRect(x: -10, y: 0, width: 46, height: 33),
                                        layer: WindowHolePolicy.statusLayer, owner: controlCenter, isRegularApp: false)]),
            ("above the menu bar", [popoverPanel(popoverWindow.offsetBy(dx: 0, dy: -40)), soloFanItem]),
            // A strip under the bar with no status item of its app above it.
            ("no status item", [popoverPanel(CGRect(x: 0, y: 33, width: 1512, height: 300))]),
            ("item not under it", [popoverPanel(popoverWindow),
                                   .init(bounds: CGRect(x: 1200, y: 0, width: 46, height: 33),
                                         layer: WindowHolePolicy.statusLayer, owner: controlCenter, isRegularApp: false)]),
            ("too narrow", [popoverPanel(CGRect(x: 470, y: 28, width: 40, height: 426)), soloFanItem]),
        ]
        for (name, windows) in cases {
            #expect(sameRegion(overVideo(windows), plainVideo), "\(name)")
        }
        // Where WindowServer reports no radii (before macOS 26), a real popover keeps the old rules too.
        #expect(sameRegion(overVideo([popoverPanel(popoverWindow), soloFanItem], radii: false), plainVideo))
        // Without a menu bar listed there is nothing to hang from: the old window bounds.
        let neutral = WindowHolePolicy.neutralRegion(
            windows: [popoverPanel(popoverWindow)], owner: terminal, display: display, cornerRadius: 16,
            floatingOwners: [soloFan], reportsCornerRadii: true)
        #expect(sameRegion(neutral, WindowHolePolicy.roundedInterior(popoverWindow, radius: 16)))
    }

    @Test("The excluded app's own status-level panel under the menu bar is not shrunk")
    func excludedStatusPanelKeepsItsBounds() {
        // A floating toolbar of the excluded app, hanging from the bar, with no status item.
        let panel = CGRect(x: 200, y: 33, width: 700, height: 120)
        let region = WindowHolePolicy.neutralRegion(
            windows: [.init(bounds: panel, layer: WindowHolePolicy.statusLayer, owner: terminal), bar],
            owner: terminal, display: display, cornerRadius: 16, reportsCornerRadii: true)
        #expect(sameRegion(region, WindowHolePolicy.roundedInterior(panel, radius: 16)))
    }

    @Test("A popover on a second display is cut against that display's menu bar")
    func popoverOnSecondDisplay() {
        let second = CGRect(x: 1512, y: 0, width: 1920, height: 1080)
        let secondBar = WindowHolePolicy.Window(bounds: CGRect(x: 1512, y: 0, width: 1920, height: 25),
                                                layer: 24, owner: 1, isRegularApp: false)
        let window = CGRect(x: 2000, y: 20, width: 366, height: 426)
        let item = WindowHolePolicy.Window(bounds: CGRect(x: 2160, y: 0, width: 46, height: 25),
                                           layer: WindowHolePolicy.statusLayer, owner: controlCenter, isRegularApp: false)
        let excluded = CGRect(x: 1600, y: 60, width: 1200, height: 800)
        let windows = [popoverPanel(window), item, secondBar, bar, .init(bounds: excluded, layer: 0, owner: terminal)]
        let there = WindowHolePolicy.neutralRegion(
            windows: windows, owner: terminal, display: second, cornerRadius: 16, reportsCornerRadii: true)
        let body = window.insetBy(dx: 13, dy: 13)
        #expect(!isNeutral(there, CGPoint(x: body.midX, y: body.midY)))
        #expect(isNeutral(there, CGPoint(x: window.minX + 6, y: body.midY)))
        // The first display's menu bar does not count for it.
        let here = WindowHolePolicy.neutralRegion(
            windows: windows, owner: terminal, display: display, cornerRadius: 16, reportsCornerRadii: true)
        #expect(here.isEmpty)
    }

    @Test("This app's measured popover is never re-cut as another app's popover")
    func ownPopoverUnchanged() {
        // No radius, so only `isMeasured` keeps it out of the popover rule.
        let measured = CGRect(x: 300, y: 28, width: 330, height: 520)
        let item = WindowHolePolicy.Window(bounds: CGRect(x: 440, y: 0, width: 46, height: 33),
                                           layer: WindowHolePolicy.statusLayer, owner: controlCenter, isRegularApp: false)
        let region = overVideo([popoverPanel(measured, owner: 2, measured: true), item])
        #expect(!isNeutral(region, CGPoint(x: measured.minX + 1, y: measured.midY)))
        #expect(!isNeutral(region, CGPoint(x: measured.minX + 6, y: measured.midY)))
        #expect(isNeutral(region, CGPoint(x: measured.minX - 1, y: measured.midY)))
    }

    @Test("Only layer-0 windows are Stage Manager thumbnails")
    func stageThumbnailsAreLayerZero() {
        let frame = CGRect(x: 16, y: 216, width: 160, height: 120)
        // An excluded app's floating window that happens to sit on a thumbnail frame stays neutral.
        let floating = WindowHolePolicy.neutralRegion(windows: [
            .init(bounds: frame, layer: 0, owner: stageManager, isRegularApp: false, isStageManager: true),
            .init(bounds: frame, layer: 3, owner: finderApp, cornerRadius: 16),
        ], owner: finderApp, display: display, cornerRadius: 16)
        #expect(sameRegion(floating, WindowHolePolicy.roundedInterior(frame, radius: 16)))
        // A Stage Manager window on another layer is not a thumbnail frame.
        let raised = WindowHolePolicy.neutralRegion(windows: [
            .init(bounds: frame, layer: 3, owner: stageManager, isRegularApp: false, isStageManager: true),
            .init(bounds: frame, layer: 0, owner: finderApp, cornerRadius: 16),
        ], owner: finderApp, display: display, cornerRadius: 16)
        #expect(sameRegion(raised, WindowHolePolicy.roundedInterior(frame, radius: 16)))
        // Same origin and width, another height: not its twin.
        let taller = CGRect(x: 16, y: 216, width: 160, height: 300)
        let tall = WindowHolePolicy.neutralRegion(windows: [
            .init(bounds: frame, layer: 0, owner: stageManager, isRegularApp: false, isStageManager: true),
            .init(bounds: taller, layer: 0, owner: finderApp, cornerRadius: 16),
        ], owner: finderApp, display: display, cornerRadius: 16)
        #expect(sameRegion(tall, WindowHolePolicy.roundedInterior(taller, radius: 16)))
    }
}
