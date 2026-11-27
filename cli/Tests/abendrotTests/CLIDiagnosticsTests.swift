import Testing
import CoreGraphics
import Foundation
import WarmthCore
@testable import abendrot

/// #38: `abendrot debug fullscreen` must give the padded-menu verdict
/// the app gives, from the radius the app gets.
@Suite("debug fullscreen: the app's radius rule (#38)")
struct CLIRadiusVerdictTests {
    private let alert = CGRect(x: 422, y: 180, width: 667, height: 461)

    @Test("A menu-level window that reports 100 pt may be a padded menu, as in the app")
    func overLimitRadiusMayBeAMenu() {
        #expect(MenuLevelDetail.text(bounds: alert, radius: 100, tags: nil, shadow: nil) == " padded menu: possible")
        #expect(MenuLevelDetail.text(bounds: alert, radius: 80, tags: nil, shadow: nil) == " padded menu: possible")
        #expect(MenuLevelDetail.text(bounds: alert, radius: .infinity, tags: nil, shadow: nil) == " padded menu: possible")
        #expect(MenuLevelDetail.text(bounds: alert, radius: -1, tags: nil, shadow: nil) == " padded menu: possible")
    }

    @Test("A radius just under 80 pt still counts as reported")
    func underLimitRadiusIsReported() {
        #expect(MenuLevelDetail.text(bounds: alert, radius: 79.9, tags: nil, shadow: nil)
            == " padded menu: no (reports a radius)")
        #expect(MenuLevelDetail.text(bounds: alert, radius: 0.5, tags: nil, shadow: nil)
            == " padded menu: no (reports a radius)")
    }

    @Test("Radii a macOS 26 window reports print and judge as before")
    func macOS26RadiiUnchanged() {
        for value: Double in [0, 0.5, 12, 12.25, 15, 16, 20, 26, 79.9, -1, .nan] {
            // The old verdict: the raw radius straight into the app's Window.
            let old = WindowHolePolicy.Window(bounds: alert, layer: WindowHolePolicy.popUpMenuLayer, owner: 0,
                                              cornerRadius: CGFloat(value)).canBePaddedMenu
            #expect(MenuLevelDetail.text(bounds: alert, radius: value, tags: nil, shadow: nil)
                == (old ? " padded menu: possible" : " padded menu: no (reports a radius)"), "\(value)")
        }
        for value: Double in [0, 12, 16, 20, 26] {
            let corners = [value, value, value, value]
            // The old reduction: the raw largest finite value.
            let old = corners.filter(\.isFinite).max() ?? 0
            #expect(CornerRadii.radius(from: corners as CFArray) == old)
        }
    }
}

/// The radius `CornerRadii` makes of one window's corner values is the one the app's window query
/// makes (`largestRadius` in CInterop's WindowFilter.m).
@Suite("debug fullscreen: corner values reduce as in the app (#38)")
struct CLICornerReductionTests {
    @Test("The largest finite number, starting from 0")
    func largestFiniteFromZero() {
        func radius(_ values: [Any]) -> Double { CornerRadii.radius(from: values as CFArray) }
        #expect(radius([16, 16, 16, 16]) == 16)
        #expect(radius([16, 16, 100, 16]) == 100)
        #expect(radius([Double.nan, 12, 12, 12]) == 12)
        #expect(radius([Double.infinity, 12]) == 12)
        // Before: the raw largest, so -1 here, and nothing counted once one value was not a number.
        #expect(radius([-1, -1, -1, -1]) == 0)
        #expect(radius([]) == 0)
        #expect(radius(["12", 16]) == 16)
        // A boolean is no CFNumber to the app's query.
        #expect(radius([true, 0.5]) == 0.5)
        #expect(CornerRadii.radius(from: nil) == 0)
    }
}

/// #37: `debug fullscreen` shows the menu margin the app remembers, and whether the app uses it.
@Suite("debug fullscreen: the remembered menu margin (#37)")
struct MenuMarginLineTests {
    private let record: [String: Any] = ["build": "26B131", "margin": 75.0]

    @Test("A record from this Mac's build is used on macOS 26 and later, where the radius query exists")
    func sameBuildIsUsed() {
        #expect(MenuMarginLine.text(storedValue: record, build: "26B131", osMajor: 27, radiusQueryExists: true)
            == "Menu margin remembered: 75 pt, proven on 26B131 (this Mac), used when Keep other windows warm is on")
        #expect(MenuMarginLine.text(storedValue: record, build: "26B131", osMajor: 26, radiusQueryExists: true)
            == "Menu margin remembered: 75 pt, proven on 26B131 (this Mac), used when Keep other windows warm is on")
    }

    @Test("A wrong margin the app kept (#37: an outlier as the first reading on a build) shows as it is stored")
    func keptOutlierIsShown() {
        // A quick terminal stalled above the top edge is the first reading on a new build: 94 is kept,
        // and `defaults delete app.abendrot.Abendrot windowFilterMenuMargin` removes it.
        let outlier: [String: Any] = ["build": "26B131", "margin": 94.0]
        #expect(MenuMarginLine.text(storedValue: outlier, build: "26B131", osMajor: 27, radiusQueryExists: true)
            == "Menu margin remembered: 94 pt, proven on 26B131 (this Mac), used when Keep other windows warm is on")
    }

    @Test("A record from another build is not used, and the line names this Mac's build")
    func otherBuildIsNotUsed() {
        #expect(MenuMarginLine.text(storedValue: record, build: "26C10", osMajor: 27, radiusQueryExists: true)
            == "Menu margin remembered: 75 pt, proven on 26B131 (this Mac runs 26C10), not used")
        #expect(MenuMarginLine.text(storedValue: record, build: nil, osMajor: 27, radiusQueryExists: true)
            == "Menu margin remembered: 75 pt, proven on 26B131 (this Mac's build is unknown), not used")
    }

    @Test("Before macOS 26 no record is used, even one from this build")
    func olderMacOSIsNotUsed() {
        let old: [String: Any] = ["build": "24G84", "margin": 75.0]
        for build: String? in ["24G84", "24F74", nil] {
            #expect(MenuMarginLine.text(storedValue: old, build: build, osMajor: 15, radiusQueryExists: false)
                == "Menu margin remembered: 75 pt, proven on 24G84, not used before macOS 26")
        }
        #expect(MenuMarginLine.text(storedValue: record, build: "26B131", osMajor: 25, radiusQueryExists: true)
            == "Menu margin remembered: 75 pt, proven on 26B131, not used before macOS 26")
    }

    @Test("No stored value")
    func none() {
        #expect(MenuMarginLine.text(storedValue: nil, build: "26B131", osMajor: 27, radiusQueryExists: true) == "Menu margin remembered: none")
    }

    @Test("A value the app would not have written is unreadable and not used")
    func unreadable() {
        let values: [Any] = [
            "75", 75, ["build": "26B131"], ["margin": 75.0], ["build": "", "margin": 75.0],
            ["build": "26B131", "margin": true], ["build": "26B131", "margin": "75"],
            ["build": "26B131", "margin": 0.0], ["build": "26B131", "margin": -75.0],
            ["build": "26B131", "margin": 129.0], ["build": "26B131", "margin": Double.nan],
            ["build": 26, "margin": 75.0],
        ]
        for value in values {
            #expect(MenuMarginLine.text(storedValue: value, build: "26B131", osMajor: 27, radiusQueryExists: true)
                == "Menu margin remembered: unreadable value, not used", "\(value)")
        }
    }

    @Test("The value as CFPreferences returns it, with whole and fractional margins")
    func preferenceForms() {
        let stored = NSDictionary(dictionary: ["build": "26B131", "margin": NSNumber(value: 75)])
        #expect(MenuMarginLine.text(storedValue: stored, build: "26B131", osMajor: 27, radiusQueryExists: true)
            == "Menu margin remembered: 75 pt, proven on 26B131 (this Mac), used when Keep other windows warm is on")
        #expect(MenuMarginLine.text(storedValue: ["build": "26B131", "margin": 74.5], build: "26B131", osMajor: 27, radiusQueryExists: true)
            == "Menu margin remembered: 74.5 pt, proven on 26B131 (this Mac), used when Keep other windows warm is on")
        #expect(MenuMarginLine.text(storedValue: ["build": "26B131", "margin": 128.0], build: "26B131", osMajor: 27, radiusQueryExists: true)
            == "Menu margin remembered: 128 pt, proven on 26B131 (this Mac), used when Keep other windows warm is on")
    }

    @Test("This Mac's build reads like a macOS build")
    func thisMacBuild() throws {
        let build = try #require(ThisMac.osBuild)
        #expect(build.count >= 5 && build.first!.isNumber, "\(build)")
    }

    @Test("Without the radius query the app neither loads nor stores a margin, so none is used")
    func noRadiusQueryIsNotUsed() {
        // macOS 26 or later where a SkyLight call of the query is missing: the app's
        // WKCopyWindowCornerRadii(nil, 0, nil) is false and the record is never loaded.
        for build: String? in ["26B131", "26C10", nil] {
            #expect(MenuMarginLine.text(storedValue: record, build: build, osMajor: 27, radiusQueryExists: false)
                == "Menu margin remembered: 75 pt, proven on 26B131, not used: this macOS has no window corner query")
        }
        #expect(MenuMarginLine.text(storedValue: nil, build: "26B131", osMajor: 27, radiusQueryExists: false)
            == "Menu margin remembered: none")
    }

    @Test("The query check is false before macOS 26 and true on it, as the app's is")
    func queryCheckFollowsTheOS() {
        // The six SkyLight calls exist on every macOS 26 and 27 release checked (the reporter's
        // 27.2.1 report printed radii). A failure on a newer macOS means the app no longer loads or
        // stores a remembered margin there, and the line says so.
        let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        #expect(CornerRadii.queryExists == (major >= MenuMarginLine.firstMacOS))
    }
}
