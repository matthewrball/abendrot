import Testing
import Foundation
@testable import WarmthCore

// MARK: - Configurable ease before bedtime (issue #36)

/// The ease that ends at bedtime has a per-user length. Every rule the fixed hour obeyed must hold
/// for each allowed length: it ends at bedtime, never starts before sunset, and stops at sunrise.
@Suite("Late-night ease length")
struct LateNightEaseTests {

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

    struct Ease: Sendable, CustomTestStringConvertible {
        let minutes: Int
        var testDescription: String { "\(minutes) min" }
        var seconds: TimeInterval { Double(minutes) * 60 }
        /// The lengths the task pins: shortest, default, longest.
        static let pinned = [Ease(minutes: 15), Ease(minutes: 60), Ease(minutes: 120)]
        static let all = LateNightStage.allowedEaseMinutes.map(Ease.init(minutes:))
    }

    private let sanFrancisco = Place(latitude: 37.77, longitude: -122.42, zone: "America/Los_Angeles")
    private let oslo = Place(latitude: 59.91, longitude: 10.75, zone: "Europe/Oslo")
    private let stockholm = Place(latitude: 59.33, longitude: 18.07, zone: "Europe/Stockholm")
    private let reykjavik = Place(latitude: 64.15, longitude: -21.94, zone: "Atlantic/Reykjavik")

    private let evening = WarmthLevel(strength: 0.7)
    private let gentle = WarmthLevel(strength: 0.2)
    private let deep = Kelvin(1200)

    private func mired(_ kelvin: Kelvin) -> Double { 1_000_000.0 / Double(kelvin.value) }

    private func legacy(_ place: Place, _ date: Date, warmth: WarmthLevel? = nil) -> ScheduleDecision {
        ScheduleResolver.solarRampDecision(
            at: date, latitude: place.latitude, longitude: place.longitude,
            configuredWarmth: warmth ?? evening
        )
    }

    private func staged(
        _ place: Place, _ date: Date, bedtime: Int = 23 * 60, ease: Int,
        target: Kelvin? = nil, warmth: WarmthLevel? = nil
    ) -> ScheduleDecision {
        ScheduleResolver.solarRampDecision(
            at: date, latitude: place.latitude, longitude: place.longitude,
            configuredWarmth: warmth ?? evening,
            warmestPoint: .everydayWarmest,
            lateNight: LateNightStage(bedtimeMinutes: bedtime, target: target ?? deep, easeMinutes: ease),
            calendar: place.calendar
        )
    }

    private func shown(_ decision: ScheduleDecision) -> Kelvin {
        guard decision.isActiveNow else { return .neutral }
        return decision.kelvin ?? decision.target.kelvin(warmestPoint: .everydayWarmest)
    }

    private func timeline(_ place: Place, _ date: Date, bedtime: Int, ease: Int?, warmth: WarmthLevel? = nil) -> NightTimeline {
        ScheduleResolver.nightTimeline(
            containing: date, latitude: place.latitude, longitude: place.longitude,
            configuredWarmth: warmth ?? evening, warmestPoint: .everydayWarmest,
            lateNight: ease.map { LateNightStage(bedtimeMinutes: bedtime, target: deep, easeMinutes: $0) }
                ?? LateNightStage(bedtimeMinutes: bedtime, target: deep),
            calendar: place.calendar
        )
    }

    // MARK: The setting itself

    @Test("The allowed lengths are 15, 30, 45, 60, 90 and 120 minutes, and the default is 60")
    func allowedSet() {
        #expect(LateNightStage.allowedEaseMinutes == [15, 30, 45, 60, 90, 120])
        #expect(LateNightStage.defaultEaseMinutes == 60)
        #expect(LateNightStage.allowedEaseMinutes.contains(LateNightStage.defaultEaseMinutes))
    }

    @Test("A stage built without a length uses the default hour")
    func unsetIsDefault() {
        let stage = LateNightStage(bedtimeMinutes: 23 * 60, target: deep)
        #expect(stage.easeMinutes == 60)
        #expect(stage.rampDuration == 3600)
        #expect(stage == LateNightStage(bedtimeMinutes: 23 * 60, target: deep, easeMinutes: 60))
    }

    @Test("An unset length resolves to the fixed hour's own numbers")
    func unsetMatchesTheFixedHour() {
        // Literal values, worked by hand from the fixed-hour rule: 2412 K evening (0.7 on the
        // everyday curve), 1200 K at bedtime, linear in mired over the hour before 23:00.
        // mired(2412) = 414.59, mired(1200) = 833.33
        // 22:15 → 519.28 → 1926 K 22:30 → 623.96 → 1603 K 22:45 → 728.65 → 1372 K
        let unset = LateNightStage(bedtimeMinutes: 23 * 60, target: deep)
        func unsetAt(_ day: Int, _ hour: Int, _ minute: Int) -> ScheduleDecision {
            ScheduleResolver.solarRampDecision(
                at: sanFrancisco.at(2026, 11, day, hour, minute),
                latitude: sanFrancisco.latitude, longitude: sanFrancisco.longitude,
                configuredWarmth: evening, warmestPoint: .everydayWarmest,
                lateNight: unset, calendar: sanFrancisco.calendar
            )
        }
        let pinned: [(day: Int, hour: Int, minute: Int, kelvin: Int)] = [
            (19, 13, 0, 6500),    // day
            (19, 20, 0, 2412),    // evening
            (19, 22, 0, 2412),    // the ease starts here
            (19, 22, 15, 1926),
            (19, 22, 30, 1603),
            (19, 22, 45, 1372),
            (19, 23, 0, 1200),    // bedtime
            (20, 3, 0, 1200),     // held
            (20, 10, 0, 6500),    // day again
        ]
        for point in pinned {
            let kelvin = shown(unsetAt(point.day, point.hour, point.minute)).value
            #expect(abs(kelvin - point.kelvin) <= 1, "\(point.hour):\(point.minute) was \(kelvin) K")
        }
        // Before the ease the stage hands back the plain evening decision, untouched.
        #expect(unsetAt(19, 22, 0).kelvin == nil)
        #expect(unsetAt(19, 22, 0).target == evening)
    }

    @Test("A length outside the allowed set snaps to the nearest allowed one")
    func nearestAllowed() {
        #expect(LateNightStage.nearestEaseMinutes(to: 60) == 60)
        #expect(LateNightStage.nearestEaseMinutes(to: 0) == 15)
        #expect(LateNightStage.nearestEaseMinutes(to: -5) == 15)
        #expect(LateNightStage.nearestEaseMinutes(to: 20) == 15)
        #expect(LateNightStage.nearestEaseMinutes(to: 70) == 60)
        #expect(LateNightStage.nearestEaseMinutes(to: 100) == 90)
        #expect(LateNightStage.nearestEaseMinutes(to: 10_000) == 120)
        // A corrupt preference: `defaults write … -float -1e30` reads back as Int.min.
        #expect(LateNightStage.nearestEaseMinutes(to: .min) == 15)
        #expect(LateNightStage.nearestEaseMinutes(to: .max) == 120)
        #expect(LateNightStage.nearestEaseMinutes(to: .min + 1) == 15)
        #expect(LateNightStage.nearestEaseMinutes(to: .max - 1) == 120)
        #expect(LateNightStage.easeMinutes(stepping: .min, by: 1) == 30)
        #expect(LateNightStage.easeMinutes(stepping: .max, by: -1) == 90)
        #expect(LateNightStage.easeMinutes(stepping: 60, by: .max) == 120)
        #expect(LateNightStage.easeMinutes(stepping: 60, by: .min) == 15)
        for minutes in LateNightStage.allowedEaseMinutes {
            #expect(LateNightStage.nearestEaseMinutes(to: minutes) == minutes)
        }
    }

    @Test("Stepping walks the allowed lengths and stops at either end")
    func stepping() {
        #expect(LateNightStage.easeMinutes(stepping: 60, by: 1) == 90)
        #expect(LateNightStage.easeMinutes(stepping: 60, by: -1) == 45)
        #expect(LateNightStage.easeMinutes(stepping: 15, by: -1) == 15)
        #expect(LateNightStage.easeMinutes(stepping: 120, by: 1) == 120)
        #expect(LateNightStage.easeMinutes(stepping: 15, by: 99) == 120)
        // A stored value off the set steps from its nearest allowed neighbour.
        #expect(LateNightStage.easeMinutes(stepping: 70, by: 1) == 90)
        var walk = [15]
        while let last = walk.last, LateNightStage.easeMinutes(stepping: last, by: 1) != last {
            walk.append(LateNightStage.easeMinutes(stepping: last, by: 1))
        }
        #expect(walk == LateNightStage.allowedEaseMinutes)
    }

    @Test("Lengths read as short labels, and in full for VoiceOver")
    func labels() {
        #expect(LateNightStage.allowedEaseMinutes.map(LateNightStage.easeText(minutes:))
                == ["15 min", "30 min", "45 min", "1 hr", "1 hr 30 min", "2 hr"])
        #expect(LateNightStage.allowedEaseMinutes.map(LateNightStage.easeSpokenText(minutes:))
                == ["15 minutes", "30 minutes", "45 minutes", "1 hour", "1 hour 30 minutes", "2 hours"])
    }

    @Test("A stage never has a zero or negative ease")
    func stageKeepsEasePositive() {
        #expect(LateNightStage(bedtimeMinutes: 0, target: deep, easeMinutes: 0).easeMinutes >= 1)
        #expect(LateNightStage(bedtimeMinutes: 0, target: deep, easeMinutes: -30).easeMinutes >= 1)
    }

    @Test("The shared bedtime rules: 8 PM through 4 AM in half-hour steps")
    func bedtimeRules() {
        #expect(LateNightStage.bedtimeRange == 20 * 60...28 * 60)
        #expect(LateNightStage.bedtimeStep == 30)
        #expect(LateNightStage.isAllowedBedtime(minutesOfDay: 20 * 60))
        #expect(LateNightStage.isAllowedBedtime(minutesOfDay: 23 * 60 + 30))
        #expect(LateNightStage.isAllowedBedtime(minutesOfDay: 0))
        #expect(LateNightStage.isAllowedBedtime(minutesOfDay: 4 * 60))
        #expect(!LateNightStage.isAllowedBedtime(minutesOfDay: 4 * 60 + 30))
        #expect(!LateNightStage.isAllowedBedtime(minutesOfDay: 19 * 60 + 30))
        #expect(!LateNightStage.isAllowedBedtime(minutesOfDay: 12 * 60))
        #expect(!LateNightStage.isAllowedBedtime(minutesOfDay: 23 * 60 + 15))
        #expect(!LateNightStage.isAllowedBedtime(minutesOfDay: -30))
        #expect(!LateNightStage.isAllowedBedtime(minutesOfDay: 1440))
    }

    // MARK: The ease ends at bedtime

    @Test("The ease starts its own length before bedtime and reaches the target at bedtime", arguments: Ease.all)
    func easeEndsAtBedtime(_ ease: Ease) {
        let bedtime = sanFrancisco.at(2026, 11, 19, 23)
        let start = bedtime.addingTimeInterval(-ease.seconds)
        // Up to the start of the ease the evening is untouched.
        var date = sanFrancisco.at(2026, 11, 19, 15)
        while date <= start {
            #expect(staged(sanFrancisco, date, ease: ease.minutes) == legacy(sanFrancisco, date), "differs at \(date)")
            date += 5 * 60
        }
        #expect(staged(sanFrancisco, start, ease: ease.minutes) == legacy(sanFrancisco, start))
        // Halfway through, halfway in mired.
        let eveningKelvin = evening.kelvin(warmestPoint: .everydayWarmest)
        let halfway = 1_000_000.0 / ((mired(eveningKelvin) + mired(deep)) / 2)
        let half = staged(sanFrancisco, start.addingTimeInterval(ease.seconds / 2), ease: ease.minutes)
        #expect(abs(Double(half.kelvin?.value ?? 0) - halfway) <= 2)
        // One minute short of bedtime it is not there yet; at bedtime and after it is.
        #expect(shown(staged(sanFrancisco, bedtime - 60, ease: ease.minutes)) > deep)
        #expect(staged(sanFrancisco, bedtime, ease: ease.minutes).kelvin == deep)
        #expect(staged(sanFrancisco, sanFrancisco.at(2026, 11, 20, 3), ease: ease.minutes).kelvin == deep)
    }

    @Test("A shorter ease starts later, so mid-evening it is cooler than a longer one")
    func lengthsDiffer() {
        let date = sanFrancisco.at(2026, 11, 19, 22, 30)
        let short = shown(staged(sanFrancisco, date, ease: 15))
        let hour = shown(staged(sanFrancisco, date, ease: 60))
        let long = shown(staged(sanFrancisco, date, ease: 120))
        #expect(short == shown(legacy(sanFrancisco, date)))
        #expect(hour < short)
        #expect(long < hour)
    }

    @Test("The ease only ever warms the screen on the way to bedtime", arguments: Ease.pinned)
    func easeIsMonotonic(_ ease: Ease) {
        var date = sanFrancisco.at(2026, 11, 19, 19)
        var previous = shown(staged(sanFrancisco, date, ease: ease.minutes))
        while date < sanFrancisco.at(2026, 11, 20, 1) {
            date += 60
            let now = shown(staged(sanFrancisco, date, ease: ease.minutes))
            #expect(now <= previous, "cooler at \(date) than a minute before")
            // No visible step: a minute never moves the screen by more than a sliver of the span.
            #expect(previous.value - now.value <= 200, "jump at \(date)")
            previous = now
        }
        #expect(previous == deep)
    }

    // MARK: Late sunsets

    @Test("A sunset inside the ease window: the ease starts at sunset and runs its full length", arguments: Ease.pinned)
    func lateSunset(_ ease: Ease) throws {
        // Oslo, 21 June: sunset ≈ 22:44 CEST, bedtime 22:00. The sun beats every allowed length.
        // "Sunset" is the resolver's own: the minute the sun is fully below the ramp band.
        let noon = oslo.at(2026, 6, 21, 15)
        let sunset = try #require(timeline(oslo, noon, bedtime: 22 * 60, ease: ease.minutes).sunset)
        #expect(sunset > oslo.at(2026, 6, 21, 22))
        var date = oslo.at(2026, 6, 21, 20)
        while date < sunset {
            #expect(staged(oslo, date, bedtime: 22 * 60, ease: ease.minutes) == legacy(oslo, date))
            date += 5 * 60
        }
        // Sunrise comes early here (≈ 03:54), so a long ease must finish before it: 120 min does.
        let eveningKelvin = evening.kelvin(warmestPoint: .everydayWarmest)
        let halfway = 1_000_000.0 / ((mired(eveningKelvin) + mired(deep)) / 2)
        let half = staged(oslo, sunset + ease.seconds / 2, bedtime: 22 * 60, ease: ease.minutes)
        // The solar envelope is still closing just after sunset, hence the looser tolerance.
        #expect(abs(Double(half.kelvin?.value ?? 0) - halfway) <= 40)
        #expect(staged(oslo, sunset + ease.seconds + 60, bedtime: 22 * 60, ease: ease.minutes).kelvin == deep)

        let night = timeline(oslo, noon, bedtime: 22 * 60, ease: ease.minutes)
        let start = try #require(night.deepeningStart)
        #expect(start == sunset)
        #expect(night.deepeningEnd == start.addingTimeInterval(ease.seconds))
    }

    @Test("A sunset part-way into a long ease window clips its start, not its length")
    func sunsetClipsLongEase() throws {
        // San Francisco, 21 June: sunset ≈ 20:35 PDT. Bedtime 21:30 with a 2-hour ease would start
        // at 19:30, in daylight; a 15-minute ease starts at 21:15, well after dark.
        let noon = sanFrancisco.at(2026, 6, 21, 15)
        let long = timeline(sanFrancisco, noon, bedtime: 21 * 60 + 30, ease: 120)
        let sunset = try #require(long.sunset)
        #expect(sunset > sanFrancisco.at(2026, 6, 21, 19, 30))
        #expect(long.deepeningStart == sunset)
        #expect(long.deepeningEnd == sunset.addingTimeInterval(120 * 60))

        let short = timeline(sanFrancisco, noon, bedtime: 21 * 60 + 30, ease: 15)
        #expect(short.deepeningStart == sanFrancisco.at(2026, 6, 21, 21, 15))
        #expect(short.deepeningEnd == sanFrancisco.at(2026, 6, 21, 21, 30))
    }

    // MARK: Early sunrises

    @Test("The sun rising before the ease ends stops it there, for any length", arguments: Ease.pinned)
    func sunriseBeforeEaseEnds(_ ease: Ease) throws {
        // Stockholm, 22 June: the sun sets ≈ 22:08 and is up near 3:31. Pick the bedtime so each
        // length is still easing at sunrise: the ease starts 10 minutes before the sun comes up.
        let night = timeline(stockholm, stockholm.at(2026, 6, 21, 23), bedtime: 4 * 60, ease: nil, warmth: gentle)
        let up = try #require(night.sunrise)
        #expect(up > stockholm.at(2026, 6, 22, 3, 10) && up < stockholm.at(2026, 6, 22, 3, 50))
        // 4:00 bedtime: 15 min starts 3:45 (after sunrise, inert); 60 starts 3:00; 120 starts 2:00.
        func screen(_ date: Date) -> Kelvin {
            shown(staged(stockholm, date, bedtime: 4 * 60, ease: ease.minutes, target: .everydayWarmest, warmth: gentle))
        }
        if ease.minutes == 15 {
            var date = stockholm.at(2026, 6, 21, 14)
            while date <= stockholm.at(2026, 6, 22, 13) {
                #expect(
                    staged(stockholm, date, bedtime: 4 * 60, ease: 15, target: .everydayWarmest, warmth: gentle)
                        == legacy(stockholm, date, warmth: gentle),
                    "differs at \(date)"
                )
                date += 5 * 60
            }
            return
        }
        // The ease had begun: warmer than the evening alone, but short of the target.
        #expect(screen(up) < shown(legacy(stockholm, up, warmth: gentle)))
        #expect(screen(up) > Kelvin.everydayWarmest)
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

    @Test("A longer ease is further along when the sun stops it")
    func longerEaseGetsFurtherBeforeSunrise() throws {
        let night = timeline(stockholm, stockholm.at(2026, 6, 21, 23), bedtime: 4 * 60, ease: nil, warmth: gentle)
        let up = try #require(night.sunrise)
        // Fraction of the ease done at sunrise: (up − 3:00)/60 ≈ 0.5 against (up − 2:00)/120 ≈ 0.75.
        let hour = shown(staged(stockholm, up, bedtime: 4 * 60, ease: 60, target: .everydayWarmest, warmth: gentle))
        let long = shown(staged(stockholm, up, bedtime: 4 * 60, ease: 120, target: .everydayWarmest, warmth: gentle))
        #expect(long < hour)
    }

    @Test("An ease that would begin after sunrise changes nothing that night", arguments: Ease.pinned)
    func easeAfterSunriseIsInert(_ ease: Ease) throws {
        // Reykjavik, 22 June: the sun is up again near 2:55. A 4:00 bedtime starts easing at 3:45
        // or 3:00, both after sunrise; the 2-hour ease starts at 2:00 and does deepen.
        var differs = false
        var date = reykjavik.at(2026, 6, 21, 14)
        while date <= reykjavik.at(2026, 6, 22, 13) {
            let now = staged(reykjavik, date, bedtime: 4 * 60, ease: ease.minutes, target: .everydayWarmest, warmth: gentle)
            if now != legacy(reykjavik, date, warmth: gentle) { differs = true }
            date += 5 * 60
        }
        #expect(differs == (ease.minutes == 120))
    }

    // MARK: Timeline

    @Test("The timeline's deepening window is the ease length, ending at bedtime", arguments: Ease.all)
    func timelineWindow(_ ease: Ease) {
        let night = timeline(sanFrancisco, sanFrancisco.at(2026, 11, 19, 20), bedtime: 23 * 60, ease: ease.minutes)
        let bedtime = sanFrancisco.at(2026, 11, 19, 23)
        #expect(night.bedtime == bedtime)
        #expect(night.deepeningEnd == bedtime)
        #expect(night.deepeningStart == bedtime.addingTimeInterval(-ease.seconds))
    }

    @Test("Timeline samples follow the resolver for the stage's own length", arguments: Ease.pinned)
    func timelineSamplesMatchResolver(_ ease: Ease) {
        let night = timeline(sanFrancisco, sanFrancisco.at(2026, 11, 19, 20), bedtime: 23 * 60, ease: ease.minutes)
        let step = night.end.timeIntervalSince(night.start) / Double(night.samples.count - 1)
        for (index, sample) in night.samples.enumerated() {
            let instant = night.start.addingTimeInterval(Double(index) * step)
            #expect(sample == shown(staged(sanFrancisco, instant, ease: ease.minutes)), "sample \(index)")
        }
    }

    @Test("Two days at one-minute steps never jump, at the shortest and longest ease", arguments: Ease.pinned)
    func neverJumps(_ ease: Ease) {
        // Only two things move the screen: the sun, by however far its band moved this minute, and
        // the stage, by one minute's share of the way from the evening to the target (the ease
        // before bed, or the default-length reset at midday, whichever is steeper). 5 mired of
        // slack covers rounding to a whole Kelvin.
        let target = Kelvin.warmestSupported
        let neutral = mired(.neutral)
        let range = mired(target) - neutral
        let eveningOffset = evening.strength * (mired(.everydayWarmest) - neutral)
        let stagePerMinute = (range - eveningOffset) / Double(min(ease.minutes, LateNightStage.defaultEaseMinutes))
        for (place, month, day, bedtime) in [
            (sanFrancisco, 11, 19, 23 * 60), (oslo, 6, 21, 22 * 60), (oslo, 6, 21, 4 * 60), (reykjavik, 12, 21, 23 * 60),
        ] {
            func sun(_ date: Date) -> Double {
                ScheduleResolver.rampFactor(
                    elevation: ScheduleResolver.solarElevationDegrees(
                        at: date, latitude: place.latitude, longitude: place.longitude
                    ),
                    rampStart: ScheduleResolver.rampStartElevation, rampFull: ScheduleResolver.rampFullElevation
                )
            }
            var date = place.at(2026, month, day, 12)
            var previous = mired(shown(staged(place, date, bedtime: bedtime, ease: ease.minutes, target: target)))
            var previousSun = sun(date)
            for _ in 0..<(48 * 60) {
                date += 60
                let now = mired(shown(staged(place, date, bedtime: bedtime, ease: ease.minutes, target: target)))
                let sunNow = sun(date)
                let limit = abs(sunNow - previousSun) * range + stagePerMinute + 5
                #expect(abs(now - previous) <= limit, "step of \(now - previous) mired at \(date), \(place.zone)")
                previous = now
                previousSun = sunNow
            }
        }
    }
}
