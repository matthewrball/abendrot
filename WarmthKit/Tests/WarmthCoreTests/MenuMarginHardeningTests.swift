import Testing
import Foundation
import CoreGraphics
@testable import WarmthCore

// Two ways #37's remembered margin went wrong, and the rules that fix them:
// - A titled window raised to the menu level and put flush under the menu bar proved "no margin"
// and removed the stored one.
// - A window dragged across displays read a margin larger than the menus', which was stored and
// could never come down.
// What is kept here are the proofs: the menu inside a proving window lies on its own display, and
// only the front app's menu with a menu's corner proves there is no margin. How readings are kept
// across samples and launches is in MenuMarginV3Tests.swift. Display and menus are the reporter's
// (macOS 27.2.1, 1512 x 982 pt, 33 pt menu bar).

private typealias Window = WindowHolePolicy.Window

private let builtIn = CGRect(x: 0, y: 0, width: 1512, height: 982)
private let bar = Window(bounds: CGRect(x: 0, y: 0, width: 1512, height: 33), layer: 24, owner: 1, isRegularApp: false)
private let finder: Int32 = 9
private let terminal: Int32 = 7
private let alertApp: Int32 = 31
private let build = "26B131"

/// `Finder (com.apple.finder) [app] layer 101 alpha 1.00 x -70 y -41 379x455 radius 0`: the menu
/// inside is x 5-234, y 34-339.
private let finderMenuWindow = CGRect(x: -70, y: -41, width: 379, height: 455)
/// Two more menus of the same menu bar, 75 pt padded, under other titles.
private let fileMenuWindow = CGRect(x: -35, y: -41, width: 410, height: 570)
private let editMenuWindow = CGRect(x: 15, y: -41, width: 390, height: 530)
/// The reporter's Terminal Help menu window, from the pasted window list.
private let helpMenuWindow = CGRect(x: 249, y: -41, width: 510, height: 278)

private func menu(_ bounds: CGRect, owner: Int32 = finder) -> Window {
    Window(bounds: bounds, layer: WindowHolePolicy.popUpMenuLayer, owner: owner)
}

/// A second display to the right, its top 100 pt lower, with a 25 pt menu bar, and an
/// alert with no reported radius (LuLu 4.5.7's glass alert on 27, any window on macOS 12-25) at the
/// top of the built-in display, dragged right until its middle is on the second display.
private let rightDisplay = CGRect(x: 1512, y: 100, width: 1920, height: 1080)
private let rightBar = Window(bounds: CGRect(x: 1512, y: 100, width: 1920, height: 25), layer: 24, owner: 1,
                              isRegularApp: false)
private let sideStraddleWindow = CGRect(x: 1250, y: 40, width: 667, height: 461)

private func proof(
    _ windows: [Window],
    displays: [CGRect] = [builtIn],
    titledRadius: CGFloat = 16,
    front: Int32? = finder
) -> WindowHolePolicy.MenuMarginProof? {
    WindowHolePolicy.menuMarginProof(in: windows, displays: displays, titledRadius: titledRadius, frontOwner: front)
}

private func padded(_ margin: CGFloat, _ window: CGRect, ambiguous: Bool = false) -> WindowHolePolicy.MenuMarginProof {
    .padded(margin, window: window, ambiguous: ambiguous)
}

/// Notes `proof` for as many samples in a row as a still window takes to count, and returns the writes.
private func hold(_ memory: inout SampledMenuMargin, _ proof: WindowHolePolicy.MenuMarginProof?) -> [MenuMarginMemory.Write] {
    (0..<SampledMenuMargin.heldSamples).compactMap { _ in memory.note(proof) }
}

private func saved(_ margin: CGFloat, on onBuild: String = build) -> MenuMarginMemory.Write {
    .save(MenuMarginMemory.Record(build: onBuild, margin: margin))
}

private func stored(_ margin: CGFloat, on onBuild: String = build) -> MenuMarginMemory.Record {
    MenuMarginMemory.Record(build: onBuild, margin: margin)
}

/// Same pieces in the same order, to within float rounding from clipping to the display.
private func sameRegion(_ a: [CGRect], _ b: [CGRect]) -> Bool {
    a.count == b.count && zip(a, b).allSatisfy { lhs, rhs in
        abs(lhs.minX - rhs.minX) < 1e-9 && abs(lhs.minY - rhs.minY) < 1e-9
            && abs(lhs.width - rhs.width) < 1e-9 && abs(lhs.height - rhs.height) < 1e-9
    }
}

private func area(_ rects: [CGRect]) -> CGFloat {
    rects.reduce(0) { $0 + $1.width * $1.height }
}

@Suite("Menu margin proofs: the menu on its own display, and the front app's menu corner (#37)")
struct MenuMarginHardeningTests {

    // MARK: A padded proof hangs inside its own display

    @Test("A window dragged across onto a display to the right, whose top is lower, proves no margin")
    func sideStraddleProvesNothing() {
        // Its middle is on the right display, and its top 86 pt above that display's menu line, but
        // the menu its bounds would hold (x 1336-1831) starts on the built-in display.
        let windows = [menu(sideStraddleWindow, owner: alertApp), rightBar, bar]
        let displays = [builtIn, rightDisplay]
        #expect(WindowHolePolicy.observedMenuMargin(in: windows, displays: displays) == nil)
        #expect(proof(windows, displays: displays, front: alertApp) == nil)
        // A stored 75 stays, and nothing is written, however long the window sits there.
        var memory = SampledMenuMargin(stored: stored(75), build: build)
        #expect(hold(&memory, proof(windows, displays: displays, front: alertApp)).isEmpty)
        #expect(memory.margin == 75)
    }

    @Test("The reporter's menus, and menus that hug a display's edges, still prove 75 pt")
    func realMenusStillProve() {
        for window in [finderMenuWindow, fileMenuWindow, editMenuWindow, helpMenuWindow] {
            #expect(proof([menu(window), bar]) == padded(75, window), "\(window)")
        }
        #expect(finderMenuWindow.insetBy(dx: 75, dy: 75) == CGRect(x: 5, y: 34, width: 229, height: 305))

        // The menu against the display's left edge, its right edge, and its bottom edge.
        let left = CGRect(x: -75, y: -41, width: 300, height: 400)
        let right = CGRect(x: 1287, y: -41, width: 300, height: 400)
        let tall = CGRect(x: 200, y: -41, width: 300, height: 1098)
        for window in [left, right, tall] {
            #expect(proof([menu(window), bar]) == padded(75, window), "\(window)")
        }
        // Up to 1 pt past an edge is still on the display; more is not.
        let slightlyPast = right.offsetBy(dx: 1, dy: 0)
        let pastRight = right.offsetBy(dx: 1.5, dy: 0)
        let pastLeft = left.offsetBy(dx: -1.5, dy: 0)
        let pastBottom = CGRect(x: 200, y: -41, width: 300, height: 1099.5)
        #expect(proof([menu(slightlyPast), bar]) == padded(75, slightlyPast))
        for window in [pastRight, pastLeft, pastBottom] {
            #expect(WindowHolePolicy.observedMenuMargin(in: [menu(window), bar], displays: [builtIn]) == nil, "\(window)")
        }

        // A menu against the left edge of the display to the right: its window reaches back over the
        // built-in display, but the menu is on its own display. Its part above that display's top
        // edge lies on the built-in one, so the reading is ambiguous (MenuMarginV3Tests).
        let besideWindow = CGRect(x: 1437, y: 51, width: 300, height: 400)
        let beside = [menu(besideWindow), rightBar, bar]
        #expect(proof(beside, displays: [builtIn, rightDisplay]) == padded(75, besideWindow, ambiguous: true))
        // Further from that edge, the part above the top is over nothing.
        let furtherWindow = CGRect(x: 1600, y: 51, width: 300, height: 400)
        #expect(proof([menu(furtherWindow), rightBar, bar], displays: [builtIn, rightDisplay]) == padded(75, furtherWindow))
    }

    // MARK: Proof of no margin

    /// macOS 26.6: the front app's menu-bar menu is the window itself, 12 pt corner, top on the line.
    private let unpaddedMenuWindow = CGRect(x: 6, y: 34, width: 263, height: 305)

    @Test("A titled window or panel raised to the menu level and flush under the bar is no proof of no margin")
    func titledWindowsProveNothing() {
        // A titled window at CG minY 33, with the titled corner.
        let titledAtTop = Window(bounds: CGRect(x: 300, y: 33, width: 667, height: 461), layer: 101, owner: alertApp,
                                 cornerRadius: 16)
        #expect(proof([titledAtTop, bar], front: alertApp) == nil)
        // A titled utility panel on the menu line: 15 pt.
        let panel = Window(bounds: CGRect(x: 300, y: 34, width: 400, height: 300), layer: 101, owner: alertApp,
                           cornerRadius: 15)
        #expect(proof([panel, bar], front: alertApp) == nil)

        // The stored 75 stays, and the next context menu is cut at the menu.
        var memory = SampledMenuMargin(stored: stored(75), build: build)
        #expect(hold(&memory, proof([titledAtTop, bar], front: alertApp)).isEmpty)
        #expect(memory.margin == 75)
        let context = CGRect(x: 520, y: 300, width: 366, height: 455)
        let region = WindowHolePolicy.neutralRegion(
            windows: [menu(context), titledAtTop, bar], owner: finder, display: builtIn, cornerRadius: 16,
            menuMargin: memory.margin, reportsCornerRadii: true)
        #expect(sameRegion(region, WindowHolePolicy.roundedInterior(
            context.insetBy(dx: 75, dy: 75), radius: WindowHolePolicy.paddedMenuCornerRadius)))
        let menuArea: CGFloat = 216 * 305
        #expect(area(region) < menuArea)
    }

    @Test("Only the front app's menu with a corner well inside the titled one proves no margin")
    func onlyFrontMenusProveNoMargin() {
        let menu26 = Window(bounds: unpaddedMenuWindow, layer: 101, owner: terminal, cornerRadius: 12)
        // A real macOS 26 menu-bar menu of the front app.
        #expect(proof([menu26, bar], front: terminal) == .unpadded)
        // The same window of an app that is not in front.
        #expect(proof([menu26, bar], front: finder) == nil)
        // Nothing known about the front app or the titled corner: nothing proves it.
        #expect(proof([menu26, bar], front: nil) == nil)
        #expect(proof([menu26, bar], titledRadius: 0, front: terminal) == nil)
        #expect(proof([menu26, bar], titledRadius: .nan, front: terminal) == nil)
        // Just under the panel's corner still counts; the panel's does not.
        for (radius, proves) in [(CGFloat(13.9), true), (14.99, true), (15, false), (16, false), (20, false)] {
            let window = Window(bounds: unpaddedMenuWindow, layer: 101, owner: terminal, cornerRadius: radius)
            #expect((proof([window, bar], front: terminal) == .unpadded) == proves, "radius \(radius)")
        }
        // The default parameters prove nothing.
        #expect(WindowHolePolicy.menuMarginProof(in: [menu26, bar], displays: [builtIn]) == nil)
    }

    // MARK: Where nothing persists (macOS 12-25)

    @Test("Where WindowServer reports no radii nothing is loaded or stored, so every launch starts as in 1.1.19")
    func nothingPersistsWithoutRadii() {
        let pre26 = "24G84"
        // A record of this very build, such as an 86 read from a window across two displays, is not loaded.
        let memory = MenuMarginMemory(stored: stored(86, on: pre26), build: pre26, persists: false)
        #expect(memory.margin == 0)
        #expect(memory.stored == nil)

        // In a session readings still apply, but nothing is written, not a raise and not a clear. A
        // larger reading from one window raises nothing once a margin is known.
        var session = SampledMenuMargin(stored: stored(86, on: pre26), build: pre26, persists: false)
        #expect(hold(&session, padded(75, finderMenuWindow)).isEmpty)
        #expect(session.margin == 75)
        #expect(hold(&session, padded(86, sideStraddleWindow)).isEmpty)
        #expect(session.margin == 75)
        #expect(session.note(.unpadded) == nil)
        #expect(session.margin == 0)

        // After a relaunch the excluded app's own 263 x 305 pt menu (no radius there) is neutral at its
        // bounds and the titled corner, as in 1.1.19, not cut 86 pt inside.
        let relaunched = MenuMarginMemory(stored: stored(86, on: pre26), build: pre26, persists: false)
        let ownMenu = Window(bounds: unpaddedMenuWindow, layer: 101, owner: terminal)
        let region = WindowHolePolicy.neutralRegion(
            windows: [ownMenu, bar], owner: terminal, display: builtIn, cornerRadius: 10, menuMargin: relaunched.margin)
        #expect(sameRegion(region, WindowHolePolicy.roundedInterior(unpaddedMenuWindow, radius: 10)))
        let nearlyWholeMenu: CGFloat = 80_000
        #expect(area(region) > nearlyWholeMenu)

        // Where radii are reported, the same record is loaded.
        let on26 = MenuMarginMemory(stored: stored(75), build: build, persists: true)
        #expect(on26.margin == 75)
    }
}
