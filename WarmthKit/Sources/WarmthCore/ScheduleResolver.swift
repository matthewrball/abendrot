import Foundation

// MARK: - Schedule resolution

/// The decision a schedule produces at a given instant: whether warmth should be on, and
/// at what target level if so.
public struct ScheduleDecision: Hashable, Sendable {
    public let isActiveNow: Bool
    public let target: WarmthLevel

    public init(isActiveNow: Bool, target: WarmthLevel) {
        self.isActiveNow = isActiveNow
        self.target = target
    }

    public static let inactive = ScheduleDecision(isActiveNow: false, target: .off)
}

/// Pure resolver for `ScheduleMode`. No clocks of its own — the caller passes the instant
/// and (for `.followSystemNightShift`) the injected follow state, keeping this fully testable.
public enum ScheduleResolver {

    /// Resolve a schedule at a given instant.
    ///
    /// - Parameters:
    /// - mode: the configured schedule mode.
    /// - date: the instant to evaluate.
    /// - calendar: calendar used to read local hour/minute for `.custom` (default `.current`).
    /// - configuredWarmth: the global warmth level to use when a mode is simply "on"
    /// (`.alwaysOn`, `.solar` night, `.followSystemNightShift` active). Defaults to full.
    /// - nightShiftActive: injected Night Shift follow state, used only by
    /// `.followSystemNightShift`. When the private follow is unavailable the engine passes
    /// the already-degraded decision through a `.solar` resolution instead.
    public static func resolve(
        _ mode: ScheduleMode,
        at date: Date,
        calendar: Calendar = .current,
        configuredWarmth: WarmthLevel = WarmthLevel(strength: 1),
        nightShiftActive: Bool = false
    ) -> ScheduleDecision {
        switch mode {
        case .off:
            return .inactive

        case .alwaysOn:
            return ScheduleDecision(isActiveNow: true, target: configuredWarmth)

        case let .custom(schedule):
            let active = isWithinWindow(
                start: schedule.start,
                end: schedule.end,
                at: date,
                calendar: calendar
            )
            return ScheduleDecision(isActiveNow: active, target: active ? schedule.warmest : .off)

        case let .solar(latitude, longitude):
            // Graded sunset-aware envelope: eases warmth in before sunset, full through the night,
            // eases back out at sunrise — using the user's real solar position. (Sunset ramp.)
            return solarRampDecision(
                at: date,
                latitude: latitude,
                longitude: longitude,
                configuredWarmth: configuredWarmth
            )

        case .followSystemNightShift:
            return ScheduleDecision(
                isActiveNow: nightShiftActive,
                target: nightShiftActive ? configuredWarmth : .off
            )
        }
    }

    // MARK: Custom window (midnight wrap-around)

    /// Is `date`'s local minute-of-day inside the `[start, end)` window, treating a window
    /// whose end is earlier than its start as wrapping over midnight (e.g. 22:00 → 06:00)?
    static func isWithinWindow(
        start: DateComponents,
        end: DateComponents,
        at date: Date,
        calendar: Calendar
    ) -> Bool {
        let now = minuteOfDay(of: date, calendar: calendar)
        let s = minuteOfDay(of: start)
        let e = minuteOfDay(of: end)

        if s == e { return false }                 // zero-length window → never active
        if s < e { return now >= s && now < e }    // same-day window
        return now >= s || now < e                 // wraps past midnight
    }

    private static func minuteOfDay(of date: Date, calendar: Calendar) -> Int {
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }

    private static func minuteOfDay(of comps: DateComponents) -> Int {
        ((comps.hour ?? 0) * 60 + (comps.minute ?? 0)) % (24 * 60)
    }

    // MARK: Sunset-aware ramp envelope

    /// Solar elevation (°) at which the pre-sunset ramp BEGINS — warmth starts easing in. The sun is
    /// still above the horizon here (~45–60 min before sunset, latitude/season dependent).
    public static let rampStartElevation = 6.0

    /// Solar elevation (°) at which warmth reaches FULL — the standard −0.833° refraction-corrected
    /// sunset horizon. At and below this (sun has set → all night) warmth is the configured level.
    public static let rampFullElevation = -0.833

    /// Today's sunset (sun crossing the -0.833° refraction horizon, descending) for `coordinate`, in the
    /// given calendar/time zone. Returns nil when the sun doesn't cross that horizon that day (polar day/night).
    /// Scans the day at 1-minute resolution using the same `solarElevationDegrees` model Sunset mode uses.
    public static func sunsetTime(
        forCoordinate coordinate: TimeZoneCoordinates.Coordinate,
        on date: Date,
        calendar: Calendar = .current
    ) -> Date? {
        // Anchor the 24h scan to the COORDINATE's own local day, not the user's. With the caller's
        // default `.current` calendar, a far-timezone city's solar noon lands late in the user-local
        // window and the descending sunset crossing falls past minute 1440 → the loop never finds it
        // → nil (e.g. Tokyo when the Mac is in the US). An approximate longitude-derived time zone
        // (15°/hour, zero permission/network) puts the city's noon near the middle of the window.
        var calendar = calendar
        if let tz = TimeZoneCoordinates.approximateTimeZone(forLongitude: coordinate.longitude) {
            calendar.timeZone = tz
        }
        let startOfDay = calendar.startOfDay(for: date)
        func elevation(_ minute: Int) -> Double {
            solarElevationDegrees(at: startOfDay.addingTimeInterval(Double(minute) * 60),
                                  latitude: coordinate.latitude, longitude: coordinate.longitude)
        }
        let noon = (0..<1440).max(by: { elevation($0) < elevation($1) }) ?? 720
        for minute in noon..<1440 where elevation(minute) <= rampFullElevation {
            return startOfDay.addingTimeInterval(Double(minute) * 60)
        }
        return nil
    }

    /// A graded, sunset-aware decision driven by the sun's real position: warmth eases from 0 (sun
    /// at `rampStart`) up to `configuredWarmth` (sun at/below `rampFull` = sunset → night), and back
    /// down through the same band at sunrise. Makes Sunset mode "dim up to sunset, then full warm
    /// once the sun sets" instead of a hard on/off at a fixed clock time.
    public static func solarRampDecision(
        at date: Date,
        latitude: Double,
        longitude: Double,
        configuredWarmth: WarmthLevel,
        rampStart: Double = rampStartElevation,
        rampFull: Double = rampFullElevation
    ) -> ScheduleDecision {
        let elevation = solarElevationDegrees(at: date, latitude: latitude, longitude: longitude)
        let factor = rampFactor(elevation: elevation, rampStart: rampStart, rampFull: rampFull)
        guard factor > 0 else { return .inactive }
        return ScheduleDecision(
            isActiveNow: true,
            target: WarmthLevel(strength: configuredWarmth.strength * factor)
        )
    }

    /// The 0…1 ramp factor for a solar elevation: 0 at/above `rampStart` (daytime), 1 at/below
    /// `rampFull` (sunset → night), linear between. Robust to a degenerate/inverted window.
    static func rampFactor(elevation: Double, rampStart: Double, rampFull: Double) -> Double {
        guard rampStart > rampFull else { return elevation <= rampFull ? 1 : 0 }
        let t = (rampStart - elevation) / (rampStart - rampFull)
        return min(1, max(0, t))
    }

    // MARK: Solar elevation

    /// Solar elevation angle in degrees above the horizon at `date` (UTC-based), for the
    /// given coordinates. Reimplemented NOAA solar-position approximation.
    static func solarElevationDegrees(at date: Date, latitude: Double, longitude: Double) -> Double {
        let secondsPerDay = 86_400.0

        // Julian day / century from the Unix epoch (1970-01-01 = JD 2440587.5).
        let julianDay = date.timeIntervalSince1970 / secondsPerDay + 2_440_587.5
        let julianCentury = (julianDay - 2_451_545.0) / 36_525.0

        // Geometric mean longitude & anomaly of the sun (degrees).
        let geomMeanLong = normalizeDegrees(280.46646 + julianCentury * (36_000.76983 + julianCentury * 0.0003032))
        let geomMeanAnom = 357.52911 + julianCentury * (35_999.05029 - 0.0001537 * julianCentury)

        // Sun's equation of center.
        let anomRad = degreesToRadians(geomMeanAnom)
        let center = sin(anomRad) * (1.914602 - julianCentury * (0.004817 + 0.000014 * julianCentury))
            + sin(2 * anomRad) * (0.019993 - 0.000101 * julianCentury)
            + sin(3 * anomRad) * 0.000289

        let trueLong = geomMeanLong + center

        // Apparent longitude (corrected for nutation/aberration).
        let omega = 125.04 - 1934.136 * julianCentury
        let appLong = trueLong - 0.00569 - 0.00478 * sin(degreesToRadians(omega))

        // Mean obliquity of the ecliptic, corrected.
        let meanObliquity = 23.0 + (26.0 + (21.448 - julianCentury * (46.815 + julianCentury * (0.00059 - julianCentury * 0.001813))) / 60.0) / 60.0
        let obliquityCorr = meanObliquity + 0.00256 * cos(degreesToRadians(omega))

        // Solar declination.
        let declination = radiansToDegrees(asin(sin(degreesToRadians(obliquityCorr)) * sin(degreesToRadians(appLong))))

        // Equation of time (minutes).
        let varY = pow(tan(degreesToRadians(obliquityCorr / 2)), 2)
        let geomMeanLongRad = degreesToRadians(geomMeanLong)
        let eccentEarthOrbit = 0.016708634 - julianCentury * (0.000042037 + 0.0000001267 * julianCentury)
        let equationOfTime = 4 * radiansToDegrees(
            varY * sin(2 * geomMeanLongRad)
            - 2 * eccentEarthOrbit * sin(anomRad)
            + 4 * eccentEarthOrbit * varY * sin(anomRad) * cos(2 * geomMeanLongRad)
            - 0.5 * varY * varY * sin(4 * geomMeanLongRad)
            - 1.25 * eccentEarthOrbit * eccentEarthOrbit * sin(2 * anomRad)
        )

        // True solar time (minutes) at this longitude, then hour angle (degrees).
        let minutesUTC = utcMinutesOfDay(date)
        let trueSolarTime = (minutesUTC + equationOfTime + 4 * longitude).truncatingRemainder(dividingBy: 1440)
        var hourAngle = trueSolarTime / 4 - 180
        if hourAngle < -180 { hourAngle += 360 }

        // Solar zenith → elevation.
        let latRad = degreesToRadians(latitude)
        let declRad = degreesToRadians(declination)
        let hourRad = degreesToRadians(hourAngle)
        let zenithCos = sin(latRad) * sin(declRad) + cos(latRad) * cos(declRad) * cos(hourRad)
        let zenith = radiansToDegrees(acos(min(1, max(-1, zenithCos))))

        return 90 - zenith
    }

    private static func utcMinutesOfDay(_ date: Date) -> Double {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let comps = cal.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        let h = Double(comps.hour ?? 0)
        let m = Double(comps.minute ?? 0)
        let s = Double(comps.second ?? 0) + Double(comps.nanosecond ?? 0) / 1_000_000_000
        return h * 60 + m + s / 60
    }

    private static func degreesToRadians(_ d: Double) -> Double { d * .pi / 180 }
    private static func radiansToDegrees(_ r: Double) -> Double { r * 180 / .pi }
    private static func normalizeDegrees(_ d: Double) -> Double {
        let m = d.truncatingRemainder(dividingBy: 360)
        return m < 0 ? m + 360 : m
    }
}
