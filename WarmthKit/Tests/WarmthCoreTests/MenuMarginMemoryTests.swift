import Testing
import Foundation
import CoreGraphics
@testable import WarmthCore

/// #37: on a Mac whose menu windows carry a transparent margin (macOS 27.2.1 here), menus over an
/// excluded app had a box around them after every launch until a menu-bar menu was opened, because
/// the margin lived only in memory. Fixtures are the reporter's numbers: the 1512 x 982 pt display,
/// the 33 pt menu bar and Finder's menu-bar menu from the 1.1.18 debug output, and the boxes
/// measured in the screenshots of the 2026-11-24 comment on #30.
@Suite("Menu margin memory (#37)")
struct MenuMarginMemoryTests {
    private let display = CGRect(x: 0, y: 0, width: 1512, height: 982)
    /// `Window Server layer 24 x 0 y 0 1512x33`.
    private let menuBar = WindowHolePolicy.Window(
        bounds: CGRect(x: 0, y: 0, width: 1512, height: 33), layer: 24, owner: 1, isRegularApp: false)
    private let finder: Int32 = 9
    private let terminal: Int32 = 7
    private let lulu: Int32 = 5
    /// The reporter's build, and another one.
    private let build = "26B131"
    private let otherBuild = "26B120"

    /// `Finder (com.apple.finder) [app] layer 101 alpha 1.00 x -70 y -41 379x455 radius 0`. WindowServer
    /// reports radius 0, which the backend drops, so the window has no known radius.
    private let finderMenuWindow = CGRect(x: -70, y: -41, width: 379, height: 455)
    private var finderMenu: WindowHolePolicy.Window { .init(bounds: finderMenuWindow, layer: 101, owner: finder) }
    /// Finder's Edit menu, under another title: a window of another size. Two menus that read the same
    /// margin confirm it (`MenuMarginMemory`).
    private let editMenuWindow = CGRect(x: 15, y: -41, width: 390, height: 530)
    private var editMenu: WindowHolePolicy.Window { .init(bounds: editMenuWindow, layer: 101, owner: finder) }

    /// The desktop context menu after launch (screenshot db35894d): a neutral box 366 x 455 pt around a
    /// 216 x 305 pt menu, 74.5 to 75 pt on every side.
    private let contextMenuWindow = CGRect(x: 520, y: 300, width: 366, height: 455)
    private var contextMenu: WindowHolePolicy.Window { .init(bounds: contextMenuWindow, layer: 101, owner: finder) }
    private var desktop: WindowHolePolicy.Window {
        .init(bounds: display, layer: Int(CGWindowLevelForKey(.desktopIconWindow)), owner: finder)
    }

    /// LuLu's menu from its status item (screenshots fd63c9e3 and 1c78da1a): a 136 x 153 pt menu in a
    /// box 75 pt wider on every side, hanging from the menu bar.
    private let luluMenuWindow = CGRect(x: 300, y: -41, width: 286, height: 303)
    private var luluMenu: WindowHolePolicy.Window {
        .init(bounds: luluMenuWindow, layer: 101, owner: lulu, isRegularApp: false)
    }
    /// An excluded Finder window behind LuLu's menu.
    private let finderWindow = CGRect(x: 60, y: 40, width: 1100, height: 800)

    /// macOS 26.6: the menu-bar menu is the window itself, and WindowServer reports its 12 pt corner.
    private let unpaddedMenuWindow = CGRect(x: 6, y: 34, width: 263, height: 305)
    private func unpaddedMenu(radius: CGFloat? = 12, owner: Int32 = 7, regular: Bool = true) -> WindowHolePolicy.Window {
        .init(bounds: unpaddedMenuWindow, layer: 101, owner: owner, isRegularApp: regular, cornerRadius: radius)
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

    /// The proof the backend takes from a sample: the titled corner is 16 pt, and `front` is the
    /// frontmost app (none by default, so nothing proves the absence of a margin).
    private func proof(_ windows: [WindowHolePolicy.Window], displays: [CGRect]? = nil,
                       front: Int32? = nil) -> WindowHolePolicy.MenuMarginProof? {
        WindowHolePolicy.menuMarginProof(in: windows, displays: displays ?? [display], titledRadius: 16, frontOwner: front)
    }

    private func makeRecord(_ build: String, _ margin: CGFloat) -> MenuMarginMemory.Record? {
        MenuMarginMemory.Record(build: build, margin: margin)
    }

    private func saved(_ build: String, _ margin: CGFloat) -> MenuMarginMemory.Write? {
        .save(MenuMarginMemory.Record(build: build, margin: margin))
    }

    /// Notes `proof` for as many samples in a row as a still window takes to count (a menu held
    /// open), and returns the one write, or nil. More than one write is a failure.
    private func hold(_ memory: inout SampledMenuMargin, _ proof: WindowHolePolicy.MenuMarginProof?) -> MenuMarginMemory.Write? {
        let writes = (0..<SampledMenuMargin.heldSamples).compactMap { _ in memory.note(proof) }
        #expect(writes.count <= 1, "\(writes)")
        return writes.first
    }

    // MARK: Launch

    @Test("A margin stored on this build cuts the first context menu after launch at the menu")
    func storedMarginOnSameBuild() {
        var memory = SampledMenuMargin(stored: .init(build: build, margin: 75), build: build)
        #expect(memory.margin == 75)

        // Right-click on the desktop with Finder excluded, before any menu-bar menu.
        let windows = [contextMenu, menuBar, desktop]
        #expect(proof(windows) == nil)
        #expect(hold(&memory, proof(windows)) == nil)
        #expect(memory.margin == 75)
        let region = WindowHolePolicy.neutralRegion(
            windows: windows, owner: finder, display: display, cornerRadius: 16, menuMargin: memory.margin)
        let body = contextMenuWindow.insetBy(dx: 75, dy: 75)
        #expect(body.size == CGSize(width: 216, height: 305))
        #expect(sameRegion(region, WindowHolePolicy.roundedInterior(body, radius: WindowHolePolicy.paddedMenuCornerRadius)))
        // The 75 pt margin, where the box was, stays warm.
        for point in [CGPoint(x: contextMenuWindow.minX + 10, y: body.midY), CGPoint(x: body.midX, y: contextMenuWindow.minY + 10),
                      CGPoint(x: contextMenuWindow.maxX - 10, y: body.midY), CGPoint(x: body.midX, y: contextMenuWindow.maxY - 10)] {
            #expect(!isNeutral(region, point), "margin point \(point)")
        }
    }

    @Test("A margin stored on this build keeps a menu-bar app's menu warm at the menu, and neutral at the menu when it is excluded")
    func storedMarginForMenuBarAppMenus() {
        let memory = MenuMarginMemory(stored: .init(build: build, margin: 75), build: build)
        let body = luluMenuWindow.insetBy(dx: 75, dy: 75)
        #expect(body.size == CGSize(width: 136, height: 153))

        // fd63c9e3: LuLu's menu over an excluded Finder window was a warm box 286 pt wide.
        let warm = WindowHolePolicy.neutralRegion(
            windows: [luluMenu, menuBar, .init(bounds: finderWindow, layer: 0, owner: finder)],
            owner: finder, display: display, cornerRadius: 16, menuMargin: memory.margin)
        #expect(!isNeutral(warm, CGPoint(x: body.midX, y: body.midY)))
        #expect(!isNeutral(warm, CGPoint(x: body.minX + 1, y: body.midY)))
        #expect(isNeutral(warm, CGPoint(x: body.minX - 30, y: body.midY)))
        #expect(isNeutral(warm, CGPoint(x: body.midX, y: body.maxY + 30)))
        #expect(isNeutral(warm, CGPoint(x: body.maxX + 30, y: body.midY)))

        // 1c78da1a: LuLu excluded too, Finder in front. Its menu is neutral at the menu, not its window.
        let neutral = WindowHolePolicy.neutralRegion(
            windows: [luluMenu, menuBar, desktop], owner: finder, display: display, cornerRadius: 16,
            floatingOwners: [lulu], menuMargin: memory.margin)
        #expect(sameRegion(neutral, WindowHolePolicy.roundedInterior(body, radius: WindowHolePolicy.paddedMenuCornerRadius)))
    }

    @Test("A stored margin also cuts menus while no menu bar is listed")
    func storedMarginWithoutMenuBar() {
        // An auto-hidden menu bar: nothing to prove a margin against, but a remembered one still applies.
        let memory = MenuMarginMemory(stored: .init(build: build, margin: 75), build: build)
        let windows = [contextMenu, desktop]
        #expect(proof(windows) == nil)
        let region = WindowHolePolicy.neutralRegion(
            windows: windows, owner: finder, display: display, cornerRadius: 16, menuMargin: memory.margin)
        #expect(sameRegion(region, WindowHolePolicy.roundedInterior(
            contextMenuWindow.insetBy(dx: 75, dy: 75), radius: WindowHolePolicy.paddedMenuCornerRadius)))
    }

    @Test("A margin stored on another build, or with no build known, is ignored: menus count at their bounds, as in 1.1.19")
    func storedMarginOnOtherBuild() {
        let windows = [contextMenu, menuBar, desktop]
        let old = WindowHolePolicy.neutralRegion(windows: windows, owner: finder, display: display, cornerRadius: 16)
        // The 1.1.19 box: the whole 366 x 455 pt window, at the titled-window corner.
        #expect(sameRegion(old, WindowHolePolicy.roundedInterior(contextMenuWindow, radius: 16)))
        for memory in [MenuMarginMemory(stored: .init(build: otherBuild, margin: 75), build: build),
                       MenuMarginMemory(stored: .init(build: build, margin: 75), build: nil),
                       MenuMarginMemory(stored: nil, build: build)] {
            #expect(memory.margin == 0)
            #expect(WindowHolePolicy.neutralRegion(
                windows: windows, owner: finder, display: display, cornerRadius: 16, menuMargin: memory.margin) == old)
        }

        // The first Finder menu-bar menu, once held open, proves the margin on this build and replaces
        // the old record.
        var memory = SampledMenuMargin(stored: .init(build: otherBuild, margin: 75), build: build)
        #expect(proof([finderMenu, menuBar, desktop]) == .padded(75, window: finderMenuWindow, ambiguous: false))
        #expect(hold(&memory, proof([finderMenu, menuBar, desktop])) == saved(build, 75))
        #expect(memory.margin == 75)
        #expect(hold(&memory, proof([editMenu, menuBar, desktop])) == nil)
        let proven: MenuMarginMemory.Record? = MenuMarginMemory.Record(build: build, margin: 75)
        #expect(memory.stored == proven)
    }

    // MARK: Proof of no margin

    @Test("A menu-bar menu without a margin clears a stored margin")
    func unpaddedMenuClearsStoredMargin() {
        let sample = [unpaddedMenu(), menuBar]
        #expect(proof(sample, front: terminal) == .unpadded)

        // A wrong record for this very build (macOS 26.6 here).
        var memory = SampledMenuMargin(stored: .init(build: "25G72", margin: 75), build: "25G72")
        #expect(memory.margin == 75)
        #expect(memory.note(proof(sample, front: terminal)) == .clear)
        #expect(memory.margin == 0)
        #expect(memory.stored == nil)
        // Cleared once, not on every sample.
        #expect(hold(&memory, proof(sample, front: terminal)) == nil)
        #expect(WindowHolePolicy.neutralRegion(
            windows: sample, owner: terminal, display: display, cornerRadius: 16, menuMargin: memory.margin)
            == WindowHolePolicy.neutralRegion(windows: sample, owner: terminal, display: display, cornerRadius: 16))

        // A margin proven earlier in this session drops too.
        var session = SampledMenuMargin(stored: nil, build: build)
        #expect(hold(&session, .padded(75, window: finderMenuWindow, ambiguous: false)) == saved(build, 75))
        #expect(session.note(proof(sample, front: terminal)) == .clear)
        #expect(session.margin == 0)

        // A record from another build is cleared as well; nothing stored means nothing to write.
        var stale = SampledMenuMargin(stored: .init(build: otherBuild, margin: 75), build: build)
        #expect(stale.note(.unpadded) == .clear)
        var empty = SampledMenuMargin(stored: nil, build: build)
        #expect(empty.note(.unpadded) == nil)
        #expect(empty.margin == 0)
    }

    @Test("Windows that merely sit under the menu bar prove no absence of a margin")
    func falseUnpaddedProofs() {
        let atLine = CGRect(x: 400, y: 34, width: 366, height: 455)
        // Each case with the app of its window in front, so it fails for its own reason.
        let cases: [(String, [WindowHolePolicy.Window])] = [
            // macOS 27: a padded context menu or submenu whose window top lands on the menu line. Its
            // window reports radius 0 (dropped to nil by the backend), never the menu's corner.
            ("padded window, no radius", [.init(bounds: atLine, layer: 101, owner: finder), menuBar]),
            ("padded window, radius 0", [.init(bounds: atLine, layer: 101, owner: finder, cornerRadius: 0), menuBar]),
            ("unpadded menu, no radius", [unpaddedMenu(radius: nil), menuBar]),
            ("accessory app", [unpaddedMenu(owner: lulu, regular: false), menuBar]),
            ("status-level window", [.init(bounds: unpaddedMenuWindow, layer: WindowHolePolicy.statusLayer, owner: terminal,
                                           cornerRadius: 12), menuBar]),
            ("this app's measured window", [.init(bounds: unpaddedMenuWindow, layer: 101, owner: 2, isMeasured: true,
                                                  cornerRadius: 12), menuBar]),
            ("invisible", [.init(bounds: unpaddedMenuWindow, layer: 101, owner: terminal, alpha: 0, cornerRadius: 12), menuBar]),
            ("below the line", [.init(bounds: unpaddedMenuWindow.offsetBy(dx: 0, dy: 2.5), layer: 101, owner: terminal,
                                      cornerRadius: 12), menuBar]),
            ("past the display's edge", [.init(bounds: CGRect(x: 1400, y: 34, width: 263, height: 305), layer: 101,
                                               owner: terminal, cornerRadius: 12), menuBar]),
            ("too small for a menu", [.init(bounds: CGRect(x: 6, y: 34, width: 12, height: 12), layer: 101, owner: terminal,
                                            cornerRadius: 4), menuBar]),
            ("no menu bar listed", [unpaddedMenu()]),
            ("a context menu", [.init(bounds: CGRect(x: 600, y: 477, width: 118, height: 106), layer: 101, owner: terminal,
                                      cornerRadius: 12), menuBar]),
        ]
        for (name, windows) in cases {
            #expect(proof(windows, front: windows.first?.owner) == nil, "\(name)")
        }

        // Within the slack of the menu line, and against a second display's own menu bar.
        #expect(proof([.init(bounds: unpaddedMenuWindow.offsetBy(dx: 0, dy: 2), layer: 101, owner: terminal,
                             cornerRadius: 12), menuBar], front: terminal) == .unpadded)
        let second = CGRect(x: 1512, y: -200, width: 1920, height: 1080)
        let secondBar = WindowHolePolicy.Window(bounds: CGRect(x: 1512, y: -200, width: 1920, height: 25), layer: 24,
                                                owner: 1, isRegularApp: false)
        let there = WindowHolePolicy.Window(bounds: CGRect(x: 1600, y: -174, width: 263, height: 305), layer: 101,
                                            owner: terminal, cornerRadius: 12)
        #expect(proof([there, secondBar, menuBar], displays: [display, second], front: terminal) == .unpadded)
        #expect(proof([there, menuBar], displays: [display, second], front: terminal) == nil)

        // A padded submenu that lands on the menu line, even one reporting a radius, opens beside
        // its parent, which hangs from the bar: the margin wins. Alone, such a window of the front
        // app with a menu's corner would prove no margin.
        let submenu = WindowHolePolicy.Window(bounds: atLine, layer: 101, owner: finder, cornerRadius: 12)
        #expect(proof([submenu, menuBar, desktop], front: finder) == .unpadded)
        #expect(proof([submenu, finderMenu, menuBar, desktop], front: finder)
            == .padded(75, window: finderMenuWindow, ambiguous: false))
    }

    // MARK: Which margin is kept

    @Test("The largest margin read is kept: submenus, a second display and a context menu near the top read less")
    func largestMarginIsKept() {
        // A submenu of Finder's menu, opened from its second item, reaches above the display by less.
        let submenu = WindowHolePolicy.Window(bounds: CGRect(x: 159, y: -21, width: 370, height: 350), layer: 101, owner: finder)
        #expect(WindowHolePolicy.observedMenuMargin(in: [submenu, menuBar], displays: [display]) == 55)
        #expect(WindowHolePolicy.observedMenuMargin(in: [submenu, finderMenu, menuBar], displays: [display]) == 75)

        // A second display above and to the right, with a 24 pt menu bar: its menu is measured
        // against its own bar, and the built-in display does not read it.
        let second = CGRect(x: 1512, y: -200, width: 1920, height: 1080)
        let secondBar = WindowHolePolicy.Window(bounds: CGRect(x: 1512, y: -200, width: 1920, height: 24), layer: 24,
                                                owner: 1, isRegularApp: false)
        let secondMenu = WindowHolePolicy.Window(bounds: CGRect(x: 1700, y: -250, width: 400, height: 500), layer: 101,
                                                 owner: terminal)
        #expect(WindowHolePolicy.observedMenuMargin(in: [secondMenu, secondBar, menuBar], displays: [display, second]) == 75)
        #expect(WindowHolePolicy.observedMenuMargin(in: [secondMenu, menuBar], displays: [display, second]) == nil)
        #expect(WindowHolePolicy.observedMenuMargin(
            in: [secondMenu, secondBar, finderMenu, submenu, menuBar], displays: [display, second]) == 75)

        // A desktop context menu opened 50 pt from the top: its padded window starts 25 pt above the
        // display and reads 59 pt. 1.1.19 used that reading until the next menu-bar menu.
        let nearTop = WindowHolePolicy.Window(bounds: CGRect(x: 1000, y: -25, width: 366, height: 455), layer: 101, owner: finder)
        #expect(proof([nearTop, menuBar, desktop]) == .padded(59, window: nearTop.bounds, ambiguous: false))
        var memory = SampledMenuMargin(stored: nil, build: build)
        #expect(hold(&memory, proof([finderMenu, menuBar, desktop])) == saved(build, 75))
        #expect(hold(&memory, proof([nearTop, menuBar, desktop])) == nil)
        #expect(memory.margin == 75)
        let region = WindowHolePolicy.neutralRegion(
            windows: [nearTop, menuBar, desktop], owner: finder, display: display, cornerRadius: 16, menuMargin: memory.margin)
        #expect(sameRegion(region, WindowHolePolicy.roundedInterior(
            nearTop.bounds.insetBy(dx: 75, dy: 75), radius: WindowHolePolicy.paddedMenuCornerRadius)))

        // Before any menu-bar menu, that reading is the best known and is stored. Once a margin is
        // known, a larger reading needs a second window to agree: two menu-bar menus raise it.
        var fresh = SampledMenuMargin(stored: nil, build: build)
        #expect(hold(&fresh, proof([nearTop, menuBar, desktop])) == saved(build, 59))
        #expect(fresh.margin == 59)
        #expect(hold(&fresh, proof([finderMenu, menuBar, desktop])) == nil)
        #expect(fresh.margin == 59)
        #expect(hold(&fresh, proof([editMenu, menuBar, desktop])) == saved(build, 75))
        #expect(fresh.margin == 75)
    }

    // MARK: Writes

    @Test("The margin is written only when it changes, never per sample")
    func writesOnlyOnChange() {
        let menuOpen = [finderMenu, menuBar, desktop]
        let editOpen = [editMenu, menuBar, desktop]
        let contextOpen = [contextMenu, menuBar, desktop]
        let nothing = [menuBar, desktop]
        // A session: a Finder menu held open for two seconds at 60 Hz, context menus, the Edit menu,
        // idle samples.
        let session = Array(repeating: nothing, count: 30) + Array(repeating: menuOpen, count: 120)
            + Array(repeating: contextOpen, count: 90) + Array(repeating: editOpen, count: 60)
            + Array(repeating: menuOpen, count: 60) + Array(repeating: nothing, count: 30)

        var first = SampledMenuMargin(stored: nil, build: build)
        var writes = session.compactMap { first.note(proof($0)) }
        let saved: [MenuMarginMemory.Write] = [.save(MenuMarginMemory.Record(build: build, margin: 75))]
        #expect(writes == saved)

        // The next launch on the same build loads it and writes nothing.
        var second = SampledMenuMargin(stored: first.stored, build: build)
        #expect(second.margin == 75)
        writes = session.compactMap { second.note(proof($0)) }
        #expect(writes.isEmpty)

        // After an OS update the old record is replaced once.
        var updated = SampledMenuMargin(stored: first.stored, build: "26C55")
        #expect(updated.margin == 0)
        writes = session.compactMap { updated.note(proof($0)) }
        let resaved: [MenuMarginMemory.Write] = [.save(MenuMarginMemory.Record(build: "26C55", margin: 75))]
        #expect(writes == resaved)

        // With no build known, the margin is used for the session and never stored.
        var unknown = SampledMenuMargin(stored: nil, build: nil)
        writes = session.compactMap { unknown.note(proof($0)) }
        #expect(writes.isEmpty)
        #expect(unknown.margin == 75)
    }

    // MARK: Stored values

    @Test("A stored record round-trips through a property list, as defaults keep it")
    func recordRoundTrip() throws {
        let record = MenuMarginMemory.Record(build: build, margin: 75)
        let data = try PropertyListSerialization.data(fromPropertyList: record.storedValue, format: .binary, options: 0)
        let read = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        #expect(MenuMarginMemory.Record(storedValue: read) == record)
        #expect(MenuMarginMemory.defaultsKey == "windowFilterMenuMargin")

        // Hand-written with `defaults write ... -dict build 26B131 margin -int 75` or `-float 75.5`.
        for (xml, margin) in [("<integer>75</integer>", CGFloat(75)), ("<real>75.5</real>", CGFloat(75.5))] {
            let read = try plist("<dict><key>build</key><string>26B131</string><key>margin</key>\(xml)</dict>")
            #expect(MenuMarginMemory.Record(storedValue: read) == makeRecord(build, margin))
        }
    }

    @Test("Stored values this code did not write are ignored")
    func garbageIsIgnored() throws {
        let garbage: [(String, Any?)] = [
            ("absent", nil),
            ("a number", 75),
            ("a string", "26B131:75"),
            ("data", Data([1, 2, 3])),
            ("an array", [build, 75] as [Any]),
            ("empty", [String: Any]()),
            ("no margin", ["build": build]),
            ("no build", ["margin": 75]),
            ("empty build", ["build": "", "margin": 75] as [String: Any]),
            ("numeric build", ["build": 26, "margin": 75]),
            ("margin as a string", ["build": build, "margin": "75"]),
            ("margin as a bool", ["build": build, "margin": true] as [String: Any]),
            ("zero margin", ["build": build, "margin": 0] as [String: Any]),
            ("negative margin", ["build": build, "margin": -75] as [String: Any]),
            ("margin too wide", ["build": build, "margin": 129] as [String: Any]),
            ("not a number", ["build": build, "margin": Double.nan] as [String: Any]),
            ("infinite", ["build": build, "margin": Double.infinity] as [String: Any]),
            ("integer keys", [1: build, 2: 75] as [Int: Any]),
        ]
        for (name, value) in garbage {
            let record = MenuMarginMemory.Record(storedValue: value)
            #expect(record == nil, "\(name)")
            #expect(MenuMarginMemory(stored: record, build: build).margin == 0, "\(name)")
        }
        // Booleans hand-written with `defaults write`, as a property list holds them.
        let bool = try plist("<dict><key>build</key><string>26B131</string><key>margin</key><true/></dict>")
        #expect(MenuMarginMemory.Record(storedValue: bool) == nil)
        // The widest margin a menu can prove is accepted.
        let widest: [String: Any] = ["build": build, "margin": 128]
        let widestRecord: MenuMarginMemory.Record? = MenuMarginMemory.Record(build: build, margin: 128)
        #expect(MenuMarginMemory.Record(storedValue: widest) == widestRecord)
    }

    private func plist(_ body: String) throws -> Any {
        let xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\">\(body)</plist>"
        return try PropertyListSerialization.propertyList(from: Data(xml.utf8), options: [], format: nil)
    }

    // MARK: Macs without padded menus

    /// Window lists from a Mac whose menus have no margin (macOS 26.6): a menu-bar menu, a context
    /// menu, another app's menu-bar menu and panel over an excluded window, and nothing at all.
    private var unpaddedSamples: [[WindowHolePolicy.Window]] {
        let window = CGRect(x: 200, y: 60, width: 700, height: 500)
        let excluded = WindowHolePolicy.Window(bounds: window, layer: 0, owner: terminal, cornerRadius: 16)
        return [
            [.init(bounds: CGRect(x: 820, y: 300, width: 180, height: 220), layer: 101, owner: terminal, cornerRadius: 12),
             menuBar, excluded],
            [unpaddedMenu(radius: nil), menuBar, excluded],
            [unpaddedMenu(), menuBar, excluded],
            [.init(bounds: CGRect(x: 300, y: 34, width: 184, height: 294), layer: 101, owner: lulu, isRegularApp: false,
                   cornerRadius: 12),
             .init(bounds: CGRect(x: 600, y: 100, width: 150, height: 100), layer: 101, owner: 6, isRegularApp: false),
             menuBar, excluded],
            [menuBar, excluded],
            [],
        ]
    }

    /// What this checks is the memory, not the hole: no sample reads a margin, so the margin stays
    /// zero and `neutralRegion` gets the same `menuMargin: 0` it got in 1.1.19. That the zero-margin
    /// hole itself is 1.1.19's is pinned by `PaddedMenuCornerTests.unpaddedOutputMatchesRelease`.
    @Test("Without padded menus no sample reads a margin, the margin stays zero, and only another build's record is removed")
    func unpaddedMacKeepsZeroMargin() {
        let starts: [(String, MenuMarginMemory.Record?)] = [
            ("nothing stored", nil),
            ("garbage stored", MenuMarginMemory.Record(storedValue: ["build": "25G72", "margin": "75"])),
            ("another build's record", .init(build: otherBuild, margin: 75)),
        ]
        for (name, stored) in starts {
            var memory = SampledMenuMargin(stored: stored, build: "25G72")
            #expect(memory.margin == 0, "\(name)")
            var writes: [MenuMarginMemory.Write] = []
            for _ in 0..<3 {
                for sample in unpaddedSamples {
                    #expect(WindowHolePolicy.observedMenuMargin(in: sample, displays: [display]) == nil, "\(name)")
                    if let write = memory.note(proof(sample, front: terminal)) { writes.append(write) }
                    #expect(memory.margin == 0, "\(name)")
                }
            }
            // Only another build's record is removed, once, by the front app's 12 pt menu-bar menu.
            let expected: [MenuMarginMemory.Write] = stored == nil ? [] : [.clear]
            #expect(writes == expected, "\(name)")
        }
    }
}
