import Foundation

// MARK: - TimeZoneCoordinates

/// Approximate geographic coordinates for the system time zone, used to compute the user's REAL
/// sunrise/sunset for "Sunset" mode **without any location permission** (Abendrot asks for none —
/// that's load-bearing to its positioning).
///
/// Sunset *timing* is driven mostly by longitude (≈4 minutes of clock time per degree) and
/// secondarily by latitude (the seasonal day-length swing). A representative coordinate per IANA
/// zone is far more accurate than the old fixed 20:00 clock — typically within ~15–25 min of the
/// true sunset at mid-latitudes. For zones not in the table we fall back to a longitude derived
/// from the UTC offset (Earth turns 15°/hour) at the equator (latitude 0 → no seasonal swing,
/// sunset ≈ 18:00 local) — never wrong by hemisphere, just less precise. No network, no permission,
/// a few KB of static data. Coordinates are accurate to ~1° (ample for sunset timing).
public enum TimeZoneCoordinates {

    public struct Coordinate: Hashable, Sendable {
        public let latitude: Double
        public let longitude: Double
        public init(latitude: Double, longitude: Double) {
            self.latitude = latitude
            self.longitude = longitude
        }
    }

    /// Best-effort coordinate for an IANA identifier (e.g. `"America/New_York"`), falling back to a
    /// UTC-offset longitude at the equator when the identifier isn't in the table.
    public static func coordinate(forIdentifier identifier: String, secondsFromGMT: Int) -> Coordinate {
        if let known = table[identifier] { return known }
        // Fallback: longitude from the UTC offset (15° per hour = 1° per 240 s); equator latitude.
        let lon = (Double(secondsFromGMT) / 3600.0) * 15.0
        return Coordinate(latitude: 0, longitude: min(180, max(-180, lon)))
    }

    /// An APPROXIMATE time zone for a longitude (Earth turns 15°/hour → 1 hour per 15°), rounded to
    /// the nearest whole hour. Zero permission, zero network — consistent with Abendrot's no-CoreLocation
    /// approach. Used to anchor a coordinate's solar day to *its own* local midnight (so a far-away city's
    /// sunset can be computed/displayed in that city's clock rather than the user's). Returns nil only if
    /// `TimeZone(secondsFromGMT:)` rejects the offset, which it won't for any |longitude| ≤ 180.
    public static func approximateTimeZone(forLongitude longitude: Double) -> TimeZone? {
        TimeZone(secondsFromGMT: Int((longitude / 15.0).rounded()) * 3600)
    }

    /// Convenience for the live engine: the current system zone's coordinate. (Reads `TimeZone`
    /// only — no permission, no IO.)
    public static func current(_ timeZone: TimeZone = .current) -> Coordinate {
        // For the offset FALLBACK (unlisted zones) use the STANDARD-time meridian, not the current
        // offset — otherwise a DST-observing zone's summer offset shifts the estimated longitude
        // ~15°. Table hits ignore this value (they use fixed coords). (Review M2.)
        let standardOffset = timeZone.secondsFromGMT() - Int(timeZone.daylightSavingTimeOffset())
        return coordinate(forIdentifier: timeZone.identifier, secondsFromGMT: standardOffset)
    }

    /// Representative coordinates (≈city level) for common IANA zones, covering the large majority
    /// of users across both hemispheres. Misses use the UTC-offset fallback above.
    static let table: [String: Coordinate] = [
        // ── North America ──────────────────────────────────────────────────────────
        "America/New_York": .init(latitude: 40.71, longitude: -74.01),
        "America/Detroit": .init(latitude: 42.33, longitude: -83.05),
        "America/Toronto": .init(latitude: 43.65, longitude: -79.38),
        "America/Chicago": .init(latitude: 41.85, longitude: -87.65),
        "America/Winnipeg": .init(latitude: 49.90, longitude: -97.14),
        "America/Denver": .init(latitude: 39.74, longitude: -104.98),
        "America/Edmonton": .init(latitude: 53.55, longitude: -113.49),
        "America/Phoenix": .init(latitude: 33.45, longitude: -112.07),
        "America/Los_Angeles": .init(latitude: 34.05, longitude: -118.24),
        "America/Vancouver": .init(latitude: 49.28, longitude: -123.12),
        "America/Tijuana": .init(latitude: 32.53, longitude: -117.02),
        "America/Anchorage": .init(latitude: 61.22, longitude: -149.90),
        "America/Halifax": .init(latitude: 44.65, longitude: -63.57),
        "America/St_Johns": .init(latitude: 47.56, longitude: -52.71),
        "Pacific/Honolulu": .init(latitude: 21.31, longitude: -157.86),
        "America/Mexico_City": .init(latitude: 19.43, longitude: -99.13),

        // ── Central & South America ────────────────────────────────────────────────
        "America/Guatemala": .init(latitude: 14.63, longitude: -90.51),
        "America/Panama": .init(latitude: 8.98, longitude: -79.52),
        "America/Bogota": .init(latitude: 4.71, longitude: -74.07),
        "America/Lima": .init(latitude: -12.05, longitude: -77.04),
        "America/Caracas": .init(latitude: 10.49, longitude: -66.88),
        "America/Santiago": .init(latitude: -33.45, longitude: -70.67),
        "America/Sao_Paulo": .init(latitude: -23.55, longitude: -46.63),
        "America/Argentina/Buenos_Aires": .init(latitude: -34.61, longitude: -58.38),

        // ── Europe ─────────────────────────────────────────────────────────────────
        "Atlantic/Reykjavik": .init(latitude: 64.15, longitude: -21.94),
        "Europe/Dublin": .init(latitude: 53.35, longitude: -6.26),
        "Europe/London": .init(latitude: 51.51, longitude: -0.13),
        "Europe/Lisbon": .init(latitude: 38.72, longitude: -9.14),
        "Europe/Madrid": .init(latitude: 40.42, longitude: -3.70),
        "Europe/Paris": .init(latitude: 48.86, longitude: 2.35),
        "Europe/Brussels": .init(latitude: 50.85, longitude: 4.35),
        "Europe/Amsterdam": .init(latitude: 52.37, longitude: 4.90),
        "Europe/Berlin": .init(latitude: 52.52, longitude: 13.40),
        "Europe/Zurich": .init(latitude: 47.38, longitude: 8.54),
        "Europe/Rome": .init(latitude: 41.90, longitude: 12.50),
        "Europe/Vienna": .init(latitude: 48.21, longitude: 16.37),
        "Europe/Prague": .init(latitude: 50.08, longitude: 14.44),
        "Europe/Budapest": .init(latitude: 47.50, longitude: 19.04),
        "Europe/Belgrade": .init(latitude: 44.79, longitude: 20.45),
        "Europe/Warsaw": .init(latitude: 52.23, longitude: 21.01),
        "Europe/Copenhagen": .init(latitude: 55.68, longitude: 12.57),
        "Europe/Oslo": .init(latitude: 59.91, longitude: 10.75),
        "Europe/Stockholm": .init(latitude: 59.33, longitude: 18.07),
        "Europe/Helsinki": .init(latitude: 60.17, longitude: 24.94),
        "Europe/Athens": .init(latitude: 37.98, longitude: 23.73),
        "Europe/Bucharest": .init(latitude: 44.43, longitude: 26.10),
        "Europe/Kyiv": .init(latitude: 50.45, longitude: 30.52),
        "Europe/Kiev": .init(latitude: 50.45, longitude: 30.52),
        "Europe/Istanbul": .init(latitude: 41.01, longitude: 28.98),
        "Europe/Moscow": .init(latitude: 55.76, longitude: 37.62),

        // ── Africa ─────────────────────────────────────────────────────────────────
        "Africa/Casablanca": .init(latitude: 33.57, longitude: -7.59),
        "Africa/Algiers": .init(latitude: 36.75, longitude: 3.06),
        "Africa/Tunis": .init(latitude: 36.80, longitude: 10.18),
        "Africa/Accra": .init(latitude: 5.60, longitude: -0.19),
        "Africa/Lagos": .init(latitude: 6.52, longitude: 3.38),
        "Africa/Cairo": .init(latitude: 30.04, longitude: 31.24),
        "Africa/Nairobi": .init(latitude: -1.29, longitude: 36.82),
        "Africa/Johannesburg": .init(latitude: -26.20, longitude: 28.04),

        // ── Middle East ────────────────────────────────────────────────────────────
        "Asia/Jerusalem": .init(latitude: 31.78, longitude: 35.22),
        "Asia/Beirut": .init(latitude: 33.89, longitude: 35.50),
        "Asia/Baghdad": .init(latitude: 33.32, longitude: 44.36),
        "Asia/Riyadh": .init(latitude: 24.71, longitude: 46.68),
        "Asia/Qatar": .init(latitude: 25.29, longitude: 51.53),
        "Asia/Dubai": .init(latitude: 25.20, longitude: 55.27),
        "Asia/Tehran": .init(latitude: 35.69, longitude: 51.39),

        // ── Asia ───────────────────────────────────────────────────────────────────
        "Asia/Karachi": .init(latitude: 24.86, longitude: 67.00),
        "Asia/Kolkata": .init(latitude: 22.57, longitude: 88.36),
        "Asia/Colombo": .init(latitude: 6.93, longitude: 79.86),
        "Asia/Kathmandu": .init(latitude: 27.72, longitude: 85.32),
        "Asia/Dhaka": .init(latitude: 23.81, longitude: 90.41),
        "Asia/Yangon": .init(latitude: 16.87, longitude: 96.20),
        "Asia/Bangkok": .init(latitude: 13.76, longitude: 100.50),
        "Asia/Ho_Chi_Minh": .init(latitude: 10.82, longitude: 106.63),
        "Asia/Jakarta": .init(latitude: -6.21, longitude: 106.85),
        "Asia/Kuala_Lumpur": .init(latitude: 3.14, longitude: 101.69),
        "Asia/Singapore": .init(latitude: 1.35, longitude: 103.82),
        "Asia/Manila": .init(latitude: 14.60, longitude: 120.98),
        "Asia/Hong_Kong": .init(latitude: 22.32, longitude: 114.17),
        "Asia/Taipei": .init(latitude: 25.03, longitude: 121.57),
        "Asia/Shanghai": .init(latitude: 31.23, longitude: 121.47),
        "Asia/Seoul": .init(latitude: 37.57, longitude: 126.98),
        "Asia/Tokyo": .init(latitude: 35.68, longitude: 139.69),
        "Asia/Tashkent": .init(latitude: 41.30, longitude: 69.24),
        "Asia/Almaty": .init(latitude: 43.24, longitude: 76.89),
        "Asia/Yekaterinburg": .init(latitude: 56.84, longitude: 60.61),
        "Asia/Novosibirsk": .init(latitude: 55.01, longitude: 82.93),
        "Asia/Vladivostok": .init(latitude: 43.12, longitude: 131.89),

        // ── Oceania ────────────────────────────────────────────────────────────────
        "Australia/Perth": .init(latitude: -31.95, longitude: 115.86),
        "Australia/Darwin": .init(latitude: -12.46, longitude: 130.84),
        "Australia/Adelaide": .init(latitude: -34.93, longitude: 138.60),
        "Australia/Brisbane": .init(latitude: -27.47, longitude: 153.03),
        "Australia/Sydney": .init(latitude: -33.87, longitude: 151.21),
        "Australia/Melbourne": .init(latitude: -37.81, longitude: 144.96),
        "Australia/Hobart": .init(latitude: -42.88, longitude: 147.33),
        "Pacific/Guam": .init(latitude: 13.47, longitude: 144.75),
        "Pacific/Auckland": .init(latitude: -36.85, longitude: 174.76),
        "Pacific/Fiji": .init(latitude: -18.14, longitude: 178.44),
    ]
}
