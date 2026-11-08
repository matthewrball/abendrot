import Foundation
import CoreGraphics

// MARK: - Timed pause

/// A temporary suppression of warmth. It does not change the master enable, the schedule, or the
/// warmth curve. `until` is an absolute instant, so sleep does not extend it.
public struct TimedPause: Hashable, Sendable, Codable {
    public enum Kind: String, Codable, Sendable, Hashable {
        case oneHour
        case untilSunrise
    }

    public var until: Date
    public var kind: Kind

    public init(until: Date, kind: Kind) {
        self.until = until
        self.kind = kind
    }
}

// MARK: - PausePolicy

/// Pure rules for temporary pause and for "does this window cover its display?".
///
/// Window-level neutrality is intentionally not here. Gamma, color filters, and hardware gain
/// transform the whole display after compositing. Punching a hole would require either a private
/// inverse backdrop or dropping to the public alpha overlay, which washes blacks. Abendrot does
/// not ask for Screen Recording or Accessibility to chase that mockup.
public enum PausePolicy {

    public static let oneHour: TimeInterval = 3_600

    /// A stored pause further out than this is corrupt, not a request. Discard it.
    public static let maximumLead: TimeInterval = 48 * 3_600

    /// A window is full screen only when it covers the display to within this inset of every edge,
    /// including the top. A zoomed window that starts under the menu bar does not.
    ///
    /// Geometry alone misses native full screen on a notched built-in: the content settles at
    /// `{0, 33, 1512, 949}`, the same frame as a zoomed window, after briefly covering the whole
    /// display during the animation. `fullScreenSpaceDisplayIDs` catches that case from the
    /// desktop-level windows instead.
    public static let fullScreenEdgeInset: CGFloat = 8

    /// The pause to honor at `date`, or nil when it is missing, expired, non-finite, or absurdly far.
    public static func active(_ pause: TimedPause?, at date: Date) -> TimedPause? {
        guard let pause else { return nil }
        let lead = pause.until.timeIntervalSince(date)
        guard lead.isFinite, lead > 0, lead <= maximumLead else { return nil }
        return pause
    }

    public static func oneHour(from date: Date) -> TimedPause {
        TimedPause(until: date.addingTimeInterval(oneHour), kind: .oneHour)
    }

    /// True when `window` contains `display` inset on every side. Both rects share the
    /// CoreGraphics top-left space used by `kCGWindowBounds` and `CGDisplayBounds`.
    public static func coversDisplay(
        window: CGRect,
        display: CGRect,
        edgeInset: CGFloat = fullScreenEdgeInset
    ) -> Bool {
        guard display.width > edgeInset * 2 + 1, display.height > edgeInset * 2 + 1 else { return false }
        guard window.width > 1, window.height > 1 else { return false }
        return window.contains(display.insetBy(dx: edgeInset, dy: edgeInset))
    }

    /// One on-screen window. `layer` 0 is a normal window. List order is front to back, so the first
    /// layer-0 window that intersects a display is the topmost one there. `owner` is the process id.
    public struct ListedWindow: Equatable, Sendable {
        public var bounds: CGRect
        public var layer: Int
        public var owner: Int32
        public init(bounds: CGRect, layer: Int, owner: Int32 = 0) {
            self.bounds = bounds
            self.layer = layer
            self.owner = owner
        }
    }

    public struct ListedDisplay: Equatable, Sendable {
        public var id: CGDirectDisplayID
        public var bounds: CGRect
        public init(id: CGDirectDisplayID, bounds: CGRect) {
            self.id = id
            self.bounds = bounds
        }
    }

    /// A desktop-level window. `desktop` is Finder's desktop, which every normal Space keeps on
    /// each display. `fullScreenBackdrop` is the Dock's backdrop one level above the desktop, which
    /// macOS puts behind a native full-screen Space.
    public struct BackdropWindow: Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            case desktop
            case fullScreenBackdrop
        }

        public var bounds: CGRect
        public var kind: Kind
        public init(bounds: CGRect, kind: Kind) {
            self.bounds = bounds
            self.kind = kind
        }
    }

    /// Displays showing a native full-screen Space. Probed on a notched built-in and on an
    /// external display: once settled, the Dock backdrop covers that display and Finder's desktop
    /// is gone from it. A zoomed window keeps the desktop. During the slide animation the backdrop
    /// is offset and can reach the neighbouring display while its desktop is still listed, so both
    /// conditions are required.
    public static func fullScreenSpaceDisplayIDs(
        backdrops: [BackdropWindow],
        displays: [ListedDisplay]
    ) -> Set<CGDirectDisplayID> {
        var spaces: Set<CGDirectDisplayID> = []
        for display in displays {
            let center = CGPoint(x: display.bounds.midX, y: display.bounds.midY)
            let hasBackdrop = backdrops.contains {
                $0.kind == .fullScreenBackdrop && coversDisplay(window: $0.bounds, display: display.bounds)
            }
            let hasDesktop = backdrops.contains { $0.kind == .desktop && $0.bounds.contains(center) }
            if hasBackdrop && !hasDesktop { spaces.insert(display.id) }
        }
        return spaces
    }

    /// A display is full screen when the owner of its topmost layer-0 window also has a window that
    /// covers it, or when it is showing a native full-screen Space. A toolbar strip listed first
    /// still counts if that same owner covers the display. A small window of another app sitting on
    /// top does not. `mirroring` maps a hardware mirror to the display it copies.
    public static func fullScreenDisplayIDs(
        ownedWindows: [ListedWindow],
        displays: [ListedDisplay],
        mirroring: [CGDirectDisplayID: CGDirectDisplayID] = [:],
        fullScreenSpaces: Set<CGDirectDisplayID> = []
    ) -> Set<CGDirectDisplayID> {
        var covered = fullScreenSpaces
        for display in displays {
            guard let top = ownedWindows.first(where: { window in
                window.layer == 0 && !window.bounds.isEmpty
                    && primaryDisplay(of: window.bounds, among: displays, excluding: Set(mirroring.keys)) == display.id
            }) else { continue }
            let ownerCovers = ownedWindows.contains {
                $0.layer == 0 && $0.owner == top.owner
                    && coversDisplay(window: $0.bounds, display: display.bounds)
            }
            if ownerCovers { covered.insert(display.id) }
        }
        for (mirror, source) in mirroring where covered.contains(source) {
            covered.insert(mirror)
        }
        return covered
    }

    /// The display that owns most of `window`. A window drawn on one display can still report a
    /// few points past the shared edge; that clip must not make it the top window on the next display.
    private static func primaryDisplay(
        of window: CGRect,
        among displays: [ListedDisplay],
        excluding mirrors: Set<CGDirectDisplayID> = []
    ) -> CGDirectDisplayID? {
        var bestID: CGDirectDisplayID?
        var bestArea: CGFloat = 0
        for display in displays where !mirrors.contains(display.id) {
            let hit = window.intersection(display.bounds)
            guard !hit.isNull, !hit.isEmpty else { continue }
            let area = hit.width * hit.height
            if area > bestArea {
                bestArea = area
                bestID = display.id
            }
        }
        return bestID
    }

    /// The next morning when Sunset mode goes neutral: the sun ascending through +6°, or through
    /// −0.833° when that day never reaches +6°. Nil in polar day or polar night.
    public static func nextSunrise(
        at date: Date,
        latitude: Double,
        longitude: Double,
        calendar: Calendar = .current
    ) -> Date? {
        guard latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        if let today = sunriseTime(on: date, latitude: latitude, longitude: longitude, calendar: calendar),
           today > date {
            return today
        }
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: date) else { return nil }
        guard let next = sunriseTime(on: tomorrow, latitude: latitude, longitude: longitude, calendar: calendar),
              next > date else { return nil }
        return next
    }

    /// Ascending crossing on the coordinate's local calendar day. Prefers +6°, when Sunset mode
    /// goes neutral. Near 60°N in winter the sun rises but never reaches +6°, so that day falls
    /// back to the −0.833° horizon rather than reporting no sunrise. Nil in polar day or polar night.
    public static func sunriseTime(
        on date: Date,
        latitude: Double,
        longitude: Double,
        calendar: Calendar = .current
    ) -> Date? {
        ascendingCrossing(
            on: date, latitude: latitude, longitude: longitude,
            elevation: ScheduleResolver.rampStartElevation, calendar: calendar
        ) ?? ascendingCrossing(
            on: date, latitude: latitude, longitude: longitude,
            elevation: ScheduleResolver.rampFullElevation, calendar: calendar
        )
    }

    private static func ascendingCrossing(
        on date: Date,
        latitude: Double,
        longitude: Double,
        elevation: Double,
        calendar: Calendar
    ) -> Date? {
        var calendar = calendar
        if let timeZone = TimeZoneCoordinates.approximateTimeZone(forLongitude: longitude) {
            calendar.timeZone = timeZone
        }
        let start = calendar.startOfDay(for: date)
        for minute in 0..<1_440 {
            let instant = start.addingTimeInterval(Double(minute) * 60)
            let previous = ScheduleResolver.solarElevationDegrees(
                at: instant.addingTimeInterval(-60), latitude: latitude, longitude: longitude)
            let current = ScheduleResolver.solarElevationDegrees(
                at: instant, latitude: latitude, longitude: longitude)
            if previous <= elevation && current > elevation {
                return instant
            }
        }
        return nil
    }
}
