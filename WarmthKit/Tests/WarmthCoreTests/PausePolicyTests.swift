import Testing
import Foundation
import CoreGraphics
@testable import WarmthCore

@Suite("Pause policy")
struct PausePolicyTests {

    @Test("One hour is an absolute 3600 seconds, and a past or far pause is inactive")
    func expiry() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let hour = PausePolicy.oneHour(from: now)
        #expect(hour.kind == .oneHour)
        #expect(hour.until.timeIntervalSince(now) == 3_600)
        #expect(PausePolicy.active(hour, at: now.addingTimeInterval(3_599)) == hour)
        #expect(PausePolicy.active(hour, at: hour.until) == nil)
        #expect(PausePolicy.active(hour, at: now.addingTimeInterval(-10)) == hour)

        let stale = TimedPause(until: now.addingTimeInterval(-1), kind: .untilSunrise)
        #expect(PausePolicy.active(stale, at: now) == nil)

        let corrupt = TimedPause(until: now.addingTimeInterval(PausePolicy.maximumLead + 60), kind: .oneHour)
        #expect(PausePolicy.active(corrupt, at: now) == nil)
        #expect(PausePolicy.active(nil, at: now) == nil)
    }

    @Test("Geometry alone does not count a zoomed or notched-fullscreen frame")
    func coverage() {
        let builtIn = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let external = CGRect(x: 1512, y: 0, width: 1920, height: 1080)

        #expect(PausePolicy.coversDisplay(window: external, display: external))
        #expect(PausePolicy.coversDisplay(window: builtIn, display: builtIn))
        #expect(PausePolicy.coversDisplay(window: builtIn.insetBy(dx: 2, dy: 2), display: builtIn))

        // Probed maximized Chrome and notched Safari full screen: the same frame, under the menu bar.
        let underMenuBar = CGRect(x: 0, y: 33, width: 1512, height: 949)
        #expect(!PausePolicy.coversDisplay(window: underMenuBar, display: builtIn))

        let almost = CGRect(x: 0, y: 0, width: 1400, height: 880)
        #expect(!PausePolicy.coversDisplay(window: almost, display: builtIn))
        #expect(!PausePolicy.coversDisplay(window: .zero, display: builtIn))
        #expect(!PausePolicy.coversDisplay(window: builtIn, display: .zero))
    }

    @Test("A fullscreen toolbar strip listed first does not hide the covering window behind it")
    func stripBeforeContent() {
        let external = PausePolicy.ListedDisplay(
            id: 5, bounds: CGRect(x: 1512, y: 0, width: 1920, height: 1080))
        let builtIn = PausePolicy.ListedDisplay(
            id: 1, bounds: CGRect(x: 0, y: 0, width: 1512, height: 982))
        let strip = PausePolicy.ListedWindow(
            bounds: CGRect(x: 1512, y: 0, width: 1920, height: 75), layer: 0)
        let content = PausePolicy.ListedWindow(
            bounds: CGRect(x: 1512, y: 0, width: 1920, height: 1080), layer: 0)
        let notched = PausePolicy.ListedWindow(
            bounds: CGRect(x: 0, y: 33, width: 1512, height: 949), layer: 0)

        #expect(PausePolicy.fullScreenDisplayIDs(
            ownedWindows: [strip, content], displays: [external, builtIn]) == [5])
        #expect(PausePolicy.fullScreenDisplayIDs(
            ownedWindows: [strip, notched], displays: [external, builtIn]).isEmpty)
    }

    @Test("A notched native full-screen Space pauses that display, but a zoomed window does not")
    func notchedFullScreenSpace() {
        let builtIn = PausePolicy.ListedDisplay(
            id: 1, bounds: CGRect(x: 0, y: 0, width: 1512, height: 982))
        let external = PausePolicy.ListedDisplay(
            id: 5, bounds: CGRect(x: 1512, y: 0, width: 1920, height: 1080))
        let underNotch = PausePolicy.ListedWindow(
            bounds: CGRect(x: 0, y: 33, width: 1512, height: 949), layer: 0, owner: 7)
        let builtInDesktop = PausePolicy.BackdropWindow(bounds: builtIn.bounds, kind: .desktop)
        let externalDesktop = PausePolicy.BackdropWindow(bounds: external.bounds, kind: .desktop)
        let builtInBackdrop = PausePolicy.BackdropWindow(bounds: builtIn.bounds, kind: .fullScreenBackdrop)

        // Probed: settled full screen on the notched built-in drops Finder's desktop there and
        // adds the Dock backdrop. The external keeps its desktop and stays warm.
        let fullScreen = PausePolicy.fullScreenSpaceDisplayIDs(
            backdrops: [builtInBackdrop, externalDesktop], displays: [builtIn, external])
        #expect(fullScreen == [1])
        #expect(PausePolicy.fullScreenDisplayIDs(
            ownedWindows: [underNotch], displays: [builtIn, external], fullScreenSpaces: fullScreen) == [1])

        // A zoomed window has the same frame, but the desktop is still listed.
        #expect(PausePolicy.fullScreenSpaceDisplayIDs(
            backdrops: [builtInDesktop, externalDesktop], displays: [builtIn, external]).isEmpty)
    }

    @Test("The sliding full-screen animation does not pause either display")
    func fullScreenAnimation() {
        let builtIn = PausePolicy.ListedDisplay(
            id: 1, bounds: CGRect(x: 0, y: 0, width: 1512, height: 982))
        let external = PausePolicy.ListedDisplay(
            id: 5, bounds: CGRect(x: 1512, y: 0, width: 1920, height: 1080))
        // Probed 0.2s into the animation: the backdrop and old desktop slide sideways together.
        let sliding = [
            PausePolicy.BackdropWindow(bounds: CGRect(x: 1019, y: 0, width: 1512, height: 982), kind: .fullScreenBackdrop),
            PausePolicy.BackdropWindow(bounds: CGRect(x: -557, y: 0, width: 1512, height: 982), kind: .desktop),
            PausePolicy.BackdropWindow(bounds: external.bounds, kind: .desktop),
        ]
        #expect(PausePolicy.fullScreenSpaceDisplayIDs(backdrops: sliding, displays: [builtIn, external]).isEmpty)
    }

    @Test("Without the Dock backdrop or a filling window, a missing desktop is not full screen")
    func missingDesktopAlone() {
        let builtIn = PausePolicy.ListedDisplay(
            id: 1, bounds: CGRect(x: 0, y: 0, width: 1512, height: 982))
        // Finder's desktop can be turned off. That alone must not pause every display.
        #expect(PausePolicy.fullScreenSpaceDisplayIDs(backdrops: [], displays: [builtIn]).isEmpty)
    }

    @Test("With no Dock backdrop, a window filling the screen below the notch on a desktop-less Space counts")
    func fullScreenWithoutDockBackdrop() {
        let builtIn = PausePolicy.ListedDisplay(
            id: 1, bounds: CGRect(x: 0, y: 0, width: 1512, height: 982))
        let external = PausePolicy.ListedDisplay(
            id: 5, bounds: CGRect(x: 1512, y: 0, width: 1920, height: 1080))
        let underNotch = PausePolicy.ListedWindow(
            bounds: CGRect(x: 0, y: 33, width: 1512, height: 949), layer: 0, owner: 7)
        let externalDesktop = PausePolicy.BackdropWindow(bounds: external.bounds, kind: .desktop)

        #expect(PausePolicy.fullScreenSpaceDisplayIDs(
            backdrops: [externalDesktop], displays: [builtIn, external], ownedWindows: [underNotch],
            finderDesktopExists: true) == [1])

        // With Finder's desktop turned off or Finder relaunching, a missing desktop proves nothing:
        // the same frame may be a zoomed window.
        #expect(PausePolicy.fullScreenSpaceDisplayIDs(
            backdrops: [], displays: [builtIn, external], ownedWindows: [underNotch],
            finderDesktopExists: false).isEmpty)

        // The same frame with the desktop still listed is a zoomed window.
        let builtInDesktop = PausePolicy.BackdropWindow(bounds: builtIn.bounds, kind: .desktop)
        #expect(PausePolicy.fullScreenSpaceDisplayIDs(
            backdrops: [builtInDesktop, externalDesktop], displays: [builtIn, external],
            ownedWindows: [underNotch], finderDesktopExists: true).isEmpty)

        // A smaller window in front of a desktop-less Space does not count.
        let small = PausePolicy.ListedWindow(
            bounds: CGRect(x: 200, y: 200, width: 600, height: 400), layer: 0, owner: 9)
        #expect(PausePolicy.fullScreenSpaceDisplayIDs(
            backdrops: [externalDesktop], displays: [builtIn, external], ownedWindows: [small, underNotch],
            finderDesktopExists: true).isEmpty)

        // A strip taller than a notch is a window under a tall toolbar, not full screen.
        let lowered = PausePolicy.ListedWindow(
            bounds: CGRect(x: 0, y: 60, width: 1512, height: 922), layer: 0, owner: 7)
        #expect(PausePolicy.fullScreenSpaceDisplayIDs(
            backdrops: [externalDesktop], displays: [builtIn, external], ownedWindows: [lowered],
            finderDesktopExists: true).isEmpty)
    }

    @Test("Finder's desktop counts as existing when it is listed on any Space")
    func finderDesktopOnAnySpace() {
        let desktop = Int(CGWindowLevelForKey(.desktopIconWindow))
        let apps: [Int32: (bundleID: String?, isRegular: Bool)] = [
            3: ("com.apple.finder", true), 4: ("com.apple.dock", false),
        ]
        let lookup: (Int32) -> (bundleID: String?, isRegular: Bool) = { apps[$0] ?? (nil, false) }
        let finder: [String: Any] = [kCGWindowOwnerPID as String: Int32(3), kCGWindowLayer as String: desktop]
        let finderWindow: [String: Any] = [kCGWindowOwnerPID as String: Int32(3), kCGWindowLayer as String: 0]
        let dock: [String: Any] = [kCGWindowOwnerPID as String: Int32(4), kCGWindowLayer as String: desktop]
        #expect(PausePolicy.finderDesktopExists(allWindowInfo: [dock, finder], app: lookup))
        #expect(!PausePolicy.finderDesktopExists(allWindowInfo: [dock, finderWindow], app: lookup))
    }

    @Test("The classifier keeps visible normal windows and the Finder and Dock markers only")
    func classifierKeepsMarkers() {
        func window(_ pid: Int32, layer: Int, x: Double, alpha: Double = 1) -> [String: Any] {
            [kCGWindowOwnerPID as String: pid, kCGWindowLayer as String: layer, kCGWindowAlpha as String: alpha,
             kCGWindowBounds as String: CGRect(x: x, y: 0, width: 100, height: 100).dictionaryRepresentation]
        }
        let desktop = Int(CGWindowLevelForKey(.desktopIconWindow))
        let backdrop = Int(CGWindowLevelForKey(.desktopWindow)) + 1
        let apps: [Int32: (bundleID: String?, isRegular: Bool)] = [
            1: ("com.example.app", true), 2: ("com.example.overlay", false),
            3: ("com.apple.finder", true), 4: ("com.apple.dock", false),
        ]
        let sample = PausePolicy.classify(windowInfo: [
            window(1, layer: 0, x: 0),
            window(1, layer: 0, x: 10, alpha: 0),
            window(2, layer: 0, x: 20),
            window(3, layer: desktop, x: 30),
            window(4, layer: backdrop, x: 40),
            window(4, layer: desktop, x: 50),
            window(1, layer: 25, x: 60),
        ]) { apps[$0] ?? (nil, false) }

        #expect(sample.regularWindows.map(\.bounds.minX) == [0])
        #expect(sample.backdrops == [
            .init(bounds: CGRect(x: 30, y: 0, width: 100, height: 100), kind: .desktop),
            .init(bounds: CGRect(x: 40, y: 0, width: 100, height: 100), kind: .fullScreenBackdrop),
        ])
    }

    @Test("A mirror pauses with a source that is on a full-screen Space")
    func mirrorFollowsFullScreenSpace() {
        let source = PausePolicy.ListedDisplay(
            id: 1, bounds: CGRect(x: 0, y: 0, width: 1512, height: 982))
        let mirror = PausePolicy.ListedDisplay(id: 9, bounds: source.bounds)
        #expect(PausePolicy.fullScreenDisplayIDs(
            ownedWindows: [], displays: [mirror, source], mirroring: [9: 1], fullScreenSpaces: [1]) == [1, 9])
    }

    @Test("A hardware mirror pauses when the display it copies is covered")
    func mirrorPausesWithSource() {
        let source = PausePolicy.ListedDisplay(
            id: 1, bounds: CGRect(x: 0, y: 0, width: 1512, height: 982))
        let cover = PausePolicy.ListedWindow(
            bounds: CGRect(x: 0, y: 0, width: 1512, height: 982), layer: 0)
        let ids = PausePolicy.fullScreenDisplayIDs(
            ownedWindows: [cover],
            displays: [source],
            mirroring: [9: 1]
        )
        #expect(ids == [1, 9])
    }

    @Test("A mirror listed before its source still pauses with that source")
    func mirrorListedFirst() {
        let source = PausePolicy.ListedDisplay(
            id: 1, bounds: CGRect(x: 0, y: 0, width: 1512, height: 982))
        let mirror = PausePolicy.ListedDisplay(id: 9, bounds: source.bounds)
        let cover = PausePolicy.ListedWindow(bounds: source.bounds, layer: 0, owner: 1)
        #expect(PausePolicy.fullScreenDisplayIDs(
            ownedWindows: [cover],
            displays: [mirror, source],
            mirroring: [9: 1]
        ) == [1, 9])
    }

    @Test("A covering window on one display stays covered when another display's window is listed first")
    func coverStaysWhenFocusMoves() {
        let builtIn = PausePolicy.ListedDisplay(
            id: 1, bounds: CGRect(x: 0, y: 0, width: 1512, height: 982))
        let external = PausePolicy.ListedDisplay(
            id: 5, bounds: CGRect(x: 1512, y: 0, width: 1920, height: 1080))
        let focused = PausePolicy.ListedWindow(
            bounds: CGRect(x: 80, y: 80, width: 640, height: 480), layer: 0, owner: 1)
        let cover = PausePolicy.ListedWindow(bounds: external.bounds, layer: 0, owner: 2)
        #expect(PausePolicy.fullScreenDisplayIDs(
            ownedWindows: [focused, cover], displays: [builtIn, external]) == [5])
    }

    @Test("A window that only clips the next display does not hide that display's cover")
    func overhangDoesNotHideCover() {
        let builtIn = PausePolicy.ListedDisplay(
            id: 1, bounds: CGRect(x: 0, y: 0, width: 1512, height: 982))
        let external = PausePolicy.ListedDisplay(
            id: 5, bounds: CGRect(x: 1512, y: 0, width: 1920, height: 1080))
        let overhang = PausePolicy.ListedWindow(
            bounds: CGRect(x: 80, y: 40, width: 1500, height: 700), layer: 0, owner: 1)
        let cover = PausePolicy.ListedWindow(bounds: external.bounds, layer: 0, owner: 2)
        #expect(PausePolicy.fullScreenDisplayIDs(
            ownedWindows: [overhang, cover], displays: [builtIn, external]) == [5])
    }

    @Test("A small window of another app above a cover keeps that display warm")
    func smallWindowAboveCover() {
        let external = PausePolicy.ListedDisplay(
            id: 5, bounds: CGRect(x: 1512, y: 0, width: 1920, height: 1080))
        let small = PausePolicy.ListedWindow(
            bounds: CGRect(x: 1600, y: 200, width: 400, height: 300), layer: 0, owner: 1)
        let cover = PausePolicy.ListedWindow(bounds: external.bounds, layer: 0, owner: 2)
        #expect(PausePolicy.fullScreenDisplayIDs(
            ownedWindows: [small, cover], displays: [external]).isEmpty)
    }
    @Test("Next sunrise ends when Sunset goes neutral, not at astronomical dawn")
    func sunrise() throws {
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let afternoon = losAngeles.date(from: DateComponents(year: 2026, month: 6, day: 21, hour: 15))!
        let coordinate = TimeZoneCoordinates.coordinate(
            forIdentifier: "America/Los_Angeles", secondsFromGMT: -28_800)

        let next = PausePolicy.nextSunrise(
            at: afternoon, latitude: coordinate.latitude, longitude: coordinate.longitude, calendar: losAngeles)
        let sunrise = try #require(next)
        #expect(sunrise > afternoon)
        #expect(sunrise.timeIntervalSince(afternoon) < 26 * 3_600)

        let elevation = ScheduleResolver.solarElevationDegrees(
            at: sunrise, latitude: coordinate.latitude, longitude: coordinate.longitude)
        #expect(elevation > ScheduleResolver.rampFullElevation)
        #expect(abs(elevation - ScheduleResolver.rampStartElevation) < 1)

        let local = losAngeles.dateComponents([.hour, .minute], from: sunrise)
        #expect((4...9).contains(local.hour ?? -1))

        let before = sunrise.addingTimeInterval(-2 * 3_600)
        let sameMorning = PausePolicy.nextSunrise(
            at: before, latitude: coordinate.latitude, longitude: coordinate.longitude, calendar: losAngeles)
        #expect(sameMorning == sunrise)

        let polar = PausePolicy.nextSunrise(
            at: afternoon, latitude: 80, longitude: 0, calendar: losAngeles)
        #expect(polar == nil)
        #expect(PausePolicy.nextSunrise(at: afternoon, latitude: .nan, longitude: 0) == nil)
    }

    @Test("A high-latitude winter sunrise falls back to the horizon when the sun never reaches +6")
    func winterSunrise() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let afternoon = utc.date(from: DateComponents(year: 2026, month: 12, day: 21, hour: 15))!
        let next = try #require(PausePolicy.nextSunrise(
            at: afternoon, latitude: 64.15, longitude: -21.94, calendar: utc))
        let elevation = ScheduleResolver.solarElevationDegrees(
            at: next, latitude: 64.15, longitude: -21.94)
        #expect(elevation < ScheduleResolver.rampStartElevation)
        #expect(abs(elevation - ScheduleResolver.rampFullElevation) < 1)
    }
}
