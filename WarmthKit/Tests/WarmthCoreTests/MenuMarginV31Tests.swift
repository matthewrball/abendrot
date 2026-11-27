import Testing
import Foundation
import CoreGraphics
@testable import WarmthCore

// How #37's menu margin is kept once one is known. When one still clean reading above the margin
// could raise it, it was raised for good, since macOS 27 never proves there is no margin:
// - With 75 stored, a tall pop-up whose body is pinned to the top of the screen (body top y 4 or 0)
// and held 0.5 s stored 105 or 109. On macOS 26.7.3 no real AppKit menu started above the menu
// line while the bar was listed; macOS 27 is unverified.
// - Ghostty's quick terminal stalled 0.2 s mid-slide, top at y -60, stored 94.
// So a larger reading raises a known margin only when another window agrees. The reporter's steps
// are in MenuMarginV3Tests. Stillness is timed on an injected clock, not counted in samples, and a
// gap in sampling restarts it; a proof of no margin forgets the session's readings.
// Display, menu bar and menus are the reporter's (macOS 27.2.1, 1512 x 982 pt, 33 pt menu bar).

private typealias Window = WindowHolePolicy.Window

private let builtIn = CGRect(x: 0, y: 0, width: 1512, height: 982)
private let bar = Window(bounds: CGRect(x: 0, y: 0, width: 1512, height: 33), layer: 24, owner: 1, isRegularApp: false)
private let finder: Int32 = 9
private let ghostty: Int32 = 44
private let alertApp: Int32 = 31
private let build = "26B131"

private let fileMenu = CGRect(x: -35, y: -41, width: 410, height: 570)
private let editMenu = CGRect(x: 15, y: -41, width: 390, height: 530)
private let rowA = CGRect(x: 1000, y: -25, width: 366, height: 455)

/// A 200 x 900 pt pop-up menu in its 75 pt padded window, its body pinned at y `bodyTop`.
private func pinnedPopUp(bodyTop: CGFloat) -> CGRect {
    CGRect(x: 600 - 75, y: bodyTop - 75, width: 200 + 150, height: 900 + 150)
}
/// Another, shorter pop-up pinned at the same height.
private let otherPinnedPopUp = CGRect(x: 900, y: 4 - 75, width: 300, height: 900)
/// Ghostty's quick terminal (1200 x 400 pt) stalled mid-slide, its top at y -60.
private let stalledTerminal = CGRect(x: 156, y: -60, width: 1200, height: 400)

/// A display stacked below the built-in one, with a 25 pt menu bar.
private let below = CGRect(x: 0, y: 982, width: 1920, height: 1080)
private let belowBar = Window(bounds: CGRect(x: 0, y: 982, width: 1920, height: 25), layer: 24, owner: 1,
                              isRegularApp: false)
/// An alert dragged across onto it: ambiguous, 108.
private let straddle = CGRect(x: 400, y: 900, width: 667, height: 461)
/// A window parked above the built-in display's top edge that reads the same 108, clean.
private let parked108 = CGRect(x: 600, y: -74, width: 400, height: 600)

private func menu(_ bounds: CGRect, owner: Int32 = finder) -> Window {
    Window(bounds: bounds, layer: WindowHolePolicy.popUpMenuLayer, owner: owner)
}

private func proof(_ windows: [Window], stacked: Bool = false, front: Int32? = finder) -> WindowHolePolicy.MenuMarginProof? {
    WindowHolePolicy.menuMarginProof(
        in: windows + (stacked ? [belowBar, bar] : [bar]), displays: stacked ? [builtIn, below] : [builtIn],
        titledRadius: 16, frontOwner: front)
}

/// Notes `proof` for `samples` 60 Hz samples in a row (0.5 s by default), and returns the writes.
private func hold(
    _ memory: inout SampledMenuMargin,
    _ proof: WindowHolePolicy.MenuMarginProof?,
    samples: Int = SampledMenuMargin.heldSamples
) -> [MenuMarginMemory.Write] {
    (0..<samples).compactMap { _ in memory.note(proof) }
}

private func savedOnly(_ margin: CGFloat) -> [MenuMarginMemory.Write] {
    [.save(MenuMarginMemory.Record(build: build, margin: margin))]
}

private func record(_ margin: CGFloat) -> MenuMarginMemory.Record {
    MenuMarginMemory.Record(build: build, margin: margin)
}

@Suite("Menu margin: agreement once a margin is known, and stillness on a clock (#37)")
struct MenuMarginV31Tests {

    // MARK: A larger reading needs a second window once a margin is known

    @Test("A pop-up pinned to the top (body top 4 or 0), held 0.5 s, does not raise a stored 75")
    func pinnedPopUpDoesNotRaise() {
        let cases: [(bodyTop: CGFloat, reads: CGFloat)] = [(4, 105), (0, 109)]
        for (bodyTop, reads) in cases {
            let popup = pinnedPopUp(bodyTop: bodyTop)
            let expected = WindowHolePolicy.MenuMarginProof.padded(reads, window: popup, ambiguous: false)
            #expect(proof([menu(popup)]) == expected)
            var memory = SampledMenuMargin(stored: record(75), build: build)
            #expect(hold(&memory, proof([menu(popup)])).isEmpty, "body top \(bodyTop)")
            #expect(hold(&memory, proof([menu(fileMenu)])).isEmpty)
            #expect(hold(&memory, proof([menu(editMenu)])).isEmpty)
            #expect(memory.margin == 75)
            #expect(MenuMarginMemory(stored: memory.stored, build: build).margin == 75)
        }
    }

    @Test("Ghostty's quick terminal stalled mid-slide does not raise a stored 75, nor does the same stall twice")
    func stalledTerminalDoesNotRaise() {
        #expect(proof([menu(stalledTerminal, owner: ghostty)], front: alertApp)
            == .padded(94, window: stalledTerminal, ambiguous: false))
        var memory = SampledMenuMargin(stored: record(75), build: build)
        // 12 samples, then a whole second; then the next slide stalls at the same place:
        // one window, however often.
        #expect(hold(&memory, proof([menu(stalledTerminal, owner: ghostty)], front: alertApp), samples: 12).isEmpty)
        #expect(hold(&memory, proof([menu(stalledTerminal, owner: ghostty)], front: alertApp), samples: 60).isEmpty)
        #expect(memory.note(nil) == nil)
        #expect(hold(&memory, proof([menu(stalledTerminal, owner: ghostty)], front: alertApp)).isEmpty)
        #expect(memory.margin == 75)
    }

    @Test("Known residual: two windows of different shapes agreeing above the margin raise it (no real menu did on 26.7.3)")
    func twoPinnedPopUpsAgree() {
        #expect(proof([menu(otherPinnedPopUp)]) == .padded(105, window: otherPinnedPopUp, ambiguous: false))
        var memory = SampledMenuMargin(stored: record(75), build: build)
        #expect(hold(&memory, proof([menu(pinnedPopUp(bodyTop: 4))])).isEmpty)
        #expect(hold(&memory, proof([menu(otherPinnedPopUp)])) == savedOnly(105))
    }

    @Test("A larger reading agrees within 0.5 pt, clean or ambiguous, in either order")
    func cleanAndAmbiguousAgree() {
        #expect(proof([menu(parked108, owner: alertApp)], stacked: true, front: alertApp)
            == .padded(108, window: parked108, ambiguous: false))
        #expect(proof([menu(straddle, owner: alertApp)], stacked: true, front: alertApp)
            == .padded(108, window: straddle, ambiguous: true))
        let orders: [[CGRect]] = [[parked108, straddle], [straddle, parked108]]
        for order in orders {
            var memory = SampledMenuMargin(stored: record(75), build: build)
            #expect(hold(&memory, proof([menu(order[0], owner: alertApp)], stacked: true, front: alertApp)).isEmpty)
            #expect(hold(&memory, proof([menu(order[1], owner: alertApp)], stacked: true, front: alertApp))
                == savedOnly(108))
        }
    }

    // MARK: From no margin

    @Test("Known residual: the first still reading on a new build is believed alone, even an outlier")
    func firstReadingIsBelieved() {
        // The stalled terminal with nothing stored: 94 is stored, and no menu lowers it. `abendrot debug fullscreen`
        // then prints "Menu margin remembered: 94 pt, proven on 26B131 (this Mac), used when Keep other
        // windows warm is on" (MenuMarginLineTests), and
        // `defaults delete app.abendrot.Abendrot windowFilterMenuMargin` removes it.
        var memory = SampledMenuMargin(stored: nil, build: build)
        #expect(hold(&memory, proof([menu(stalledTerminal, owner: ghostty)], front: alertApp)) == savedOnly(94))
        #expect(hold(&memory, proof([menu(fileMenu)])).isEmpty)
        #expect(hold(&memory, proof([menu(editMenu)])).isEmpty)
        #expect(memory.margin == 94)
        #expect(MenuMarginMemory(stored: memory.stored, build: build).margin == 94)
    }

    @Test("The cost: after 59 on a new build, one menu-bar menu raises nothing; a second of another size in the same session does")
    func healTakesTwoMenusInOneSession() {
        var session = SampledMenuMargin(stored: nil, build: build)
        #expect(hold(&session, proof([menu(rowA)])) == savedOnly(59))
        #expect(hold(&session, proof([menu(fileMenu)])).isEmpty)
        #expect(session.margin == 59)
        // Relaunched in between, the File menu is forgotten: the Edit menu alone raises nothing.
        var relaunched = SampledMenuMargin(stored: session.stored, build: build)
        #expect(relaunched.margin == 59)
        #expect(hold(&relaunched, proof([menu(editMenu)])).isEmpty)
        #expect(relaunched.margin == 59)
        // In the same session it does.
        #expect(hold(&session, proof([menu(editMenu)])) == savedOnly(75))
        #expect(session.margin == 75)
    }

    @Test("On a laptop below an external display, keeping the margin takes two menus of different sizes")
    func laptopBelowAnExternalDisplay() {
        let external = CGRect(x: -200, y: -1080, width: 1920, height: 1080)
        let externalBar = Window(bounds: CGRect(x: -200, y: -1080, width: 1920, height: 25), layer: 24, owner: 1,
                                 isRegularApp: false)
        func laptop(_ window: CGRect) -> WindowHolePolicy.MenuMarginProof? {
            WindowHolePolicy.menuMarginProof(in: [menu(window), bar, externalBar], displays: [builtIn, external],
                                             titledRadius: 16, frontOwner: finder)
        }
        #expect(laptop(fileMenu) == .padded(75, window: fileMenu, ambiguous: true))
        var memory = SampledMenuMargin(stored: nil, build: build)
        #expect(hold(&memory, laptop(fileMenu)).isEmpty)
        #expect(memory.margin == 0)
        #expect(hold(&memory, laptop(editMenu)) == savedOnly(75))
    }

    // MARK: Stillness is timed, not counted

    @Test("A burst of extra samples within 0.2 s does not make a window still; 0.2 s does")
    func burstIsNotStillness() {
        let file = proof([menu(fileMenu)])
        var memory = MenuMarginMemory(stored: nil, build: build)
        // The timer's sample, then 40 more within 0.1 s from apply, rebuildPanels and Space changes.
        #expect(memory.note(file, at: 100) == nil)
        for extra in 1...40 {
            #expect(memory.note(file, at: 100 + Double(extra) * 0.0025) == nil, "extra sample \(extra)")
        }
        #expect(memory.note(file, at: 100.15) == nil)
        #expect(memory.margin == 0)
        #expect(memory.note(file, at: 100.2) == .save(record(75)))
    }

    @Test("Two samples 0.3 s apart with nothing between are a gap, not stillness; sampled on, it counts 0.2 s later")
    func timeNotSamples() {
        let file = proof([menu(fileMenu)])
        var memory = MenuMarginMemory(stored: nil, build: build)
        #expect(memory.note(file, at: 7) == nil)
        #expect(memory.note(file, at: 7.3) == nil)
        let writes = (1...15).compactMap { memory.note(file, at: 7.3 + Double($0) / 60) }
        #expect(writes == savedOnly(75))
    }

    @Test("A stall frame seen once, then the same bounds 30 s later, counts for nothing")
    func gapRestartsStillness() {
        let stall = proof([menu(stalledTerminal, owner: ghostty)], front: alertApp)
        var memory = MenuMarginMemory(stored: nil, build: build)
        #expect(memory.note(stall, at: 6000) == nil)
        #expect(memory.note(stall, at: 6030) == nil)
        #expect(memory.margin == 0)
        // Gaps of 0.140625 s are watched; one of 0.15625 s starts the count again (exact in binary,
        // on either side of the 0.15 s bound).
        var bounded = MenuMarginMemory(stored: nil, build: build)
        let file = proof([menu(fileMenu)])
        #expect(MenuMarginMemory.sampleGap == 0.15)
        #expect(bounded.note(file, at: 100) == nil)
        #expect(bounded.note(file, at: 100.140625) == nil)
        #expect(bounded.note(file, at: 100.28125) == .save(record(75)))
        var restarted = MenuMarginMemory(stored: nil, build: build)
        #expect(restarted.note(file, at: 200) == nil)
        #expect(restarted.note(file, at: 200.15625) == nil)
        #expect(restarted.note(file, at: 200.296875) == nil)
        #expect(restarted.note(file, at: 200.359375) == .save(record(75)))
    }

    @Test("Late ticks still count within 0.3 s: 16-60 ms apart, and the measured 84 ms with gaps of 100-146 ms")
    func jitteryTicksCount() {
        let file = proof([menu(fileMenu)])
        // Gaps between ticks, in seconds: an uneven 60 Hz, then the cadence measured on a loaded
        // Mac with a window list taken each tick (77-88 ms at most in most runs, 100-146 ms in one).
        let cadences: [[TimeInterval]] = [
            [0.016, 0.060, 0.017, 0.045, 0.060, 0.016, 0.030, 0.006],
            [0.084, 0.084, 0.084],
            [0.084, 0.120, 0.084],
            [0.084, 0.100, 0.084],
            [0.146, 0.084],
        ]
        for gaps in cadences {
            var memory = MenuMarginMemory(stored: nil, build: build)
            let start: TimeInterval = 300
            var time = start
            var writes: [MenuMarginMemory.Write] = []
            var countedAfter: TimeInterval?
            if let write = memory.note(file, at: time) { writes.append(write) }
            for gap in gaps {
                time += gap
                if let write = memory.note(file, at: time) {
                    writes.append(write)
                    countedAfter = time - start
                }
            }
            #expect(writes == savedOnly(75), "\(gaps)")
            #expect((countedAfter ?? 1) < 0.3, "\(gaps)")
        }
    }

    @Test("A zero proof forgets the session's readings, so none from before it agrees with one after")
    func zeroProofForgetsReadings() {
        let external = CGRect(x: -200, y: -1080, width: 1920, height: 1080)
        let externalBar = Window(bounds: CGRect(x: -200, y: -1080, width: 1920, height: 25), layer: 24, owner: 1,
                                 isRegularApp: false)
        func laptop(_ windows: [Window]) -> WindowHolePolicy.MenuMarginProof? {
            WindowHolePolicy.menuMarginProof(in: windows + [bar, externalBar], displays: [builtIn, external],
                                             titledRadius: 16, frontOwner: finder)
        }
        let unpadded = Window(bounds: CGRect(x: 6, y: 34, width: 263, height: 305), layer: 101, owner: finder,
                              cornerRadius: 12)
        var memory = SampledMenuMargin(stored: record(75), build: build)
        #expect(hold(&memory, laptop([menu(fileMenu)])).isEmpty)
        #expect(memory.note(laptop([unpadded])) == .clear)
        #expect(hold(&memory, laptop([menu(editMenu)])).isEmpty)
        #expect(memory.margin == 0)
        // Two menus after the zero proof still agree.
        #expect(hold(&memory, laptop([menu(fileMenu)])) == savedOnly(75))
    }

    @Test("A reading that changes starts the clock again")
    func changedReadingRestarts() {
        // Sampled every 50 ms: the File menu for 0.15 s, then the Edit menu.
        var memory = MenuMarginMemory(stored: nil, build: build)
        for time in [0, 0.05, 0.1, 0.15] {
            #expect(memory.note(proof([menu(fileMenu)]), at: time) == nil, "\(time)")
        }
        for time in [0.2, 0.25, 0.3, 0.35] {
            #expect(memory.note(proof([menu(editMenu)]), at: time) == nil, "\(time)")
        }
        #expect(memory.note(proof([menu(editMenu)]), at: 0.42) == .save(record(75)))
    }
}
