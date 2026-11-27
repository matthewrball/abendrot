import Testing
import Foundation
import CoreGraphics
@testable import WarmthCore

/// #39: the corner a padded macOS 27 menu is cut at, against the corner macOS draws, and proof
/// that nothing else moved.
@Suite("Padded menu corners (#39)")
struct PaddedMenuCornerTests {
    private let display = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let menuBar = CGRect(x: 0, y: 0, width: 1512, height: 33)
    private let excludedApp: Int32 = 7
    private let menuBarApp: Int32 = 5
    private let margin: CGFloat = 75

    /// How far in from its side a macOS 27.2.1 menu's drawn outline sits on each device row
    /// (2 per point) from the top, rows 1 to 29, in points. The mean over ten corners in four of
    /// the reporter's screenshots: a menu-bar app's menu (the #39 screenshot), Finder's Apple and
    /// File menus, and a contextual menu. The corners agree to 0.13 pt on every row. Row 0 is
    /// left out: its inset is the whole tail of the curve along the top edge, not a point on
    /// it. Measured from the screenshots for #39.
    private static let drawnInset: [CGFloat] = [
        8.26, 6.88, 5.87, 5.07, 4.39, 3.79, 3.29, 2.84, 2.51, 2.15, 1.79, 1.57, 1.29, 1.10, 0.94,
        0.76, 0.62, 0.51, 0.49, 0.40, 0.31, 0.24, 0.19, 0.15, 0.12, 0.10, 0.08, 0.07, 0.06,
    ]

    /// With 1 pt corner rows on a 2x display the cut is a staircase of 2-pixel steps, so one of
    /// the two device rows in each step lands up to about a pixel off any curve. Past that, a
    /// cut that leaves more of the menu on the wrong side is the #39 line, and one that leaves
    /// more of the backdrop on the menu's side is a new fringe outside the menu.
    private static let tolerance: CGFloat = 0.55

    private enum Corner: CaseIterable { case topLeft, topRight, bottomLeft, bottomRight }

    /// The spans of `region` that cross the horizontal line at `y`, merged where they touch.
    private func spans(_ region: [CGRect], atY y: CGFloat) -> [(minX: CGFloat, maxX: CGFloat)] {
        let crossing = region.filter { $0.minY <= y && y < $0.maxY }.sorted { $0.minX < $1.minX }
        var merged: [(minX: CGFloat, maxX: CGFloat)] = []
        for rect in crossing {
            if let last = merged.last, rect.minX <= last.maxX + 1e-9 {
                merged[merged.count - 1].maxX = max(last.maxX, rect.maxX)
            } else {
                merged.append((rect.minX, rect.maxX))
            }
        }
        return merged
    }

    /// How far in from the menu's side the cut sits on device row `row` of `corner`: where the
    /// menu's colour starts. `menuIsNeutral` is true for the excluded app's own menu (the hole is
    /// the menu) and false for another app's menu in front of the excluded window (the hole is
    /// outside it).
    private func cutInset(_ region: [CGRect], menu: CGRect, corner: Corner, row: Int, menuIsNeutral: Bool) -> CGFloat {
        let offset = (CGFloat(row) + 0.5) / 2
        let top = corner == .topLeft || corner == .topRight
        let left = corner == .topLeft || corner == .bottomLeft
        let line = spans(region, atY: top ? menu.minY + offset : menu.maxY - offset)
        let side = left ? menu.minX : menu.maxX
        let probe = left ? side + 1e-6 : side - 1e-6
        if menuIsNeutral {
            // The neutral span reaching furthest towards the side.
            let inside = line.filter { left ? $0.maxX > probe : $0.minX < probe }
            guard let span = left ? inside.first : inside.last else { return 0 }
            return max(0, left ? span.minX - side : side - span.maxX)
        }
        // The neutral span, if any, that runs in from the side over the menu's square corner.
        guard let span = line.first(where: { $0.minX <= probe && probe < $0.maxX }) else { return 0 }
        return left ? span.maxX - side : side - span.minX
    }

    /// Same pieces in the same order, to within the float rounding of clipping to the display.
    private func sameRegion(_ a: [CGRect], _ b: [CGRect]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { lhs, rhs in
            abs(lhs.minX - rhs.minX) < 1e-9 && abs(lhs.minY - rhs.minY) < 1e-9
                && abs(lhs.width - rhs.width) < 1e-9 && abs(lhs.height - rhs.height) < 1e-9
        }
    }

    private func expectFollowsDrawnCorner(_ region: [CGRect], menu: CGRect, menuIsNeutral: Bool) {
        for corner in Corner.allCases {
            var menuSide: CGFloat = 0
            var backdropSide: CGFloat = 0
            for (index, drawn) in Self.drawnInset.enumerated() {
                let cut = cutInset(region, menu: menu, corner: corner, row: index + 1, menuIsNeutral: menuIsNeutral)
                menuSide = max(menuSide, cut - drawn)
                backdropSide = max(backdropSide, drawn - cut)
            }
            #expect(menuSide <= Self.tolerance, "\(corner): \(menuSide) pt of the menu on the wrong side")
            #expect(backdropSide <= Self.tolerance, "\(corner): \(backdropSide) pt outside the menu on its side")
        }
    }

    @Test("A menu-bar app's padded menu over an excluded window stays warm up to its drawn corner")
    func warmPaddedMenuFollowsDrawnCorner() {
        // The #39 screenshot: a 136 pt wide menu under a status item, over the excluded window.
        let menu = CGRect(x: 600, y: 34, width: 136, height: 200)
        let windows: [WindowHolePolicy.Window] = [
            .init(bounds: menu.insetBy(dx: -margin, dy: -margin), layer: 101, owner: menuBarApp, isRegularApp: false),
            .init(bounds: menuBar, layer: 24, owner: 1, isRegularApp: false),
            .init(bounds: CGRect(x: 100, y: 34, width: 1200, height: 800), layer: 0, owner: excludedApp),
        ]
        let region = WindowHolePolicy.neutralRegion(
            windows: windows, owner: excludedApp, display: display, cornerRadius: 16, menuMargin: margin,
            reportsCornerRadii: true)
        expectFollowsDrawnCorner(region, menu: menu, menuIsNeutral: false)
    }

    @Test("The excluded app's padded menu is neutral up to its drawn corner")
    func neutralPaddedMenuFollowsDrawnCorner() {
        let menu = CGRect(x: 300, y: 34, width: 243, height: 180)
        let windows: [WindowHolePolicy.Window] = [
            .init(bounds: menu.insetBy(dx: -margin, dy: -margin), layer: 101, owner: excludedApp),
            .init(bounds: menuBar, layer: 24, owner: 1, isRegularApp: false),
        ]
        let region = WindowHolePolicy.neutralRegion(
            windows: windows, owner: excludedApp, display: display, cornerRadius: 16, menuMargin: margin,
            reportsCornerRadii: true)
        expectFollowsDrawnCorner(region, menu: menu, menuIsNeutral: true)
    }

    @Test("Menus that are not padded, and padded menus that report a radius, keep their radius exactly")
    func otherMenusKeepTheirRadius() {
        let menu = CGRect(x: 600, y: 300.5, width: 184.5, height: 120)
        let excluded = CGRect(x: 100, y: 100, width: 1200, height: 800)
        // macOS 26: no margin. The titled default for no radius, the reported one otherwise.
        for reported: CGFloat? in [nil, 0, 12, 13.5] {
            let known = reported.flatMap { $0 > 0 ? $0 : nil }
            let own = WindowHolePolicy.neutralRegion(
                windows: [.init(bounds: menu, layer: 101, owner: excludedApp, cornerRadius: reported)],
                owner: excludedApp, display: display, cornerRadius: 16)
            #expect(sameRegion(own, WindowHolePolicy.roundedInterior(menu, radius: known ?? 16)))
            // Another app's menu in front: square with no radius, rounded at the reported one.
            let other = WindowHolePolicy.neutralRegion(windows: [
                .init(bounds: menu, layer: 101, owner: 3, cornerRadius: reported),
                .init(bounds: excluded, layer: 0, owner: excludedApp),
            ], owner: excludedApp, display: display)
            let corner = CGPoint(x: menu.minX + 0.25, y: menu.minY + 0.25)
            #expect(other.contains { $0.contains(corner) } == (known != nil))
            #expect(!other.contains { $0.contains(CGPoint(x: menu.midX, y: menu.midY)) })
        }
        // A menu-level window that reports a radius is rounded by WindowServer at its own bounds, so
        // it has no transparent margin (#38): with a margin proven it still counts at its bounds and
        // its own radius, never at the padded radius.
        let window = menu.insetBy(dx: -margin, dy: -margin)
        for reported: CGFloat in [10, 12, 16] {
            let own = WindowHolePolicy.neutralRegion(
                windows: [.init(bounds: window, layer: 101, owner: excludedApp, cornerRadius: reported)],
                owner: excludedApp, display: display, cornerRadius: 16, menuMargin: margin)
            #expect(sameRegion(own, WindowHolePolicy.roundedInterior(window, radius: reported)))
        }
    }

    // Each pinned value below is FNV-1a over every rect the policy returns for 2,000 seeded scenes
    // of one kind. Coordinates are hashed on a 2^-20 pt grid, so a CI runner whose CoreGraphics
    // rounds a clipped rect's last bit differently does not fail; any change to a radius, a row or a
    // tile still does. Each value was found by compiling the block between BEGIN SCENES and END
    // SCENES, with a main that prints `hash(kind: kind, seed: 39, count: 2000, exact: false)` per kind,
    // against the WarmthCore sources of each tree:
    // swiftc -O -package-name wk -module-name WarmthCore -o hashes main.swift <tree>/WarmthKit/Sources/WarmthCore/*.swift
    // for the 1.1.19 release, the #38 change alone, the #39 change alone and this tree. Compared
    // scene by scene, every scene equals 1.1.19, #38 alone or #39 alone by which menu-level windows
    // it holds.

    /// `noMargin` (macOS 26 and earlier, no margin proven) equals 1.1.19 compiled on its own
    /// sources: neither #38 nor #39 touches a scene without a menu margin.
    @Test("Without a padded menu that lacks a radius, the 12.25 pt corner changes no hole or tile")
    func unpaddedOutputMatchesRelease() {
        #expect(PaddedMenuIdentityScenes.hash(kind: .noMargin, seed: 39, count: 2000, exact: false) == 0x160A_FA75_8015_9BEA)
    }

    /// `paddedNoRadius` changes with #39 alone: every menu-level window reports no radius, so #38's
    /// rule never applies and only the padded corner moves. The value equals #39 alone and this
    /// tree; 1.1.19's 13 pt corner gives 0x616E_DF77_D298_5C68.
    @Test("Padded menus that all report no radius are cut at the 12.25 pt corner, exactly as #39 alone cuts them")
    func paddedWithoutRadiusMatches39Alone() {
        #expect(PaddedMenuIdentityScenes.hash(kind: .paddedNoRadius, seed: 39, count: 2000, exact: false) == 0x8B51_FF1E_69A6_B9FC)
    }

    /// A #38 change detector, kept here because the scenes live here: `reportedRadii` is not
    /// 1.1.19's (0x58AE_3989_61C9_7A2E) because #38 counts a menu-level window that reports a radius
    /// at its own bounds. The value equals #38 alone, so #39's padded corner touches none of
    /// these scenes.
    @Test("#38 change detector: padded menu windows that all report a radius are counted at their bounds, as #38 alone counts them")
    func reportedRadiiMatch38Alone() {
        #expect(PaddedMenuIdentityScenes.hash(kind: .reportedRadii, seed: 39, count: 2000, exact: false) == 0xAC55_1B67_A92B_32EB)
    }
}

// BEGIN SCENES - the identity scripts copy this block verbatim, up to END SCENES.
/// Seeded random window lists for comparing the policy's output between builds.
fileprivate enum PaddedMenuIdentityScenes {
    enum Kind {
        /// macOS 26 and earlier: no menu margin proven. Menus, popovers, floating and normal
        /// windows, with and without reported radii.
        case noMargin
        /// macOS 27 padded menus whose windows all report a radius, so the padded fallback never applies.
        case reportedRadii
        /// macOS 27 padded menus of which about two thirds report a radius and a third none (nil or
        /// 0). Both #38 and #39 change these scenes; comparing each scene with #38 alone and #39
        /// alone tells them apart.
        case paddedWithoutRadius
        /// macOS 27 padded menus that all report no radius (nil or 0), as the reporter's do: the
        /// scenes #39 alone changes.
        case paddedNoRadius
    }

    /// SplitMix64, so every run and every machine sees the same scenes.
    struct Random {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func int(_ range: ClosedRange<Int>) -> Int {
            range.lowerBound + Int(next() % UInt64(range.upperBound - range.lowerBound + 1))
        }
        mutating func chance(_ percent: Int) -> Bool { int(0...99) < percent }
        /// A value on a quarter-point grid in `range` points.
        mutating func quarter(_ range: ClosedRange<Int>) -> CGFloat {
            let quarters = int((range.lowerBound * 4)...(range.upperBound * 4))
            return CGFloat(quarters) / 4
        }
        mutating func rect(x: ClosedRange<Int>, y: ClosedRange<Int>, width: ClosedRange<Int>, height: ClosedRange<Int>) -> CGRect {
            let originX = quarter(x)
            let originY = quarter(y)
            let sizeX = quarter(width)
            let sizeY = quarter(height)
            return CGRect(x: originX, y: originY, width: sizeX, height: sizeY)
        }
        mutating func radius(allowUnknown: Bool) -> CGFloat? {
            if allowUnknown {
                switch int(0...5) {
                case 0: return nil
                case 1: return 0
                default: break
                }
            }
            let whole = int(4...40)
            let fraction = CGFloat(int(0...3)) / 4
            return CGFloat(whole) + fraction
        }
    }

    static let display = CGRect(x: 0, y: 0, width: 1512, height: 982)
    static let menuBar = CGRect(x: 0, y: 0, width: 1512, height: 33)
    static let margin: CGFloat = 75

    static func scene(_ kind: Kind, _ random: inout Random) -> (windows: [WindowHolePolicy.Window], margin: CGFloat, fallback: CGFloat, floating: Set<Int32>, reports: Bool) {
        let excluded: Int32 = 7
        let padded = kind != .noMargin
        let unknownRadii = kind != .reportedRadii
        var windows: [WindowHolePolicy.Window] = []
        for _ in 0..<random.int(1...3) {
            let bounds = random.rect(x: -100...1300, y: 0...800, width: 60...900, height: 40...700)
            windows.append(.init(bounds: bounds, layer: 0, owner: excluded, cornerRadius: random.radius(allowUnknown: true)))
        }
        for _ in 0..<random.int(0...3) {
            let bounds = random.rect(x: -100...1300, y: 0...800, width: 60...900, height: 40...700)
            let owner = Int32(random.int(8...10))
            windows.append(.init(bounds: bounds, layer: 0, owner: owner, alpha: random.chance(90) ? 1 : 0,
                                 cornerRadius: random.radius(allowUnknown: true)))
        }
        for _ in 0..<random.int(0...3) {
            var body = random.rect(x: 0...1300, y: 34...700, width: 40...300, height: 30...400)
            if random.chance(50) { body.origin.y = menuBar.maxY + 1 }
            let owner: Int32 = [excluded, 3, 5][random.int(0...2)]
            let bounds = padded ? body.insetBy(dx: -margin, dy: -margin) : body
            let radius: CGFloat? = kind == .paddedNoRadius
                ? (random.chance(50) ? nil : 0) : random.radius(allowUnknown: unknownRadii)
            windows.append(.init(bounds: bounds, layer: 101, owner: owner, isRegularApp: owner != 5,
                                 cornerRadius: radius))
        }
        if random.chance(40) {
            // A menu-bar extra's popover window under its status item, and the item.
            let width = random.quarter(80...400)
            let left = random.quarter(200...1100)
            windows.append(.init(bounds: CGRect(x: left, y: menuBar.maxY - 5, width: width, height: random.quarter(80...500)),
                                 layer: 25, owner: 11, isRegularApp: false,
                                 cornerRadius: random.chance(70) ? nil : random.radius(allowUnknown: false)))
            windows.append(.init(bounds: CGRect(x: left + width / 2 - 12, y: 0, width: 24, height: menuBar.height),
                                 layer: 25, owner: 12, isRegularApp: false))
        }
        if random.chance(30) {
            let bounds = random.rect(x: 0...1200, y: 40...700, width: 100...400, height: 60...300)
            windows.append(.init(bounds: bounds, layer: 3, owner: random.chance(50) ? excluded : 9,
                                 cornerRadius: random.radius(allowUnknown: true)))
        }
        if random.chance(80) {
            windows.append(.init(bounds: menuBar, layer: 24, owner: 1, isRegularApp: false))
        }
        // Front to back in a random order.
        for index in stride(from: windows.count - 1, to: 0, by: -1) {
            windows.swapAt(index, random.int(0...index))
        }
        let fallback: CGFloat = [0, 16, 12.5][random.int(0...2)]
        let floating: Set<Int32> = random.chance(50) ? [9] : []
        return (windows, padded ? margin : 0, fallback, floating, random.chance(70))
    }

    /// `exact` hashes each coordinate's bits; otherwise its value rounded to a 2^-20 pt grid.
    static func hash(kind: Kind, seed: UInt64, count: Int, exact: Bool) -> UInt64 {
        var random = Random(state: seed)
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        func mix(_ value: UInt64) {
            hash = (hash ^ value) &* 0x0000_0100_0000_01B3
        }
        func mix(_ value: CGFloat) {
            let double = Double(value)
            mix(exact ? double.bitPattern : UInt64(bitPattern: Int64((double * 1_048_576).rounded())))
        }
        for _ in 0..<count {
            let scene = scene(kind, &random)
            let region = WindowHolePolicy.neutralRegion(
                windows: scene.windows, owner: 7, display: display, cornerRadius: scene.fallback,
                floatingOwners: scene.floating, menuMargin: scene.margin, reportsCornerRadii: scene.reports)
            let tiles = WindowHolePolicy.warmTiles(around: region, in: display)
            for rects in [region, tiles] {
                mix(UInt64(rects.count))
                for rect in rects {
                    mix(rect.minX)
                    mix(rect.minY)
                    mix(rect.width)
                    mix(rect.height)
                }
            }
        }
        return hash
    }
}
// END SCENES
