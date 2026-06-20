import Testing
import Foundation
@testable import WarmthCore

// MARK: - Kelvin

@Suite("Kelvin")
struct KelvinTests {
    @Test("clamps to 500...6500")
    func clamps() {
        #expect(Kelvin(100).value == 500)     // below the floor → clamped to 500
        #expect(Kelvin(500).value == 500)
        #expect(Kelvin(1000).value == 1000)
        #expect(Kelvin(3000).value == 3000)
        #expect(Kelvin(6500).value == 6500)
        #expect(Kelvin(10_000).value == 6500)
    }

    @Test("neutral is 6500K")
    func neutral() {
        #expect(Kelvin.neutral.value == 6500)
    }

    @Test("is comparable by value")
    func comparable() {
        #expect(Kelvin(2700) < Kelvin(6500))
        #expect(!(Kelvin(6500) < Kelvin(2700)))
    }
}

// MARK: - WarmthLevel

@Suite("WarmthLevel")
struct WarmthLevelTests {
    @Test("strength clamps to 0...1")
    func clamps() {
        #expect(WarmthLevel(strength: -1).strength == 0)
        #expect(WarmthLevel(strength: 0.5).strength == 0.5)
        #expect(WarmthLevel(strength: 2).strength == 1)
    }

    @Test("0 → neutral, 1 → warmestPoint")
    func endpoints() {
        let warmest = Kelvin(2700)
        #expect(WarmthLevel(strength: 0).kelvin(warmestPoint: warmest) == Kelvin.neutral)
        #expect(WarmthLevel(strength: 1).kelvin(warmestPoint: warmest) == warmest)
    }

    @Test("monotonic (more strength → lower or equal Kelvin)")
    func monotonic() {
        let warmest = Kelvin(2700)
        var previous = WarmthLevel(strength: 0).kelvin(warmestPoint: warmest)
        for step in 1...10 {
            let current = WarmthLevel(strength: Double(step) / 10).kelvin(warmestPoint: warmest)
            #expect(current <= previous)
            previous = current
        }
    }

    @Test("midpoint sits strictly between endpoints")
    func midpoint() {
        let warmest = Kelvin(2700)
        let mid = WarmthLevel(strength: 0.5).kelvin(warmestPoint: warmest)
        #expect(mid < Kelvin.neutral)
        #expect(mid > warmest)
    }

    @Test("strength 0 lands on the neutral constant (6500K); strength 1 is the warmest point exactly")
    func endpointsHitNeutralConstant() {
        let warmest = Kelvin(3000)
        #expect(WarmthLevel(strength: 0).kelvin(warmestPoint: warmest).value == Kelvin.neutral.value)
        #expect(WarmthLevel(strength: 0).kelvin(warmestPoint: warmest).value == 6500)
        #expect(WarmthLevel(strength: 1).kelvin(warmestPoint: warmest) == warmest)
    }

    @Test("Kelvin is monotonically non-increasing across sampled strengths 0→1")
    func monotonicAcrossSamples() {
        let warmest = Kelvin(1900)
        var previous = WarmthLevel(strength: 0).kelvin(warmestPoint: warmest)
        for strength in stride(from: 0.0, through: 1.0, by: 0.125) {
            let current = WarmthLevel(strength: strength).kelvin(warmestPoint: warmest)
            #expect(current <= previous)
            previous = current
        }
    }
}

// MARK: - Gain math

@Suite("Kelvin → RGB gain")
struct GainTests {
    @Test("6500K is ~identity (1,1,1)")
    func neutralIsIdentity() {
        let gain = rgbGain(for: Kelvin(6500))
        #expect(abs(gain.red - 1) < 0.02)
        #expect(abs(gain.green - 1) < 0.02)
        #expect(abs(gain.blue - 1) < 0.02)
    }

    @Test("2700K reduces blue below green below red")
    func warmOrdering() {
        let gain = rgbGain(for: Kelvin(2700))
        #expect(gain.blue < gain.green)
        #expect(gain.green < gain.red)
    }

    @Test("all channels stay within 0...1 across the range")
    func clampedRange() {
        for k in stride(from: 1000, through: 6500, by: 250) {
            let gain = rgbGain(for: Kelvin(k))
            #expect(gain.red >= 0 && gain.red <= 1)
            #expect(gain.green >= 0 && gain.green <= 1)
            #expect(gain.blue >= 0 && gain.blue <= 1)
        }
    }

    @Test("warmer reduces blue monotonically")
    func warmerDimsBlue() {
        let cool = rgbGain(for: Kelvin(6500))
        let warm = rgbGain(for: Kelvin(2700))
        #expect(warm.blue < cool.blue)
    }
}

// MARK: - Schedule resolver

@Suite("ScheduleResolver")
struct ScheduleResolverTests {
    private func date(hour: Int, minute: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 6
        comps.day = 16
        comps.hour = hour
        comps.minute = minute
        return Calendar.current.date(from: comps)!
    }

    @Test(".alwaysOn is constant active")
    func alwaysOn() {
        let d = ScheduleResolver.resolve(.alwaysOn, at: date(hour: 3), configuredWarmth: WarmthLevel(strength: 1))
        #expect(d.isActiveNow)
        #expect(d.target.strength == 1)
    }

    @Test(".off is constant inactive")
    func off() {
        let d = ScheduleResolver.resolve(.off, at: date(hour: 22))
        #expect(!d.isActiveNow)
        #expect(d.target == .off)
    }

    @Test(".custom active inside a midnight-wrapping window")
    func customWrapInside() {
        // Window 22:00 → 06:00 wraps midnight.
        let schedule = CustomSchedule(
            start: DateComponents(hour: 22, minute: 0),
            end: DateComponents(hour: 6, minute: 0),
            warmest: WarmthLevel(strength: 0.8)
        )
        // 23:00 and 02:00 are inside; 12:00 is outside.
        #expect(ScheduleResolver.resolve(.custom(schedule), at: date(hour: 23)).isActiveNow)
        #expect(ScheduleResolver.resolve(.custom(schedule), at: date(hour: 2)).isActiveNow)
        #expect(!ScheduleResolver.resolve(.custom(schedule), at: date(hour: 12)).isActiveNow)
    }

    @Test(".custom carries the configured warmest level when active")
    func customTarget() {
        let schedule = CustomSchedule(
            start: DateComponents(hour: 22, minute: 0),
            end: DateComponents(hour: 6, minute: 0),
            warmest: WarmthLevel(strength: 0.8)
        )
        let active = ScheduleResolver.resolve(.custom(schedule), at: date(hour: 23))
        #expect(active.target.strength == 0.8)
        let inactive = ScheduleResolver.resolve(.custom(schedule), at: date(hour: 12))
        #expect(inactive.target == .off)
    }

    @Test(".custom same-day window")
    func customSameDay() {
        // 09:00 → 17:00 does NOT wrap.
        let schedule = CustomSchedule(
            start: DateComponents(hour: 9, minute: 0),
            end: DateComponents(hour: 17, minute: 0),
            warmest: WarmthLevel(strength: 0.5)
        )
        #expect(ScheduleResolver.resolve(.custom(schedule), at: date(hour: 12)).isActiveNow)
        #expect(!ScheduleResolver.resolve(.custom(schedule), at: date(hour: 20)).isActiveNow)
        #expect(!ScheduleResolver.resolve(.custom(schedule), at: date(hour: 3)).isActiveNow)
    }

    @Test(".followSystemNightShift defers to injected state")
    func followNightShift() {
        let on = ScheduleResolver.resolve(.followSystemNightShift, at: date(hour: 22), nightShiftActive: true)
        #expect(on.isActiveNow)
        let offState = ScheduleResolver.resolve(.followSystemNightShift, at: date(hour: 22), nightShiftActive: false)
        #expect(!offState.isActiveNow)
    }

    @Test(".solar daytime vs night sanity (London midsummer)")
    func solarDayNight() {
        // London ~51.5N, 0.13W on the longest day: local noon is daytime, deep night is not.
        // Build UTC instants to make the solar calc deterministic regardless of host TZ.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        func utc(hour: Int) -> Date {
            cal.date(from: DateComponents(year: 2026, month: 6, day: 21, hour: hour))!
        }
        let lat = 51.5
        let lon = -0.13
        // 12:00 UTC ≈ local solar noon in London in summer → daytime → warmth inactive.
        let noon = ScheduleResolver.resolve(.solar(latitude: lat, longitude: lon), at: utc(hour: 12))
        #expect(!noon.isActiveNow)
        // 01:00 UTC → deep night → warmth active.
        let night = ScheduleResolver.resolve(.solar(latitude: lat, longitude: lon), at: utc(hour: 1))
        #expect(night.isActiveNow)
    }

    @Test("solar elevation is higher at noon than at midnight")
    func solarElevationOrdering() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let noon = cal.date(from: DateComponents(year: 2026, month: 6, day: 21, hour: 12))!
        let midnight = cal.date(from: DateComponents(year: 2026, month: 6, day: 21, hour: 0))!
        let noonElev = ScheduleResolver.solarElevationDegrees(at: noon, latitude: 51.5, longitude: -0.13)
        let midnightElev = ScheduleResolver.solarElevationDegrees(at: midnight, latitude: 51.5, longitude: -0.13)
        #expect(noonElev > midnightElev)
        #expect(noonElev > 0)
        #expect(midnightElev < 0)
    }

    // MARK: Sunset ramp + timezone coordinates

    @Test("rampFactor: 0 above ramp start, 1 below sunset, warmer toward sunset between")
    func rampFactorEnvelope() {
        let start = ScheduleResolver.rampStartElevation   // +6°
        let full = ScheduleResolver.rampFullElevation     // −0.833°
        #expect(ScheduleResolver.rampFactor(elevation: start + 5, rampStart: start, rampFull: full) == 0)
        #expect(ScheduleResolver.rampFactor(elevation: start, rampStart: start, rampFull: full) == 0)
        #expect(ScheduleResolver.rampFactor(elevation: full, rampStart: start, rampFull: full) == 1)
        #expect(ScheduleResolver.rampFactor(elevation: full - 10, rampStart: start, rampFull: full) == 1)
        let mid = ScheduleResolver.rampFactor(elevation: (start + full) / 2, rampStart: start, rampFull: full)
        #expect(mid > 0 && mid < 1)
        // Lower elevation = closer to/past sunset = warmer.
        let lower = ScheduleResolver.rampFactor(elevation: 1, rampStart: start, rampFull: full)
        let higher = ScheduleResolver.rampFactor(elevation: 4, rampStart: start, rampFull: full)
        #expect(lower > higher)
    }

    @Test("solarRampDecision: off in daytime, full at night")
    func solarRamp() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        func utc(_ h: Int) -> Date {
            cal.date(from: DateComponents(year: 2026, month: 6, day: 21, hour: h))!
        }
        let lat = 51.5, lon = -0.13   // London
        let warmth = WarmthLevel(strength: 0.8)
        let noon = ScheduleResolver.solarRampDecision(at: utc(12), latitude: lat, longitude: lon, configuredWarmth: warmth)
        #expect(!noon.isActiveNow)
        #expect(noon.target == .off)
        let night = ScheduleResolver.solarRampDecision(at: utc(1), latitude: lat, longitude: lon, configuredWarmth: warmth)
        #expect(night.isActiveNow)
        #expect(night.target == warmth)               // deep night → full configured warmth (factor 1)
    }

    @Test("sunsetTime finds evening sunset and returns nil for polar day")
    func sunsetTime() {
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let summerDate = losAngeles.date(from: DateComponents(year: 2026, month: 6, day: 21, hour: 12))!
        let sunset = ScheduleResolver.sunsetTime(
            forCoordinate: .init(latitude: 34.05, longitude: -118.24),
            on: summerDate,
            calendar: losAngeles
        )
        #expect(sunset != nil)
        if let sunset {
            let hour = losAngeles.component(.hour, from: sunset)
            #expect(hour >= 19 && hour <= 21)
        }

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let polarDate = utc.date(from: DateComponents(year: 2026, month: 6, day: 21, hour: 12))!
        #expect(ScheduleResolver.sunsetTime(
            forCoordinate: .init(latitude: 80, longitude: 0),
            on: polarDate,
            calendar: utc
        ) == nil)
    }

    @Test("TimeZoneCoordinates: known identifier hits the table; unknown uses the UTC-offset longitude")
    func timeZoneCoordinates() {
        let ny = TimeZoneCoordinates.coordinate(forIdentifier: "America/New_York", secondsFromGMT: -5 * 3600)
        #expect(abs(ny.latitude - 40.71) < 0.5)
        #expect(abs(ny.longitude - (-74.01)) < 0.5)
        // Unknown identifier → longitude from the offset (UTC+1 = 15°E), equator latitude.
        let unknown = TimeZoneCoordinates.coordinate(forIdentifier: "Etc/Nowhere", secondsFromGMT: 3600)
        #expect(unknown.latitude == 0)
        #expect(abs(unknown.longitude - 15) < 0.001)
    }

    // MARK: isWithinWindow boundary + degenerate cases

    @Test("isWithinWindow: midnight-wrapping window (22:00→06:00) is active at the edges, off midday")
    func windowMidnightWrapEdges() {
        let start = DateComponents(hour: 22, minute: 0)
        let end = DateComponents(hour: 6, minute: 0)
        // 23:59 (just before midnight) and 00:01 (just after) are inside the wrap.
        #expect(ScheduleResolver.isWithinWindow(start: start, end: end, at: date(hour: 23, minute: 59), calendar: .current))
        #expect(ScheduleResolver.isWithinWindow(start: start, end: end, at: date(hour: 0, minute: 1), calendar: .current))
        // Midday is firmly outside.
        #expect(!ScheduleResolver.isWithinWindow(start: start, end: end, at: date(hour: 12, minute: 0), calendar: .current))
    }

    @Test("isWithinWindow: a zero-length window (start == end) is never active")
    func windowZeroLength() {
        let same = DateComponents(hour: 22, minute: 0)
        #expect(!ScheduleResolver.isWithinWindow(start: same, end: same, at: date(hour: 22, minute: 0), calendar: .current))
        #expect(!ScheduleResolver.isWithinWindow(start: same, end: same, at: date(hour: 12, minute: 0), calendar: .current))
    }

    @Test("sunsetTime: returns nil (no crash) for a polar latitude with no sunset")
    func sunsetTimePolarNil() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        // 80°N at the June solstice: the sun never sets → no -0.833° crossing → nil.
        let polarSummer = utc.date(from: DateComponents(year: 2026, month: 6, day: 21, hour: 12))!
        #expect(ScheduleResolver.sunsetTime(
            forCoordinate: .init(latitude: 80, longitude: 0),
            on: polarSummer,
            calendar: utc
        ) == nil)
    }
}

// MARK: - DisplayMethod & DisplayIdentity

@Suite("DisplayMethod")
struct DisplayMethodTests {
    @Test("badge strings")
    func badges() {
        #expect(DisplayMethod.hardware.badge == "Hardware")
        #expect(DisplayMethod.gamma.badge == "Gamma")
        #expect(DisplayMethod.overlay.badge == "Overlay")
        #expect(DisplayMethod.off.badge == "Off")
    }
}

@Suite("DisplayIdentity")
struct DisplayIdentityTests {
    @Test("equality ignores transient currentDisplayID and frame")
    func equalityIgnoresTransient() {
        let uuid = UUID()
        let edid = EDIDFingerprint(vendorID: 1, productID: 2, serial: nil, displayName: "Studio")
        let a = DisplayIdentity(
            cgUUID: uuid, edid: edid, transport: .thunderbolt, ioRegistryPath: "/a",
            currentDisplayID: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 100), backingScale: 2
        )
        let b = DisplayIdentity(
            cgUUID: uuid, edid: edid, transport: .thunderbolt, ioRegistryPath: "/a",
            currentDisplayID: 99, frame: CGRect(x: 5, y: 5, width: 200, height: 200), backingScale: 1
        )
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }

    @Test("different cgUUID → not equal")
    func differentUUID() {
        let a = DisplayIdentity(cgUUID: UUID())
        let b = DisplayIdentity(cgUUID: UUID())
        #expect(a != b)
    }

    @Test("different edid disambiguates twin monitors")
    func twinDisambiguation() {
        let uuid = UUID()
        let a = DisplayIdentity(cgUUID: uuid, edid: EDIDFingerprint(vendorID: 1, productID: 2, serial: 100))
        let b = DisplayIdentity(cgUUID: uuid, edid: EDIDFingerprint(vendorID: 1, productID: 2, serial: 200))
        #expect(a != b)
    }
}
