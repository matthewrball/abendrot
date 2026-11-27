import Testing
import CoreGraphics
@testable import abendrot

/// Issue #38: `abendrot debug fullscreen` says, for each menu-level window, whether the app may
/// take it for a padded menu, and prints the WindowServer details that could tell an alert raised
/// to that level from a menu.
@Suite("Menu-level window details in debug fullscreen (#38)")
struct MenuLevelDetailTests {
    private let alert = CGRect(x: 422, y: 180, width: 667, height: 461)

    @Test("A window that reports a radius is never taken for a padded menu")
    func roundedWindowIsNotAMenu() {
        let text = MenuLevelDetail.text(bounds: alert, radius: 16, tags: nil, shadow: nil)
        #expect(text == " padded menu: no (reports a radius)")
    }

    @Test("A window with no radius may be a padded menu, whatever else is known")
    func unknownRadiusMayBeAMenu() {
        for radius: Double? in [nil, 0, .nan] {
            #expect(MenuLevelDetail.text(bounds: alert, radius: radius, tags: nil, shadow: nil)
                == " padded menu: possible")
        }
    }

    @Test("Tags print in hex and the shadow as how far it reaches past each edge")
    func tagsAndShadow() {
        // LuLu's alert stand-in on macOS 26.6: a titled window's shadow box.
        let shadow = CGRect(x: alert.minX - 34, y: alert.minY - 26, width: alert.width + 68, height: alert.height + 68)
        let text = MenuLevelDetail.text(bounds: alert, radius: 0, tags: 0x2001_004c_2002, shadow: shadow)
        #expect(text == " tags 0x2001004c2002 shadow 34/26/34/42 padded menu: possible")
    }

    @Test("A window without a WindowServer shadow says so, and a shadow inside the window prints negative")
    func missingAndInnerShadow() {
        let none = CGRect(x: alert.minX, y: alert.minY, width: 0, height: 0)
        #expect(MenuLevelDetail.text(bounds: alert, radius: nil, tags: 0, shadow: none)
            == " tags 0x0 shadow none padded menu: possible")
        let inner = alert.insetBy(dx: 40, dy: 30)
        #expect(MenuLevelDetail.text(bounds: alert, radius: nil, tags: nil, shadow: inner)
            == " shadow -40/-30/-40/-30 padded menu: possible")
    }
}
