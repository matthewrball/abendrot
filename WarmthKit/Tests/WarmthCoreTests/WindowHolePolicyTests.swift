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
}
