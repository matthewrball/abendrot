import Testing
import Foundation
@testable import WarmthCore

// MARK: - sunsetTime across far-flung time zones (regression)

/// Regression coverage for `ScheduleResolver.sunsetTime` returning nil for cities whose solar day
/// falls far outside the user's own time zone (e.g. Tokyo while the Mac is in the US). The fix anchors
/// the 24h scan to the COORDINATE's own approximate local day (15°/hour longitude → time zone), so a
/// far city now resolves and reads as a plausible evening in *its* clock.
///
/// All instants are fixed (deterministic) — built from `DateComponents` in UTC, never `Date.now`.
@Suite("sunsetTime · far time zones")
struct SunsetTimeTests {

    /// A fixed mid-year UTC instant (2026-06-21 12:00 UTC) — well clear of polar day/night at the
    /// mid-latitude cities under test, so each has a real sunset crossing.
    private func midYearUTC() -> Date {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        return utc.date(from: DateComponents(year: 2026, month: 6, day: 21, hour: 12))!
    }

    /// The local hour-of-day of `instant` in the coordinate's *approximate* (longitude-derived) zone —
    /// the same zone the resolver uses internally, so the assertion checks the city's own clock.
    private func localHour(of instant: Date, forLongitude longitude: Double) -> Int {
        let tz = TimeZoneCoordinates.approximateTimeZone(forLongitude: longitude) ?? .current
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal.component(.hour, from: instant)
    }

    @Test("Tokyo (far east of a US user) resolves to a plausible evening in Tokyo's clock")
    func tokyo() {
        // Tokyo: lat 35.68, lon 139.69 → approx UTC+9. Before the fix this returned nil for a
        // US-default `.current` calendar.
        let coordinate = TimeZoneCoordinates.Coordinate(latitude: 35.68, longitude: 139.69)
        let sunset = ScheduleResolver.sunsetTime(forCoordinate: coordinate, on: midYearUTC())
        #expect(sunset != nil)
        if let sunset {
            let hour = localHour(of: sunset, forLongitude: coordinate.longitude)
            #expect(hour >= 17 && hour <= 20)   // plausible early-evening sunset in Tokyo local time
        }
    }

    @Test("Honolulu (far west) resolves to a plausible evening in Honolulu's clock")
    func honolulu() {
        // Honolulu: lat 21.31, lon -157.86 → approx UTC-11 (rounded). Far west of GMT.
        let coordinate = TimeZoneCoordinates.Coordinate(latitude: 21.31, longitude: -157.86)
        let sunset = ScheduleResolver.sunsetTime(forCoordinate: coordinate, on: midYearUTC())
        #expect(sunset != nil)
        if let sunset {
            let hour = localHour(of: sunset, forLongitude: coordinate.longitude)
            #expect(hour >= 17 && hour <= 20)   // plausible evening sunset in Honolulu local time
        }
    }

    @Test("near-prime-meridian city (London) resolves to a non-nil sunset")
    func nearPrimeMeridian() {
        // London: lat 51.51, lon -0.13 → approx UTC+0. Sanity check that the anchor change doesn't
        // regress the easy, near-meridian case.
        let coordinate = TimeZoneCoordinates.Coordinate(latitude: 51.51, longitude: -0.13)
        let sunset = ScheduleResolver.sunsetTime(forCoordinate: coordinate, on: midYearUTC())
        #expect(sunset != nil)
        if let sunset {
            let hour = localHour(of: sunset, forLongitude: coordinate.longitude)
            // London midsummer sunset is late (~21:00 local); allow a generous evening band.
            #expect(hour >= 19 && hour <= 23)
        }
    }
}
