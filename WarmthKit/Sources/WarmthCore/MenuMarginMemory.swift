import Foundation
import CoreGraphics

// MARK: - What a window list proves about the menu margin

extension WindowHolePolicy {
    /// What one sample of the window list proves about this Mac's menu margin.
    public enum MenuMarginProof: Equatable, Sendable {
        /// A regular app's menu hangs from the menu bar in `window`, padded by this much on every
        /// side (`observedMenuMargin`). `ambiguous` when the window's part above the display's top
        /// edge lies on another display, where an ordinary window can read the same.
        case padded(CGFloat, window: CGRect, ambiguous: Bool)
        /// A regular app's menu hangs from the menu bar in a window that is the menu itself.
        case unpadded
    }

    /// What `windows` prove about the menu margin, or nil when they prove nothing. A padded menu
    /// wins over an unpadded one in the same list: a padded submenu can start on the menu line, but
    /// then its parent hangs from the menu bar beside it. `titledRadius` is the corner of a titled
    /// window on this Mac and `frontOwner` the frontmost app: see `provesUnpaddedMenus`. Without
    /// them nothing proves the absence of a margin.
    public static func menuMarginProof(
        in windows: [Window],
        displays: [CGRect],
        titledRadius: CGFloat = 0,
        frontOwner: Int32? = nil
    ) -> MenuMarginProof? {
        if let reading = menuMarginReading(in: windows, displays: displays) {
            return .padded(reading.margin, window: reading.window, ambiguous: reading.ambiguous)
        }
        return provesUnpaddedMenus(in: windows, displays: displays, titledRadius: titledRadius,
                                   frontOwner: frontOwner) ? .unpadded : nil
    }

    /// How far below a titled window's corner a menu's corner sits, at least. On macOS 26.6 menus
    /// report 12 pt, titled panels 15 and titled windows 16, at any level.
    static let menuCornerBelowTitled: CGFloat = 1

    /// Whether a listed window proves that this Mac's menus have no margin: a menu window of the
    /// frontmost app (`frontOwner`; nil proves nothing) that starts on the line a menu opens from
    /// under the menu bar, lies wholly on the display, and reports a corner radius more than
    /// `menuCornerBelowTitled` below `titledRadius`. A macOS 26 menu-bar menu is such a window: the
    /// menu bar shows the front app's menus, and its corner is 12 pt against the titled 16. A titled
    /// window or panel an app raised to the menu level and put flush under the menu bar reports the
    /// titled corner (16 pt) or the panel's (15 pt), and another app's window is no menu-bar menu, so
    /// neither proves anything. A padded macOS 27 menu window reports radius 0, so a padded submenu
    /// or context menu that happens to start on that line proves nothing either. Neither do
    /// accessory apps (notch tools, menu-bar extras), this app's measured windows or popovers,
    /// which are not on the menu level.
    static func provesUnpaddedMenus(
        in windows: [Window],
        displays: [CGRect],
        titledRadius: CGFloat,
        frontOwner: Int32?
    ) -> Bool {
        guard let frontOwner, titledRadius.isFinite else { return false }
        let widestMenuCorner = titledRadius - menuCornerBelowTitled
        for display in displays {
            guard let menuBar = menuBar(in: windows, display: display) else { continue }
            let menuTop = menuBar.maxY + menuGapBelowMenuBar
            for window in windows
            where window.layer == popUpMenuLayer && window.isRegularApp && !window.isMeasured
                && window.owner == frontOwner {
                let bounds = window.bounds
                guard window.alpha > 0.01, let radius = window.knownCornerRadius, radius < widestMenuCorner,
                      abs(bounds.minY - menuTop) <= menuAttachSlack else { continue }
                guard bounds.width >= minMenuBody, bounds.height >= minMenuBody,
                      display.contains(bounds) else { continue }
                return true
            }
        }
        return false
    }
}

// MARK: - Remembering the margin across launches (#37)

/// This Mac's menu margin, remembered across launches together with the OS build it was proven on.
///
/// The margin can only be proven from a menu that hangs from the menu bar, and only while an
/// excluded app is in front. Kept in memory alone it was lost at every launch, and until the next
/// such menu every menu window counted at its whole bounds: a neutral box around the excluded app's
/// menus, and a warm box around other apps' menus over its windows.
///
/// The margin is how one macOS build draws menus, so a record from any other build is ignored and
/// the margin starts at zero, as before. There is deliberately no default margin and no guess from
/// the OS version: on a Mac whose menus have no margin, a wrong one cuts the excluded app's menus
/// inside their edges and leaves them warm, which is worse than the box. Only where WindowServer
/// reports corner radii (`persists`, macOS 26 and later) is anything loaded or stored. Elsewhere
/// no radius tells a padded menu from another window at the menu level, and every launch starts
/// at zero, as in 1.1.19.
///
/// The margin is the largest reading, and it only grows. A padded menu hanging from the menu bar
/// reads the whole margin; a submenu, a context menu or a toolbar menu opened near the top starts
/// lower and reads less, however many of them agree. Only a window that is no menu-bar menu reads
/// more, so a larger reading needs a second window to agree once a margin is known. So:
/// - A reading counts only once its window has held still for `stillTime`, measured on the clock
/// `note` is given, however many samples came in between, and with no gap between samples longer
/// than `sampleGap`. A menu stays where it opened. A window
/// that slides in from above the top edge at the menu level reads a different margin at every
/// frame (Ghostty's quick terminal is raised to the menu level for its slide), and so does a
/// window being dragged.
/// - While no margin is known, a clean reading that counts sets it, and it is stored at once: the
/// first menu-bar menu proves it for every launch.
/// - Once one is known, a larger reading raises it only when another window of a different shape
/// has read the same, to within `agreement` (`Reading.isAnotherWindow`), and the new margin is
/// stored at once. Menu-bar menus all read the margin itself, so they need this only after a
/// smaller margin came first.
/// - An ambiguous reading (`WindowHolePolicy.MenuMarginProof`: the window's part above the top edge
/// lies on another display) always needs that second window. A window dragged onto a display
/// stacked below reads like a menu hanging there, and it is one window, however it moves.
/// - Nothing but a proof of no margin lowers it: that sets it to zero, removes the record and
/// forgets the session's readings, so none from before it agrees with one after.
/// - A stored record of this build sets the margin at launch.
///
/// What remains, all of it pinned by tests:
/// - The first reading that counts on a new build is believed alone. If it comes from a still window
/// parked above the top edge at the menu level (a quick terminal stalled mid-slide), that margin
/// is stored, and no menu lowers it. So is a margin that two still windows of different shapes
/// agree on above the true one.
/// - Menus pinned to the top of the screen. A probe of real AppKit menus on macOS 26.7.3 for #37:
/// while the menu bar was listed, no menu started above the menu line (lowest CG minY 34), across
/// 60-item pop-ups with the first, middle and last item selected, 80-item context menus at the
/// top and the bottom of the screen, and a 92-item app menu. With the bar auto-hidden, two menus
/// were clamped to minY 33, but the bar stayed unlisted for as long as they were open, so they
/// give no reading. macOS 27 is unverified. One window reading above the margin raises nothing;
/// two of different shapes agreeing in one session would.
/// - On a new build, menus opened near the top before any menu-bar menu set a smaller margin and
/// store it; raising it then takes two menu-bar menus of different sizes in one session.
/// - On a display stacked below another, such as a laptop below an external monitor, every
/// menu-bar menu is ambiguous: keeping the margin takes two menus of different sizes in one
/// session.
/// - `abendrot debug fullscreen` prints the record, and
/// `defaults delete app.abendrot.Abendrot windowFilterMenuMargin` removes a wrong one.
public struct MenuMarginMemory: Equatable, Sendable {
    /// A proven margin and the OS build it was proven on, as stored.
    public struct Record: Equatable, Sendable {
        public var build: String
        public var margin: CGFloat

        public init(build: String, margin: CGFloat) {
            self.build = build
            self.margin = margin
        }
    }

    /// A change to make to the stored record.
    public enum Write: Equatable, Sendable {
        case save(Record)
        case clear
    }

    /// The key the record is kept under in the app's own defaults. Internal state, not a setting.
    public static let defaultsKey = "windowFilterMenuMargin"

    /// How long a window must read the same margin from the same bounds before the reading counts,
    /// in seconds: as long as Ghostty's quick terminal slide. Measured in time, not samples, so the
    /// extra samples taken when the filter is applied or rebuilt or the Space changes add nothing.
    public static let stillTime: TimeInterval = 0.2
    /// The longest gap between two samples across which a window still counts as watched, in
    /// seconds. Longer, nothing was sampled in between (tracking stopped, panels down), so whether
    /// the window moved is unknown and its stillness starts again. The backend asks for a sample
    /// every 1/60 s, but timer coalescing and the window list's own cost space the ticks further
    /// apart. Measured on a loaded Mac with a window list taken each tick: 22 to 28 Hz, the largest
    /// gaps 77 to 88 ms in most runs (the 75 ms tier-3 coalescing limit plus a tick), and in one run
    /// gaps of 100 to 146 ms. Other apps' menus never run on this thread. Any bound below
    /// `stillTime` still restarts the count across a real pause in sampling, so 0.15 s, which no
    /// measured gap reached.
    static let sampleGap: TimeInterval = 0.15
    /// How far apart two readings may be and still agree, and how far a window's size or side must
    /// move to count as another window's.
    static let agreement: CGFloat = 0.5
    /// How many of this session's readings that counted, one per window size, a new one is compared with.
    static let keptReadings = 16

    /// The OS build this launch runs on. Nil when it cannot be read: nothing is then loaded or stored.
    public let build: String?
    /// Whether the record is loaded and stored. False where WindowServer reports no corner radii
    /// (macOS 25 and earlier): every launch then starts at zero, as in 1.1.19.
    public let persists: Bool
    /// The record as it is stored now. Nil when nothing is stored, or when nothing persists.
    public private(set) var stored: Record?
    /// The margin to cut menu windows with now. Zero when none is proven.
    public private(set) var margin: CGFloat
    /// The latest sample's padded reading, and when it was first seen in this run of samples.
    private var latest: Reading?
    private var latestSince: TimeInterval = 0
    /// When the previous sample was noted, nil before the first.
    private var previousSample: TimeInterval?
    /// This session's readings that counted, clean or ambiguous, one per window size.
    private var readings: [Reading] = []

    /// One padded reading and the window it came from.
    private struct Reading: Equatable, Sendable {
        var margin: CGFloat
        var window: CGRect

        func agrees(with other: CGFloat) -> Bool {
            abs(margin - other) <= MenuMarginMemory.agreement
        }

        /// Whether `other` is another window than this reading's, as far as its bounds can tell:
        /// another size, with neither side where this one's is. One window moved keeps its size;
        /// resized from an edge or a corner, it keeps its top, so its reading, and one side. Two menus
        /// of a menu bar hang under different titles.
        func isAnotherWindow(than other: CGRect) -> Bool {
            let tolerance = MenuMarginMemory.agreement
            let resized = abs(window.width - other.width) > tolerance || abs(window.height - other.height) > tolerance
            return resized && abs(window.minX - other.minX) > tolerance && abs(window.maxX - other.maxX) > tolerance
        }
    }

    public init(stored: Record?, build: String?, persists: Bool = true) {
        self.build = build
        self.persists = persists
        self.stored = persists ? stored : nil
        if persists, let stored, let build, stored.build == build {
            margin = stored.margin
        } else {
            margin = 0
        }
    }

    /// Takes one sample's proof, nil when the sample proves nothing, taken at `time` in seconds on a
    /// clock that only goes forward (the backend's `CACurrentMediaTime()`). Returns the change to
    /// store, or nil when the stored record stays as it is. Called on every sample; a record is
    /// written only when it changes.
    public mutating func note(_ proof: WindowHolePolicy.MenuMarginProof?, at time: TimeInterval) -> Write? {
        let gap = time - (previousSample ?? time)
        previousSample = time
        guard case .padded(let seen, let window, let ambiguous) = proof else {
            latest = nil
            guard proof == .unpadded else { return nil }
            margin = 0
            readings.removeAll()
            guard persists, stored != nil else { return nil }
            stored = nil
            return .clear
        }
        let reading = Reading(margin: seen, window: window)
        if reading != latest || gap > Self.sampleGap {
            latest = reading
            latestSince = time
        }
        guard time - latestSince >= Self.stillTime else { return nil }
        let agreed = readings.contains { $0.agrees(with: seen) && $0.isAnotherWindow(than: window) }
        readings.removeAll { $0.window.size == window.size }
        readings.append(reading)
        if readings.count > Self.keptReadings { readings.removeFirst() }
        guard agreed || (!ambiguous && margin == 0) else { return nil }
        return raise(to: seen)
    }

    /// Raises the margin to a reading that counts, and stores it. A record of this build always holds
    /// `margin`, so a larger margin always differs from the stored record.
    private mutating func raise(to value: CGFloat) -> Write? {
        guard value > margin else { return nil }
        margin = value
        guard persists, let build else { return nil }
        let record = Record(build: build, margin: value)
        stored = record
        return .save(record)
    }
}

extension MenuMarginMemory.Record {
    /// Reads a stored value. Nil for anything this code would not have written: not a dictionary,
    /// no build, or a margin that is not a number above 0 and at most the widest shadow margin.
    public init?(storedValue: Any?) {
        guard let dictionary = storedValue as? [String: Any],
              let build = dictionary["build"] as? String, !build.isEmpty,
              let number = dictionary["margin"] as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let margin = CGFloat(number.doubleValue)
        guard margin.isFinite, margin > 0, margin <= WindowHolePolicy.maxShadowMargin else { return nil }
        self.init(build: build, margin: margin)
    }

    /// The property list kept for this record.
    public var storedValue: [String: Any] {
        ["build": build, "margin": Double(margin)]
    }
}
