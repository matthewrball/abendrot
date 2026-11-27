import Testing
import Foundation
import CoreGraphics
@testable import WarmthCore

// How #37's menu margin is kept:
// - When a margin had to be confirmed by a second menu, a session with one menu-bar menu stored
// nothing, so #37's own steps still showed the box after a relaunch. The first menu-bar menu is
// stored.
// - Two menus opened at one height near the top confirmed and stored a smaller margin. No reading
// lowers the margin; only a proof of no margin does.
// - A window that slides at the menu level from above the top edge reads a different margin every
// frame (Ghostty's quick terminal: a borderless, non-activating panel raised to `.popUpMenu` for
// its slide, from `y = visibleFrame.maxY`). Every reading now has to hold still first.
// Display, menu bar and menus are the reporter's (macOS 27.2.1, 1512 x 982 pt, 33 pt menu bar).

private typealias Window = WindowHolePolicy.Window

private let builtIn = CGRect(x: 0, y: 0, width: 1512, height: 982)
private let bar = Window(bounds: CGRect(x: 0, y: 0, width: 1512, height: 33), layer: 24, owner: 1, isRegularApp: false)
private let finder: Int32 = 9
private let terminal: Int32 = 7
private let ghostty: Int32 = 44
private let alertApp: Int32 = 31
private let build = "26B131"

/// Finder's File and Edit menus, 75 pt padded, hanging from the menu bar.
private let fileMenu = CGRect(x: -35, y: -41, width: 410, height: 570)
private let editMenu = CGRect(x: 15, y: -41, width: 390, height: 530)
/// Two menus anchored at one height near the top: two pop-up or pull-down buttons in one toolbar row
/// of a window flush under the menu bar, or two right-clicks at one height. Their windows start
/// 25 pt above the display and read 59.
private let rowA = CGRect(x: 1000, y: -25, width: 366, height: 455)
private let rowB = CGRect(x: 300, y: -25, width: 300, height: 380)
/// The desktop context menu after launch (screenshot db35894d): a 216 x 305 pt menu in its window.
private let context = CGRect(x: 520, y: 300, width: 366, height: 455)

/// A display stacked below the built-in one, with a 25 pt menu bar: menus hang from y 1008.
private let below = CGRect(x: 0, y: 982, width: 1920, height: 1080)
private let belowBar = Window(bounds: CGRect(x: 0, y: 982, width: 1920, height: 25), layer: 24, owner: 1,
                              isRegularApp: false)
/// An alert dragged down across onto it (reads 108), and another window there that reads the same.
private let straddleA = CGRect(x: 400, y: 900, width: 667, height: 461)
private let straddleB = CGRect(x: 900, y: 900, width: 500, height: 400)
/// Finder's File and Edit menus hanging from the lower display's menu bar: their windows start
/// 75 pt above y 1008, on the built-in display.
private let fileMenuBelow = CGRect(x: -35, y: 933, width: 410, height: 570)
private let editMenuBelow = CGRect(x: 15, y: 933, width: 390, height: 530)

private func menu(_ bounds: CGRect, owner: Int32 = finder) -> Window {
    Window(bounds: bounds, layer: WindowHolePolicy.popUpMenuLayer, owner: owner)
}

/// The proof the backend takes from a sample, the 16 pt titled corner, Finder in front.
private func proof(_ windows: [Window], stacked: Bool = false, front: Int32? = finder) -> WindowHolePolicy.MenuMarginProof? {
    WindowHolePolicy.menuMarginProof(
        in: windows + (stacked ? [belowBar, bar] : [bar]), displays: stacked ? [builtIn, below] : [builtIn],
        titledRadius: 16, frontOwner: front)
}

/// Notes `proof` for `samples` samples in a row (a menu held open), and returns the writes.
private func hold(
    _ memory: inout SampledMenuMargin,
    _ proof: WindowHolePolicy.MenuMarginProof?,
    samples: Int = SampledMenuMargin.heldSamples
) -> [MenuMarginMemory.Write] {
    (0..<samples).compactMap { _ in memory.note(proof) }
}

private func saved(_ margin: CGFloat, on onBuild: String = build) -> MenuMarginMemory.Write {
    .save(MenuMarginMemory.Record(build: onBuild, margin: margin))
}

/// One save, as the writes of a stretch of samples, typed so the comparison stays cheap to check.
private func savedOnly(_ margin: CGFloat) -> [MenuMarginMemory.Write] {
    [saved(margin)]
}

private func record(_ margin: CGFloat) -> MenuMarginMemory.Record {
    MenuMarginMemory.Record(build: build, margin: margin)
}

/// The excluded Finder's desktop context menu with this margin, as the backend cuts it.
private func contextRegion(_ margin: CGFloat) -> [CGRect] {
    WindowHolePolicy.neutralRegion(windows: [menu(context), bar], owner: finder, display: builtIn,
                                   cornerRadius: 16, menuMargin: margin, reportsCornerRadii: true)
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

/// Ghostty's quick terminal (1200 x 400 pt, centred) sliding down from above the top edge to just
/// under the menu bar in 12 frames, ease-in, one sample per frame: from y 33 - 400 to y 33.
private let slideIn: [CGRect] = (0...12).map { frame in
    let progress = CGFloat(frame) / 12
    return CGRect(x: 156, y: -367 + 400 * progress * progress, width: 1200, height: 400)
}

@Suite("Menu margin: what is kept, what raises it and what lowers it (#37)")
struct MenuMarginV3Tests {

    // MARK: The first menu-bar menu is kept

    @Test("The reporter's steps: one Finder menu, then a relaunch: 75 is stored and the context menu is cut at the menu")
    func oneMenuIsStored() {
        var memory = SampledMenuMargin(stored: nil, build: build)
        var writes: [MenuMarginMemory.Write] = []
        for sample in 1...60 {
            if let write = memory.note(proof([menu(fileMenu)])) { writes.append(write) }
            // The first 0.2 s of the first menu on a new build is still cut at its window: sample 13
            // comes 0.2 s after the first, give or take rounding.
            if sample <= 12 { #expect(memory.margin == 0, "sample \(sample)") }
            if sample >= 14 { #expect(memory.margin == 75, "sample \(sample)") }
        }
        #expect(writes == savedOnly(75))
        #expect(memory.stored == record(75))

        let relaunched = MenuMarginMemory(stored: memory.stored, build: build)
        let region = contextRegion(relaunched.margin)
        #expect(sameRegion(region, WindowHolePolicy.roundedInterior(context.insetBy(dx: 75, dy: 75),
                                                                    radius: WindowHolePolicy.paddedMenuCornerRadius)))
        // Without the record, 166,311 pt2 here, against the menu's 65,880.
        let menuArea: CGFloat = 216 * 305
        #expect(area(region) <= menuArea)
        #expect(area(contextRegion(0)) > 166_000)
    }

    // MARK: Nothing lowers the margin but a proof of no margin

    @Test("File, then two menus anchored at one height near the top: nothing below 75 is stored")
    func anchoredMenusAfterAMenuBarMenu() {
        #expect(proof([menu(rowA)]) == .padded(59, window: rowA, ambiguous: false))
        #expect(proof([menu(rowB)]) == .padded(59, window: rowB, ambiguous: false))
        var memory = SampledMenuMargin(stored: nil, build: build)
        var writes: [MenuMarginMemory.Write] = []
        for window in [fileMenu, rowA, rowB, fileMenu] {
            writes += hold(&memory, proof([menu(window)]), samples: 30)
        }
        #expect(writes == savedOnly(75))
        #expect(memory.margin == 75)
        let next = MenuMarginMemory(stored: memory.stored, build: build)
        #expect(next.margin == 75)
        // Not a 16 pt band around the menu (83,448 pt2 at 59).
        let menuArea: CGFloat = 216 * 305
        #expect(area(contextRegion(next.margin)) <= menuArea)
    }

    @Test("A stored 75, then two anchored menus before any menu-bar menu: nothing is written")
    func anchoredMenusBeforeAnyMenuBarMenu() {
        var memory = SampledMenuMargin(stored: record(75), build: build)
        var writes: [MenuMarginMemory.Write] = []
        for window in [rowA, rowB, fileMenu] {
            writes += hold(&memory, proof([menu(window)]), samples: 30)
        }
        #expect(writes.isEmpty)
        #expect(memory.margin == 75)
    }

    @Test("Only a proof of no margin lowers it: to zero, removing the record; a padded menu raises it again")
    func onlyTheZeroProofLowers() {
        var memory = SampledMenuMargin(stored: record(75), build: build)
        for window in [rowA, rowB, fileMenu, editMenu] {
            #expect(hold(&memory, proof([menu(window)])).isEmpty)
        }
        // The front app's macOS 26 menu-bar menu: the window is the menu, 12 pt corner.
        let unpadded = Window(bounds: CGRect(x: 6, y: 34, width: 263, height: 305), layer: 101, owner: terminal,
                              cornerRadius: 12)
        #expect(memory.note(proof([unpadded], front: terminal)) == .clear)
        #expect(memory.margin == 0)
        #expect(memory.stored == nil)
        #expect(hold(&memory, proof([unpadded], front: terminal)).isEmpty)
        #expect(hold(&memory, proof([menu(fileMenu)])) == savedOnly(75))
    }

    @Test("Known residual: on a new build, anchored menus seen first store 59; two menu-bar menus of different sizes raise it")
    func anchoredMenusFirstOnANewBuild() {
        var memory = SampledMenuMargin(stored: nil, build: build)
        #expect(hold(&memory, proof([menu(rowA)])) == savedOnly(59))
        #expect(memory.margin == 59)
        #expect(hold(&memory, proof([menu(rowB)])).isEmpty)
        // A smaller box than 1.1.19's (the whole window), healed once two menu-bar menus agree.
        #expect(area(contextRegion(59)) < area(contextRegion(0)))
        #expect(hold(&memory, proof([menu(fileMenu)])).isEmpty)
        #expect(memory.margin == 59)
        #expect(hold(&memory, proof([menu(editMenu)])) == savedOnly(75))
        #expect(memory.margin == 75)
    }

    @Test("One write per increase, none per sample")
    func onePerIncrease() {
        var memory = SampledMenuMargin(stored: nil, build: build)
        var writes: [MenuMarginMemory.Write] = []
        let session: [[Window]] = Array(repeating: [], count: 30) + Array(repeating: [menu(rowA)], count: 90)
            + Array(repeating: [], count: 10) + Array(repeating: [menu(fileMenu)], count: 300)
            + Array(repeating: [menu(rowB)], count: 120) + Array(repeating: [menu(editMenu)], count: 200)
            + Array(repeating: [], count: 30)
        for sample in session {
            if let write = memory.note(sample.isEmpty ? nil : proof(sample)) { writes.append(write) }
        }
        let upTwice: [MenuMarginMemory.Write] = [saved(59), saved(75)]
        #expect(writes == upTwice)
    }

    // MARK: A reading counts only from a window that holds still

    @Test("A Ghostty quick terminal sliding in and out at the menu level moves no margin and writes nothing")
    func slidingWindowCountsForNothing() {
        // Several frames of the slide read a margin, a different one each.
        let readings = slideIn.compactMap { WindowHolePolicy.observedMenuMargin(in: [menu($0, owner: ghostty), bar],
                                                                                 displays: [builtIn]) }
        #expect(readings.count >= 2)
        #expect(Set(readings).count == readings.count)
        #expect(readings.contains { $0 > 100 })
        let starts: [MenuMarginMemory.Record?] = [nil, record(75)]
        for start in starts {
            var memory = SampledMenuMargin(stored: start, build: build)
            var writes: [MenuMarginMemory.Write] = []
            for _ in 0..<5 {
                for window in slideIn + slideIn.reversed() {
                    if let write = memory.note(proof([menu(window, owner: ghostty)], front: alertApp)) { writes.append(write) }
                }
            }
            #expect(writes.isEmpty)
            #expect(memory.margin == (start?.margin ?? 0))
        }
    }

    @Test("A reading counts once its window has held still for 0.2 s, not before")
    func stillnessThreshold() {
        #expect(MenuMarginMemory.stillTime == 0.2)
        let file = proof([menu(fileMenu)])
        // A slide whose app stalls for 11 samples (0.17 s) part way.
        var stalled = SampledMenuMargin(stored: nil, build: build)
        let stall = slideIn[10]
        #expect(hold(&stalled, proof([menu(stall, owner: ghostty)]), samples: 11).isEmpty)
        #expect(stalled.note(proof([menu(slideIn[11], owner: ghostty)])) == nil)
        #expect(stalled.margin == 0)
        // On the clock, sampled every 50 ms: 0.19 s after the first sample nothing counts; 0.2 s
        // after, it does.
        var timed = MenuMarginMemory(stored: nil, build: build)
        for time in [10, 10.05, 10.1, 10.15, 10.19] {
            #expect(timed.note(file, at: time) == nil, "\(time)")
        }
        #expect(timed.margin == 0)
        #expect(timed.note(file, at: 10.25) == saved(75))
        // A menu-bar menu interrupted by a sample without it starts again.
        var interrupted = MenuMarginMemory(stored: nil, build: build)
        #expect(interrupted.note(file, at: 20) == nil)
        #expect(interrupted.note(file, at: 20.05) == nil)
        #expect(interrupted.note(nil, at: 20.1) == nil)
        for time in [20.15, 20.2, 20.25, 20.3] {
            #expect(interrupted.note(file, at: time) == nil, "\(time)")
        }
        #expect(interrupted.note(file, at: 20.36) == saved(75))
        // Held on, it is not written again.
        #expect((1...600).compactMap { interrupted.note(file, at: 20.36 + Double($0) / 60) }.isEmpty)
    }

    @Test("A window dragged sideways above the top edge reads the same margin every sample, and counts for nothing")
    func sidewaysDragCountsForNothing() {
        var memory = SampledMenuMargin(stored: nil, build: build)
        var writes: [MenuMarginMemory.Write] = []
        for step in 0..<120 {
            let window = CGRect(x: 300 + CGFloat(step) * 3, y: -41, width: 400, height: 500)
            #expect(proof([menu(window, owner: alertApp)], front: alertApp) == .padded(75, window: window, ambiguous: false))
            if let write = memory.note(proof([menu(window, owner: alertApp)], front: alertApp)) { writes.append(write) }
        }
        #expect(writes.isEmpty)
        #expect(memory.margin == 0)
    }

    // MARK: Ambiguous readings: the part above the top edge lies on another display

    @Test("Displays whose tops differ by 1 pt or less leave a menu's reading unambiguous")
    func nearlyAlignedDisplays() {
        // A display to the right whose top is 1 pt lower: a menu against its left edge reaches 75 pt
        // back over the built-in display, and its part above the top edge overlaps it by 1 pt.
        let right = CGRect(x: 1512, y: 1, width: 1920, height: 1080)
        let rightBar = Window(bounds: CGRect(x: 1512, y: 1, width: 1920, height: 25), layer: 24, owner: 1,
                              isRegularApp: false)
        let window = CGRect(x: 1437, y: -48, width: 300, height: 400)
        let lower = WindowHolePolicy.menuMarginProof(in: [menu(window), rightBar, bar], displays: [builtIn, right])
        #expect(lower == .padded(75, window: window, ambiguous: false))
        // 2 pt lower, it overlaps by 2 pt: ambiguous.
        let twoLower = CGRect(x: 1512, y: 2, width: 1920, height: 1080)
        let twoLowerBar = Window(bounds: CGRect(x: 1512, y: 2, width: 1920, height: 25), layer: 24, owner: 1,
                                 isRegularApp: false)
        let lowerWindow = window.offsetBy(dx: 0, dy: 1)
        let ambiguous = WindowHolePolicy.menuMarginProof(in: [menu(lowerWindow), twoLowerBar, bar], displays: [builtIn, twoLower])
        #expect(ambiguous == .padded(75, window: lowerWindow, ambiguous: true))
        // A mirror of the display, at the same bounds, is not another display.
        #expect(proof([menu(fileMenu)]) == WindowHolePolicy.menuMarginProof(
            in: [menu(fileMenu), bar], displays: [builtIn, builtIn], titledRadius: 16, frontOwner: finder))
    }

    @Test("A window straddling a display stacked below reads 108, ambiguous: alone it is never used or stored")
    func stackedStraddleAlone() {
        #expect(proof([menu(straddleA, owner: alertApp)], stacked: true, front: alertApp)
            == .padded(108, window: straddleA, ambiguous: true))
        let starts: [MenuMarginMemory.Record?] = [nil, record(75)]
        for start in starts {
            var memory = SampledMenuMargin(stored: start, build: build)
            #expect(hold(&memory, proof([menu(straddleA, owner: alertApp)], stacked: true, front: alertApp), samples: 600).isEmpty)
            #expect(memory.margin == (start?.margin ?? 0))
        }
    }

    @Test("Known residual: two different windows straddling the stacked display and agreeing do count")
    func twoStraddlesAgree() {
        #expect(proof([menu(straddleB, owner: alertApp)], stacked: true, front: alertApp)
            == .padded(108, window: straddleB, ambiguous: true))
        var memory = SampledMenuMargin(stored: record(75), build: build)
        #expect(hold(&memory, proof([menu(straddleA, owner: alertApp)], stacked: true, front: alertApp)).isEmpty)
        #expect(hold(&memory, proof([menu(straddleB, owner: alertApp)], stacked: true, front: alertApp)) == savedOnly(108))
    }

    @Test("A menu-bar menu on the lower display of a stacked pair is ambiguous, so it takes two different menus")
    func menusOnTheLowerDisplay() {
        #expect(proof([menu(fileMenuBelow)], stacked: true) == .padded(75, window: fileMenuBelow, ambiguous: true))
        var memory = SampledMenuMargin(stored: nil, build: build)
        #expect(hold(&memory, proof([menu(fileMenuBelow)], stacked: true), samples: 120).isEmpty)
        #expect(memory.margin == 0)
        #expect(hold(&memory, proof([menu(editMenuBelow)], stacked: true)) == savedOnly(75))
        // The upper display's menus are not ambiguous: nothing lies above it.
        #expect(proof([menu(fileMenu)], stacked: true) == .padded(75, window: fileMenu, ambiguous: false))
        // A clean reading in the same sample wins over a larger ambiguous one.
        #expect(proof([menu(straddleA, owner: alertApp), menu(fileMenu)], stacked: true)
            == .padded(75, window: fileMenu, ambiguous: false))
    }

    @Test("Ambiguous readings agree to within 0.5 pt")
    func ambiguousAgreement() {
        let close = CGRect(x: 600, y: 932.5, width: 300, height: 400)
        let apart = CGRect(x: 600, y: 932, width: 300, height: 400)
        #expect(proof([menu(close)], stacked: true) == .padded(75.5, window: close, ambiguous: true))
        #expect(proof([menu(apart)], stacked: true) == .padded(76, window: apart, ambiguous: true))
        var agreeing = SampledMenuMargin(stored: nil, build: build)
        #expect(hold(&agreeing, proof([menu(fileMenuBelow)], stacked: true)).isEmpty)
        #expect(hold(&agreeing, proof([menu(close)], stacked: true)) == savedOnly(75.5))
        var disagreeing = SampledMenuMargin(stored: nil, build: build)
        #expect(hold(&disagreeing, proof([menu(fileMenuBelow)], stacked: true)).isEmpty)
        #expect(hold(&disagreeing, proof([menu(apart)], stacked: true)).isEmpty)
        #expect(disagreeing.margin == 0)
    }

    @Test("One ambiguous window never agrees with itself, moved or resized, each shape held still")
    func ambiguousWindowNeverAgreesWithItself() {
        // Reads 75 against the lower display; resized from an edge or a bottom corner it keeps its top,
        // so its reading, and one of its sides; moved sideways it keeps its size.
        let base = CGRect(x: 300, y: 933, width: 400, height: 500)
        #expect(proof([menu(base, owner: alertApp)], stacked: true, front: alertApp)
            == .padded(75, window: base, ambiguous: true))
        let shapes: [(String, (CGFloat) -> CGRect)] = [
            ("moved", { base.offsetBy(dx: $0, dy: 0) }),
            ("bottom edge", { CGRect(x: base.minX, y: base.minY, width: base.width, height: base.height + $0) }),
            ("right edge", { CGRect(x: base.minX, y: base.minY, width: base.width + $0, height: base.height) }),
            ("left edge", { CGRect(x: base.minX - $0, y: base.minY, width: base.width + $0, height: base.height) }),
            ("bottom-right corner", { CGRect(x: base.minX, y: base.minY, width: base.width + $0, height: base.height + $0) }),
            ("bottom-left corner", { CGRect(x: base.minX - $0, y: base.minY, width: base.width + $0, height: base.height + $0) }),
        ]
        for (name, shape) in shapes {
            var memory = SampledMenuMargin(stored: nil, build: build)
            for step in 0..<20 {
                let window = shape(CGFloat(step) * 7)
                #expect(hold(&memory, proof([menu(window, owner: alertApp)], stacked: true, front: alertApp)).isEmpty,
                        "\(name) \(step)")
            }
            #expect(memory.margin == 0, "\(name)")
        }
    }
}
