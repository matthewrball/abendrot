import Testing
import Foundation
import CoreGraphics
@testable import WarmthCore

// Issue #38: ordinary windows that an app raises to the pop-up menu level (layer 101), such as
// LuLu's connection alert, were cut 75 pt inside their edges, as if they were the transparent
// window of a padded macOS 27 menu. Numbers come from the reporter's 27.2.1 window lists and the
// LuLu alert screenshot (1350 x 938 px at 2x).

private let display = CGRect(x: 0, y: 0, width: 1512, height: 982)
private let margin: CGFloat = 75
private let windowServer: Int32 = 1
private let terminal: Int32 = 7
private let finder: Int32 = 9
private let lulu: Int32 = 31
private let menuBarApp: Int32 = 5

/// `Window Server layer 24 x 0 y 0 1512x33`.
private let menuBar = WindowHolePolicy.Window(
    bounds: CGRect(x: 0, y: 0, width: 1512, height: 33), layer: 24, owner: windowServer, isRegularApp: false)

/// `Finder (com.apple.finder) [app] layer 101 alpha 1.00 x -70 y -41 379x455 radius 0`: a padded
/// menu-bar menu, its top 75 pt above the line under the menu bar.
private let finderMenuWindow = CGRect(x: -70, y: -41, width: 379, height: 455)

/// `Terminal (com.apple.Terminal) [app] layer 0 alpha 1.00 x 382 y 140 961x511 radius 16`.
private let terminalWindow = CGRect(x: 382, y: 140, width: 961, height: 511)

/// LuLu's alert as the screenshot shows it: 667 x 461 pt (LuLu's AlertWindow.xib is 667 pt wide),
/// centred by LuLu. The neutral box in the screenshot is 517 x 311 pt, 75 pt in from every edge.
private let alert = CGRect(x: 422, y: 180, width: 667, height: 461)

/// LuLu shows the alert as a titled window, then raises it to `NSPopUpMenuWindowLevel` (layer 101)
/// and, while a window is up, runs as a regular app. An opaque titled window reports the titled
/// radius (16 pt on macOS 26.6, also at layer 101), as LuLu's alert did before LuLu 4.5.7 made it
/// clear behind glass; the glass alert reports none.
private func luluAlert(radius: CGFloat?, owner: Int32 = lulu, regular: Bool = true) -> WindowHolePolicy.Window {
    WindowHolePolicy.Window(bounds: alert, layer: WindowHolePolicy.popUpMenuLayer, owner: owner,
                            isRegularApp: regular, cornerRadius: radius)
}

private func area(_ rects: [CGRect]) -> CGFloat {
    rects.reduce(0) { $0 + $1.width * $1.height }
}

private func isNeutral(_ region: [CGRect], _ point: CGPoint) -> Bool {
    region.contains { $0.contains(point) }
}

/// Same pieces in the same order, to within float rounding from clipping to the display.
private func sameRegion(_ a: [CGRect], _ b: [CGRect]) -> Bool {
    a.count == b.count && zip(a, b).allSatisfy { lhs, rhs in
        abs(lhs.minX - rhs.minX) < 1e-9 && abs(lhs.minY - rhs.minY) < 1e-9
            && abs(lhs.width - rhs.width) < 1e-9 && abs(lhs.height - rhs.height) < 1e-9
    }
}

/// Every sample point is warm exactly when it is outside the hole, and never covered twice.
private func expectTilesMatch(_ region: [CGRect]) {
    let tiles = WindowHolePolicy.warmTiles(around: region, in: display)
    for x in stride(from: display.minX + 3, to: display.maxX, by: 37) {
        for y in stride(from: display.minY + 3, to: display.maxY, by: 29) {
            let point = CGPoint(x: x, y: y)
            let covering = tiles.filter { $0.contains(point) }.count
            let expected = isNeutral(region, point) ? 0 : 1
            #expect(covering == expected, "point \(point)")
        }
    }
}

/// Points in the 75 pt band just inside each edge of `rect`: the part 1.1.19 left out.
private func band(_ rect: CGRect) -> [CGPoint] {
    let inset: CGFloat = 30
    return [CGPoint(x: rect.minX + inset, y: rect.midY), CGPoint(x: rect.maxX - inset, y: rect.midY),
            CGPoint(x: rect.midX, y: rect.minY + inset), CGPoint(x: rect.midX, y: rect.maxY - inset)]
}

@Suite("Ordinary windows at the pop-up menu level (#38)")
struct MenuLevelPanelTests {

    // MARK: The excluded app's alert

    @Test("An opaque titled alert raised to the menu level is neutral at its own bounds and radius, not 75 pt inside")
    func excludedAlertIsNeutralAtItsBounds() {
        for radius: CGFloat in [16, 20, 26] {
            let region = WindowHolePolicy.neutralRegion(
                windows: [luluAlert(radius: radius), menuBar],
                owner: lulu, display: display, cornerRadius: 16, menuMargin: margin)
            #expect(sameRegion(region, WindowHolePolicy.roundedInterior(alert, radius: radius)), "radius \(radius)")
            for point in band(alert) {
                #expect(isNeutral(region, point), "radius \(radius), band point \(point)")
            }
            // Outside its own curve the alert's corner stays warm.
            #expect(!isNeutral(region, CGPoint(x: alert.minX + 0.5, y: alert.minY + 0.5)))
            expectTilesMatch(region)
        }
    }

    @Test("The alert is neutral at its bounds after its app loses focus too, as a floating window")
    func unfocusedExcludedAlertIsNeutralAtItsBounds() {
        // Terminal is in front, with its window clear of the alert.
        let front = CGRect(x: 20, y: 700, width: 300, height: 200)
        let region = WindowHolePolicy.neutralRegion(
            windows: [luluAlert(radius: 16), menuBar, .init(bounds: front, layer: 0, owner: terminal, cornerRadius: 16)],
            owner: terminal, display: display, cornerRadius: 16, floatingOwners: [lulu], menuMargin: margin)
        let expected = WindowHolePolicy.roundedInterior(alert, radius: 16)
            + WindowHolePolicy.roundedInterior(front, radius: 16)
        #expect(sameRegion(region, expected))
        for point in band(alert) {
            #expect(isNeutral(region, point), "band point \(point)")
        }
    }

    @Test("An accessory app's own alert at the menu level is neutral at its bounds when it is excluded")
    func excludedAccessoryAlertIsNeutralAtItsBounds() {
        let region = WindowHolePolicy.neutralRegion(
            windows: [luluAlert(radius: 16, regular: false), menuBar],
            owner: lulu, display: display, cornerRadius: 16, menuMargin: margin)
        #expect(sameRegion(region, WindowHolePolicy.roundedInterior(alert, radius: 16)))
    }

    @Test("A small window that reports a radius is not dropped as too small to hold a padded menu")
    func smallRoundedWindowIsNotDropped() {
        let small = CGRect(x: 400, y: 300, width: 150, height: 120)
        let region = WindowHolePolicy.neutralRegion(
            windows: [.init(bounds: small, layer: WindowHolePolicy.popUpMenuLayer, owner: lulu, cornerRadius: 16)],
            owner: lulu, display: display, cornerRadius: 16, menuMargin: margin)
        #expect(sameRegion(region, WindowHolePolicy.roundedInterior(small, radius: 16)))
    }

    // MARK: Another app's alert over the excluded window

    @Test("Another app's alert at the menu level stays warm at its full bounds over an excluded window")
    func otherAppsAlertOccludesAtItsBounds() {
        let windows: [WindowHolePolicy.Window] = [
            luluAlert(radius: 16),
            menuBar,
            .init(bounds: terminalWindow, layer: 0, owner: terminal, cornerRadius: 16),
        ]
        let region = WindowHolePolicy.neutralRegion(
            windows: windows, owner: terminal, display: display, cornerRadius: 16, menuMargin: margin)
        // The alert lies wholly inside Terminal's window, away from its corners.
        let expected = area(WindowHolePolicy.roundedInterior(terminalWindow, radius: 16))
            - alert.width * alert.height + area(WindowHolePolicy.roundedExterior(alert, radius: 16))
        #expect(abs(area(region) - expected) < 1e-6)
        for point in band(alert) + [CGPoint(x: alert.midX, y: alert.midY)] {
            #expect(!isNeutral(region, point), "alert point \(point)")
        }
        // Outside the alert's own curve the excluded window shows.
        #expect(isNeutral(region, CGPoint(x: alert.minX + 0.5, y: alert.minY + 0.5)))
        #expect(isNeutral(region, CGPoint(x: alert.maxX - 0.5, y: alert.maxY - 0.5)))
        #expect(isNeutral(region, CGPoint(x: alert.minX - 2, y: alert.midY)))
        expectTilesMatch(region)
        // The menu margin plays no part: the same list without a proven margin gives the same hole.
        let noMargin = WindowHolePolicy.neutralRegion(
            windows: windows, owner: terminal, display: display, cornerRadius: 16, menuMargin: 0)
        let identical = region == noMargin
        #expect(identical)
    }

    @Test("Another accessory app's rounded window does not cut a box while that app has no menu open")
    func otherAccessoryWindowStillIgnored() {
        // Unchanged since 1.1.16: with padded menus, an accessory app's menu-level window is only
        // trusted while that app has a menu hanging from the menu bar. The volume control is one.
        let excluded = CGRect(x: 60, y: 40, width: 1100, height: 800)
        let region = WindowHolePolicy.neutralRegion(windows: [
            luluAlert(radius: 16, owner: menuBarApp, regular: false),
            menuBar,
            .init(bounds: excluded, layer: 0, owner: terminal),
        ], owner: terminal, display: display, menuMargin: margin)
        let whole: [CGRect] = [excluded]
        let untouched = region == whole
        #expect(untouched)
    }

    @Test("A rounded accessory window is no proof that its app has a menu hanging from the menu bar")
    func roundedWindowProvesNoMenuOwner() {
        // An accessory app's rounded window that happens to start where a padded menu would, and an
        // overlay of the same app. Neither is trusted as a menu, so neither cuts a warm box.
        let excluded = CGRect(x: 60, y: 40, width: 1100, height: 800)
        let hanging = CGRect(x: 600, y: -41, width: 400, height: 300)
        let overlay = CGRect(x: 200, y: 400, width: 300, height: 250)
        let region = WindowHolePolicy.neutralRegion(windows: [
            .init(bounds: hanging, layer: WindowHolePolicy.popUpMenuLayer, owner: menuBarApp,
                  isRegularApp: false, cornerRadius: 16),
            .init(bounds: overlay, layer: WindowHolePolicy.popUpMenuLayer, owner: menuBarApp, isRegularApp: false),
            menuBar,
            .init(bounds: excluded, layer: 0, owner: terminal),
        ], owner: terminal, display: display, menuMargin: margin)
        let whole: [CGRect] = [excluded]
        let untouched = region == whole
        #expect(untouched)

        // A padded menu of the same app, hanging from the menu bar, still makes its submenu a menu.
        let menuWindow = CGRect(x: 600, y: -41, width: 400, height: 300)
        let trusted = WindowHolePolicy.neutralRegion(windows: [
            .init(bounds: menuWindow, layer: WindowHolePolicy.popUpMenuLayer, owner: menuBarApp, isRegularApp: false),
            .init(bounds: overlay, layer: WindowHolePolicy.popUpMenuLayer, owner: menuBarApp, isRegularApp: false),
            menuBar,
            .init(bounds: excluded, layer: 0, owner: terminal),
        ], owner: terminal, display: display, menuMargin: margin)
        #expect(!isNeutral(trusted, CGPoint(x: overlay.midX, y: overlay.midY)))
        #expect(isNeutral(trusted, CGPoint(x: overlay.minX + 30, y: overlay.midY)))
    }

    // MARK: Real padded menus

    @Test("The reporter's padded Finder menu is still cut at the menu inside its window")
    func paddedFinderMenuUnchanged() {
        let body = finderMenuWindow.insetBy(dx: margin, dy: margin)
        for reported: CGFloat? in [nil, 0] {
            let region = WindowHolePolicy.neutralRegion(windows: [
                .init(bounds: finderMenuWindow, layer: WindowHolePolicy.popUpMenuLayer, owner: finder,
                      cornerRadius: reported),
                menuBar,
            ], owner: finder, display: display, cornerRadius: 16, menuMargin: margin)
            #expect(sameRegion(region, WindowHolePolicy.roundedInterior(
                body.intersection(display), radius: WindowHolePolicy.paddedMenuCornerRadius)))
        }
        // The menu's position: under the 33 pt menu bar, 229 x 305 pt.
        #expect(body == CGRect(x: 5, y: 34, width: 229, height: 305))
    }

    @Test("Another app's padded menu over an excluded window still stays warm at the menu only")
    func warmPaddedMenuUnchanged() {
        let window = CGRect(x: 500, y: 200, width: 334, height: 455)
        let menu = window.insetBy(dx: margin, dy: margin)
        let region = WindowHolePolicy.neutralRegion(windows: [
            .init(bounds: window, layer: WindowHolePolicy.popUpMenuLayer, owner: finder, cornerRadius: 0),
            menuBar,
            .init(bounds: terminalWindow, layer: 0, owner: terminal, cornerRadius: 16),
        ], owner: terminal, display: display, cornerRadius: 16, menuMargin: margin)
        let expected = area(WindowHolePolicy.roundedInterior(terminalWindow, radius: 16))
            - menu.width * menu.height
            + area(WindowHolePolicy.roundedExterior(menu, radius: WindowHolePolicy.paddedMenuCornerRadius))
        #expect(abs(area(region) - expected) < 1e-6)
        #expect(isNeutral(region, CGPoint(x: window.minX + 30, y: window.midY)))
        #expect(!isNeutral(region, CGPoint(x: menu.midX, y: menu.midY)))
    }

    @Test("A menu-level window with no known radius is still taken for a padded menu, as in 1.1.19")
    func unknownRadiusKeepsTheMenuRule() {
        // What happens to an alert that reports no radius: without other evidence it cannot be told
        // from a padded menu, so it is cut at the menu inside it with the menu's corner. This is the
        // box in the reporter's screenshot: LuLu 4.5.7 makes its titled alert clear behind a glass
        // view, and such a window reports radius 0 (a stand-in on macOS 26.6; the box's 13 pt
        // corners on 27.2.1). Nothing in the window list was found to tell it from a menu.
        for reported: CGFloat? in [nil, 0, -.infinity, .nan] {
            let region = WindowHolePolicy.neutralRegion(
                windows: [luluAlert(radius: reported), menuBar],
                owner: lulu, display: display, cornerRadius: 16, menuMargin: margin)
            #expect(sameRegion(region, WindowHolePolicy.roundedInterior(
                alert.insetBy(dx: margin, dy: margin), radius: WindowHolePolicy.paddedMenuCornerRadius)))
        }
    }

    // MARK: Proving the margin

    @Test("A window that reports a radius proves no menu margin, even where a padded menu would hang")
    func roundedWindowProvesNoMargin() {
        // A regular app's window raised to the menu level, placed where a padded menu-bar menu would
        // start (its top 75 pt above the line under the menu bar). WindowServer rounds it at its own
        // bounds, so it carries no transparent margin and is no proof of one.
        let hanging = CGRect(x: 249, y: -41, width: 510, height: 278)
        let rounded = WindowHolePolicy.Window(
            bounds: hanging, layer: WindowHolePolicy.popUpMenuLayer, owner: lulu, cornerRadius: 16)
        #expect(WindowHolePolicy.observedMenuMargin(in: [rounded, menuBar], displays: [display]) == nil)
        #expect(WindowHolePolicy.menuMarginProof(in: [rounded, menuBar], displays: [display]) == nil)

        // The same window with no radius still proves the margin, as a padded menu does.
        for reported: CGFloat? in [nil, 0] {
            let padded = WindowHolePolicy.Window(
                bounds: hanging, layer: WindowHolePolicy.popUpMenuLayer, owner: lulu, cornerRadius: reported)
            #expect(WindowHolePolicy.observedMenuMargin(in: [padded, menuBar], displays: [display]) == margin)
        }
        // Beside the reporter's padded Finder menu, it does not change the margin it proves.
        let finderMenu = WindowHolePolicy.Window(
            bounds: finderMenuWindow, layer: WindowHolePolicy.popUpMenuLayer, owner: finder, cornerRadius: 0)
        #expect(WindowHolePolicy.observedMenuMargin(
            in: [rounded, finderMenu, menuBar], displays: [display]) == margin)
    }

    // MARK: No proven margin (macOS 26 and earlier)

    @Test("Without a proven margin the menu-level path gives exactly the 1.1.19 hole")
    func noMarginMatchesOldBehaviour() {
        // 1.1.19 with no margin: every menu-level window counts at its bounds, at its own radius, or
        // at the titled radius when neutral and square when warm if it reports none.
        for reported: CGFloat? in [nil, 0, 12, 16] {
            let known = reported.flatMap { $0 > 0 ? $0 : nil }
            let neutral = WindowHolePolicy.neutralRegion(
                windows: [luluAlert(radius: reported), menuBar],
                owner: lulu, display: display, cornerRadius: 16)
            #expect(sameRegion(neutral, WindowHolePolicy.roundedInterior(alert, radius: known ?? 16)))

            let warm = WindowHolePolicy.neutralRegion(windows: [
                luluAlert(radius: reported),
                .init(bounds: terminalWindow, layer: 0, owner: terminal, cornerRadius: 16),
            ], owner: terminal, display: display, cornerRadius: 16)
            let expected = area(WindowHolePolicy.roundedInterior(terminalWindow, radius: 16))
                - alert.width * alert.height + area(WindowHolePolicy.roundedExterior(alert, radius: known ?? 0))
            #expect(abs(area(warm) - expected) < 1e-6, "reported \(String(describing: reported))")
        }
    }
}
