import Testing
import Foundation
@testable import WarmthCore

// MARK: - Late-night deepening (issue #36)

/// The opt-in second stage of Sunset mode: Day → Evening at the real sunset → Late night by a clock
/// bedtime → released by the real sunrise. Every instant is fixed; nothing reads `Date.now` or the
/// host's time zone.
@Suite("Late-night deepening")
struct LateNightStageTests {

    // MARK: Fixtures

    private struct Place {
        let latitude: Double
        let longitude: Double
        let zone: String

        var calendar: Calendar {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: zone)!
            return calendar
        }

        func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
        }
    }

    private let sanFrancisco = Place(latitude: 37.77, longitude: -122.42, zone: "America/Los_Angeles")
    private let oslo = Place(latitude: 59.91, longitude: 10.75, zone: "Europe/Oslo")
    private let reykjavik = Place(latitude: 64.15, longitude: -21.94, zone: "Atlantic/Reykjavik")
    private let tromso = Place(latitude: 69.65, longitude: 18.96, zone: "Europe/Oslo")

    private let evening = WarmthLevel(strength: 0.7)          // 2412 K on the everyday curve
    private let deep = Kelvin(1200)

    private func mired(_ kelvin: Kelvin) -> Double { 1_000_000.0 / Double(kelvin.value) }
    private var neutralMired: Double { mired(.neutral) }

    private func legacy(_ place: Place, _ date: Date, warmth: WarmthLevel? = nil) -> ScheduleDecision {
        ScheduleResolver.solarRampDecision(
            at: date, latitude: place.latitude, longitude: place.longitude,
            configuredWarmth: warmth ?? evening
        )
    }

    private func staged(
        _ place: Place,
        _ date: Date,
        bedtime: Int = 23 * 60,
        target: Kelvin? = nil,
        warmth: WarmthLevel? = nil,
        warmestPoint: Kelvin = .everydayWarmest,
        calendar: Calendar? = nil
    ) -> ScheduleDecision {
        ScheduleResolver.solarRampDecision(
            at: date, latitude: place.latitude, longitude: place.longitude,
            configuredWarmth: warmth ?? evening,
            warmestPoint: warmestPoint,
            lateNight: LateNightStage(bedtimeMinutes: bedtime, target: target ?? deep),
            calendar: calendar ?? place.calendar
        )
    }

    /// The Kelvin a decision puts on screen, whichever path produced it.
    private func shown(_ decision: ScheduleDecision, warmestPoint: Kelvin = .everydayWarmest) -> Kelvin {
        guard decision.isActiveNow else { return .neutral }
        return decision.kelvin ?? decision.target.kelvin(warmestPoint: warmestPoint)
    }

    // MARK: The three anchors

    @Test("Daytime stays neutral")
    func daytimeIsInactive() {
        let decision = staged(sanFrancisco, sanFrancisco.at(2026, 11, 19, 13))
        #expect(decision == .inactive)
    }

    @Test("Before the bedtime ramp, the evening is exactly today's Sunset decision")
    func eveningMatchesLegacy() {
        // 17:30 → 21:59 covers dusk's tail and the whole evening plateau.
        var date = sanFrancisco.at(2026, 11, 19, 15)
        let end = sanFrancisco.at(2026, 11, 19, 22)
        while date < end {
            #expect(staged(sanFrancisco, date) == legacy(sanFrancisco, date))
            date += 7 * 60
        }
    }

    @Test("Halfway through the ramp the screen is halfway in mired, not Kelvin")
    func midRampIsMiredLinear() {
        let decision = staged(sanFrancisco, sanFrancisco.at(2026, 11, 19, 22, 30))
        let eveningKelvin = evening.kelvin(warmestPoint: .everydayWarmest)
        let expected = 1_000_000.0 / ((mired(eveningKelvin) + mired(deep)) / 2)
        #expect(decision.isActiveNow)
        #expect(abs(Double(decision.kelvin?.value ?? 0) - expected) <= 2)
    }

    @Test("From bedtime through the night the screen holds the late-night Kelvin")
    func plateauHoldsTarget() {
        for (day, hour) in [(19, 23), (20, 0), (20, 2), (20, 5)] {
            let decision = staged(sanFrancisco, sanFrancisco.at(2026, 11, day, hour))
            #expect(decision.kelvin == deep, "at \(day)d \(hour)h")
            #expect(decision.isActiveNow)
        }
    }

    @Test("A bedtime after midnight belongs to the same night")
    func bedtimeWrapsMidnight() {
        let bedtime = 30                                            // 00:30
        #expect(staged(sanFrancisco, sanFrancisco.at(2026, 11, 19, 23, 15), bedtime: bedtime)
                == legacy(sanFrancisco, sanFrancisco.at(2026, 11, 19, 23, 15)))
        let half = staged(sanFrancisco, sanFrancisco.at(2026, 11, 20, 0, 0), bedtime: bedtime)
        let eveningKelvin = evening.kelvin(warmestPoint: .everydayWarmest)
        let expected = 1_000_000.0 / ((mired(eveningKelvin) + mired(deep)) / 2)
        #expect(abs(Double(half.kelvin?.value ?? 0) - expected) <= 2)
        #expect(staged(sanFrancisco, sanFrancisco.at(2026, 11, 20, 1, 0), bedtime: bedtime).kelvin == deep)
    }

    @Test("Sunrise releases the late-night warmth without a step, then the day is neutral")
    func sunriseReleases() {
        // SF sunrise on 2026-11-20 is ≈ 06:55 PST; the dawn band runs to about 07:35.
        var previous = shown(staged(sanFrancisco, sanFrancisco.at(2026, 11, 20, 6, 0)))
        #expect(previous == deep)
        var date = sanFrancisco.at(2026, 11, 20, 6, 1)
        let end = sanFrancisco.at(2026, 11, 20, 8, 30)
        while date <= end {
            let now = shown(staged(sanFrancisco, date))
            #expect(now >= previous, "warmth must only cool through dawn")
            previous = now
            date += 60
        }
        #expect(staged(sanFrancisco, end) == .inactive)
        // Midday reset is invisible: the next evening starts from the evening anchor again.
        #expect(staged(sanFrancisco, sanFrancisco.at(2026, 11, 20, 19)) == legacy(sanFrancisco, sanFrancisco.at(2026, 11, 20, 19)))
    }

    // MARK: Bedtimes the sun beats

    private let stockholm = Place(latitude: 59.33, longitude: 18.07, zone: "Europe/Stockholm")
    private let gentle = WarmthLevel(strength: 0.2)

    /// Sunrise to the minute, so the sun is certainly up a minute later.
    private func sunrise(_ place: Place, _ date: Date) -> Date? {
        ScheduleResolver.nightTimeline(
            containing: date, latitude: place.latitude, longitude: place.longitude,
            configuredWarmth: gentle, warmestPoint: .everydayWarmest, lateNight: nil, calendar: place.calendar
        ).sunrise
    }

    @Test("The sun rising mid-ramp stops the deepening there: daylight only ever cools the screen")
    func sunriseMidRampStopsTheDeepening() throws {
        // Stockholm, 22 June: the ramp to a 4:00 bedtime starts at 3:00 and the sun is up near 3:31.
        let up = try #require(sunrise(stockholm, stockholm.at(2026, 6, 21, 23)))
        #expect(up > stockholm.at(2026, 6, 22, 3, 10) && up < stockholm.at(2026, 6, 22, 3, 50))
        func screen(_ date: Date) -> Kelvin {
            shown(staged(stockholm, date, bedtime: 4 * 60, target: .everydayWarmest, warmth: gentle))
        }
        // The ramp had begun: the screen is already warmer than the evening alone.
        #expect(screen(up) < shown(legacy(stockholm, up, warmth: gentle)))
        var date = up + 60
        var previous = screen(date)
        while date < stockholm.at(2026, 6, 22, 13) {
            date += 60
            let now = screen(date)
            #expect(now >= previous, "warmer at \(date) than a minute before, in daylight")
            previous = now
        }
        #expect(previous == .neutral)
    }

    @Test("A ramp that would begin after sunrise changes nothing that night")
    func rampAfterSunriseIsInert() throws {
        // Reykjavik, 22 June: the sun is up again near 2:55, before the 3:00 ramp to a 4:00 bedtime.
        let up = try #require(sunrise(reykjavik, reykjavik.at(2026, 6, 21, 23, 30)))
        #expect(up < reykjavik.at(2026, 6, 22, 3))
        var date = reykjavik.at(2026, 6, 21, 14)
        while date <= reykjavik.at(2026, 6, 22, 13) {
            let stagedNow = staged(reykjavik, date, bedtime: 4 * 60, target: .everydayWarmest, warmth: gentle)
            #expect(stagedNow == legacy(reykjavik, date, warmth: gentle), "differs at \(date)")
            date += 5 * 60
        }
    }

    // MARK: Continuity (no visible steps, anywhere)

    struct Scenario: Sendable, CustomTestStringConvertible {
        let name: String
        let latitude: Double
        let longitude: Double
        let zone: String
        let start: DateComponents
        let bedtime: Int
        var testDescription: String { name }

        init(_ name: String, _ latitude: Double, _ longitude: Double, _ zone: String, _ year: Int, _ month: Int, _ day: Int, bedtime: Int) {
            self.name = name
            self.latitude = latitude
            self.longitude = longitude
            self.zone = zone
            self.start = DateComponents(year: year, month: month, day: day, hour: 12)
            self.bedtime = bedtime
        }

        static let all: [Scenario] = [
            Scenario("San Francisco, November", 37.77, -122.42, "America/Los_Angeles", 2026, 11, 19, bedtime: 23 * 60),
            Scenario("Oslo, midsummer, bedtime before sunset", 59.91, 10.75, "Europe/Oslo", 2026, 6, 21, bedtime: 22 * 60),
            Scenario("Oslo, midsummer, bedtime at sunrise", 59.91, 10.75, "Europe/Oslo", 2026, 6, 21, bedtime: 4 * 60),
            Scenario("Reykjavik, midwinter, the sun never clears the ramp band", 64.15, -21.94, "Atlantic/Reykjavik", 2026, 12, 21, bedtime: 23 * 60),
            Scenario("Tromsø, polar night", 69.65, 18.96, "Europe/Oslo", 2026, 12, 21, bedtime: 23 * 60),
            Scenario("Tromsø, midnight sun", 69.65, 18.96, "Europe/Oslo", 2026, 6, 21, bedtime: 23 * 60),
            Scenario("Tokyo sun on a Los Angeles clock", 35.68, 139.69, "America/Los_Angeles", 2026, 11, 19, bedtime: 23 * 60),
            Scenario("Quito, equator", -0.18, -78.47, "America/Guayaquil", 2026, 3, 20, bedtime: 20 * 60),
            Scenario("Los Angeles, fall back", 34.05, -118.24, "America/Los_Angeles", 2026, 10, 31, bedtime: 90),
            Scenario("Los Angeles, spring forward", 34.05, -118.24, "America/Los_Angeles", 2026, 3, 7, bedtime: 150),
        ]
    }

    @Test("Two days at one-minute steps never jump", arguments: Scenario.all)
    func neverJumps(_ scenario: Scenario) {
        let name = scenario.name
        let bedtime = scenario.bedtime
        let place = Place(latitude: scenario.latitude, longitude: scenario.longitude, zone: scenario.zone)
        let target = Kelvin.warmestSupported                        // the steepest case: 500 K
        let range = mired(target) - neutralMired
        // Only two things move the screen: the sun, by however far its band moved this minute, and
        // the bedtime ramp, by a sixtieth of the way from the evening to the target. A whole
        // Kelvin is 4 mired at 500 K, so rounding gets 5 mired of slack.
        let eveningOffset = evening.strength * (mired(.everydayWarmest) - neutralMired)
        let rampPerMinute = (range - eveningOffset) / 60
        func sun(_ date: Date) -> Double {
            ScheduleResolver.rampFactor(
                elevation: ScheduleResolver.solarElevationDegrees(
                    at: date, latitude: place.latitude, longitude: place.longitude
                ),
                rampStart: ScheduleResolver.rampStartElevation, rampFull: ScheduleResolver.rampFullElevation
            )
        }
        var date = place.calendar.date(from: scenario.start)!
        var previous = mired(shown(staged(place, date, bedtime: bedtime, target: target)))
        var previousSun = sun(date)
        for _ in 0..<(48 * 60) {
            date += 60
            let now = mired(shown(staged(place, date, bedtime: bedtime, target: target)))
            let sunNow = sun(date)
            let limit = abs(sunNow - previousSun) * range + rampPerMinute + 5
            #expect(abs(now - previous) <= limit, "\(name): step of \(now - previous) mired at \(date)")
            previous = now
            previousSun = sunNow
        }
    }

    // MARK: Awkward nights

    @Test("A bedtime before sunset waits for the sun: the ramp starts at sunset")
    func bedtimeBeforeSunsetWaits() throws {
        // Oslo, 21 June: sunset ≈ 22:44 CEST, bedtime 22:00.
        let noon = oslo.at(2026, 6, 21, 12)
        let sunset = try #require(ScheduleResolver.sunsetTime(
            forCoordinate: .init(latitude: oslo.latitude, longitude: oslo.longitude), on: noon, calendar: oslo.calendar
        ))
        // Through dusk the evening anchor is untouched.
        var date = oslo.at(2026, 6, 21, 20)
        while date < sunset {
            #expect(staged(oslo, date, bedtime: 22 * 60) == legacy(oslo, date))
            date += 5 * 60
        }
        let eveningKelvin = evening.kelvin(warmestPoint: .everydayWarmest)
        let expected = 1_000_000.0 / ((mired(eveningKelvin) + mired(deep)) / 2)
        let half = staged(oslo, sunset + 30 * 60, bedtime: 22 * 60)
        #expect(abs(Double(half.kelvin?.value ?? 0) - expected) <= 12)
        #expect(staged(oslo, sunset + 61 * 60, bedtime: 22 * 60).kelvin == deep)
    }

    @Test("Polar night still deepens at bedtime and eases back around midday")
    func polarNight() {
        #expect(staged(tromso, tromso.at(2026, 12, 21, 20)) == legacy(tromso, tromso.at(2026, 12, 21, 20)))
        #expect(staged(tromso, tromso.at(2026, 12, 22, 2)).kelvin == deep)
        // Mean solar noon at 18.96°E is ≈ 11:44 CET; by then the stage has fully released.
        #expect(staged(tromso, tromso.at(2026, 12, 22, 11, 50)) == legacy(tromso, tromso.at(2026, 12, 22, 11, 50)))
    }

    @Test("Midnight sun: the sun never sets, so there is no late night")
    func midnightSun() {
        var date = tromso.at(2026, 6, 21, 12)
        for _ in 0..<96 {
            #expect(staged(tromso, date) == legacy(tromso, date))
            date += 15 * 60
        }
    }

    @Test("Fall back: the repeated hour never cools the screen")
    func fallBackNeverReverses() {
        // 2026-11-01, Los Angeles: 01:00–02:00 happens twice. Bedtime 01:30 lands in it.
        let losAngeles = Place(latitude: 34.05, longitude: -118.24, zone: "America/Los_Angeles")
        var date = losAngeles.at(2026, 10, 31, 22)
        var previous = shown(staged(losAngeles, date, bedtime: 90))
        for _ in 0..<(7 * 60) {                                     // through 04:00 PST
            date += 60
            let now = shown(staged(losAngeles, date, bedtime: 90))
            #expect(now <= previous, "cooled at \(date)")
            previous = now
        }
        #expect(previous == deep)
    }

    @Test("Spring forward: a bedtime in the missing hour still arrives")
    func springForwardSkippedBedtime() {
        // 2026-03-08, Los Angeles: 02:00–03:00 does not exist. Bedtime 02:30.
        let losAngeles = Place(latitude: 34.05, longitude: -118.24, zone: "America/Los_Angeles")
        #expect(staged(losAngeles, losAngeles.at(2026, 3, 8, 3, 30), bedtime: 150).kelvin == deep)
    }

    // MARK: Composition with the existing settings

    @Test("Evening set to zero: neutral until the ramp, then warm")
    func eveningZero() {
        let off = WarmthLevel.off
        #expect(staged(sanFrancisco, sanFrancisco.at(2026, 11, 19, 19), warmth: off) == .inactive)
        let late = staged(sanFrancisco, sanFrancisco.at(2026, 11, 20, 1), warmth: off)
        #expect(late.isActiveNow)
        #expect(late.kelvin == deep)
    }

    @Test("A late-night target no warmer than the evening changes nothing")
    func coolerTargetIsInert() {
        var date = sanFrancisco.at(2026, 11, 19, 12)
        for _ in 0..<96 {
            #expect(staged(sanFrancisco, date, target: Kelvin(3000)) == legacy(sanFrancisco, date))
            date += 15 * 60
        }
    }

    @Test("Cozy already on: the evening is at the floor, so the stage is inert")
    func cozyIsUntouched() {
        let full = WarmthLevel(strength: 1)
        var date = sanFrancisco.at(2026, 11, 19, 12)
        for _ in 0..<96 {
            let decision = staged(sanFrancisco, date, target: .warmestSupported, warmth: full, warmestPoint: .warmestSupported)
            #expect(decision == legacy(sanFrancisco, date, warmth: full))
            date += 15 * 60
        }
    }

    @Test("The published strength pegs at the slider's end once the screen is warmer than it")
    func targetStrengthPegs() {
        let mid = staged(sanFrancisco, sanFrancisco.at(2026, 11, 19, 22, 10), target: .warmestSupported)
        #expect(mid.target.strength > evening.strength)
        #expect(staged(sanFrancisco, sanFrancisco.at(2026, 11, 20, 1), target: .warmestSupported).target.strength == 1)
    }

    // MARK: Wiring through the engine's entry point

    @Test("Sunset mode with no stage is byte-for-byte the old decision")
    func degradeWithoutStageIsUnchanged() {
        let coordinate = TimeZoneCoordinates.Coordinate(latitude: sanFrancisco.latitude, longitude: sanFrancisco.longitude)
        var date = sanFrancisco.at(2026, 11, 19, 12)
        for _ in 0..<(24 * 4) {
            let decision = ScheduleResolver.resolveWithDegrade(
                mode: .followSystemNightShift, at: date, calendar: sanFrancisco.calendar,
                configuredWarmth: evening, nightShift: nil, privateAPIsEnabled: true,
                fallback: ScheduleResolver.defaultEveningFallback, solarCoordinate: coordinate,
                warmestPoint: .everydayWarmest, lateNight: nil
            )
            #expect(decision == legacy(sanFrancisco, date))
            #expect(decision.kelvin == nil)
            date += 15 * 60
        }
    }

    @Test("Sunset mode passes the stage through; other modes ignore it")
    func degradeRoutesStage() {
        let coordinate = TimeZoneCoordinates.Coordinate(latitude: sanFrancisco.latitude, longitude: sanFrancisco.longitude)
        let stage = LateNightStage(bedtimeMinutes: 23 * 60, target: deep)
        let date = sanFrancisco.at(2026, 11, 20, 1)
        func resolve(_ mode: ScheduleMode, coordinate: TimeZoneCoordinates.Coordinate?) -> ScheduleDecision {
            ScheduleResolver.resolveWithDegrade(
                mode: mode, at: date, calendar: sanFrancisco.calendar,
                configuredWarmth: evening, nightShift: nil, privateAPIsEnabled: true,
                fallback: ScheduleResolver.defaultEveningFallback, solarCoordinate: coordinate,
                warmestPoint: .everydayWarmest, lateNight: stage
            )
        }
        #expect(resolve(.followSystemNightShift, coordinate: coordinate).kelvin == deep)
        #expect(resolve(.followSystemNightShift, coordinate: nil).kelvin == nil)   // fixed-window fallback
        #expect(resolve(.alwaysOn, coordinate: coordinate).kelvin == nil)
        #expect(resolve(.off, coordinate: coordinate) == .inactive)
    }

    @Test("Bedtime minutes are kept inside one day")
    func bedtimeIsNormalized() {
        #expect(LateNightStage(bedtimeMinutes: 1440 + 30, target: deep).bedtimeMinutes == 30)
        #expect(LateNightStage(bedtimeMinutes: -60, target: deep).bedtimeMinutes == 23 * 60)
    }
}
