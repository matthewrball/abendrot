import Testing
import Foundation
@testable import WarmthCore

// MARK: - Night timeline (the Settings anchors strip reads this)

/// One night laid out for display: the anchors and the colour between them, taken from the same
/// resolver the engine runs so the picture cannot disagree with the screen. Every instant is fixed.
@Suite("Night timeline")
struct NightTimelineTests {

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
    private let tromso = Place(latitude: 69.65, longitude: 18.96, zone: "Europe/Oslo")
    private let berlin = Place(latitude: 52.52, longitude: 13.40, zone: "Europe/Berlin")

    private let evening = WarmthLevel(strength: 0.7)          // 2412 K on the everyday curve
    private let deep = Kelvin(1200)

    private func timeline(
        _ place: Place,
        _ date: Date,
        bedtime: Int? = 23 * 60,
        sampleCount: Int = 97
    ) -> NightTimeline {
        ScheduleResolver.nightTimeline(
            containing: date, latitude: place.latitude, longitude: place.longitude,
            configuredWarmth: evening, warmestPoint: .everydayWarmest,
            lateNight: bedtime.map { LateNightStage(bedtimeMinutes: $0, target: deep) },
            calendar: place.calendar, sampleCount: sampleCount
        )
    }

    /// The sample closest to `date`.
    private func sample(_ timeline: NightTimeline, at date: Date) -> Kelvin {
        let fraction = date.timeIntervalSince(timeline.start) / timeline.end.timeIntervalSince(timeline.start)
        let index = Int((fraction * Double(timeline.samples.count - 1)).rounded())
        return timeline.samples[index]
    }

    @Test("Sunset and sunrise land on whole clock minutes, the minute the Location caption prints")
    func sunTimesAreWholeMinutes() throws {
        // Mean solar noon is not on a whole minute anywhere but the prime meridian, so a scan
        // counted from it printed 4:55 PM beside the caption's 4:56 PM.
        let nights: [(Place, Date)] = [
            (sanFrancisco, sanFrancisco.at(2026, 11, 19, 20)),
            (berlin, berlin.at(2026, 11, 19, 20)),
            (oslo, oslo.at(2026, 6, 21, 20)),
            (sanFrancisco, sanFrancisco.at(2026, 3, 8, 20)),
        ]
        for (place, date) in nights {
            let night = timeline(place, date)
            let sunset = try #require(night.sunset)
            let sunrise = try #require(night.sunrise)
            #expect(sunset.timeIntervalSince1970.truncatingRemainder(dividingBy: 60) == 0)
            #expect(sunrise.timeIntervalSince1970.truncatingRemainder(dividingBy: 60) == 0)
            #expect(sunset == ScheduleResolver.sunsetTime(
                forCoordinate: .init(latitude: place.latitude, longitude: place.longitude),
                on: date, calendar: place.calendar
            ))
        }
    }

    @Test("A night runs solar noon to solar noon with the anchors in order")
    func anchorsInOrder() throws {
        let night = timeline(sanFrancisco, sanFrancisco.at(2026, 11, 19, 20))
        // Mean solar noon at 122.42°W is ≈ 12:10 PST.
        #expect(abs(night.start.timeIntervalSince(sanFrancisco.at(2026, 11, 19, 12, 10))) < 60)
        #expect(night.end.timeIntervalSince(night.start) == 86_400)

        let sunset = try #require(night.sunset)
        let expectedSunset = try #require(ScheduleResolver.sunsetTime(
            forCoordinate: .init(latitude: sanFrancisco.latitude, longitude: sanFrancisco.longitude),
            on: sanFrancisco.at(2026, 11, 19, 12), calendar: sanFrancisco.calendar
        ))
        #expect(sunset == expectedSunset)

        let sunrise = try #require(night.sunrise)
        #expect(sunrise > sanFrancisco.at(2026, 11, 20, 6, 40))
        #expect(sunrise < sanFrancisco.at(2026, 11, 20, 7, 10))

        #expect(night.bedtime == sanFrancisco.at(2026, 11, 19, 23))
        #expect(night.deepeningStart == sanFrancisco.at(2026, 11, 19, 22))
        #expect(night.deepeningEnd == sanFrancisco.at(2026, 11, 19, 23))
        #expect(night.start < sunset && sunset < sunrise && sunrise < night.end)
    }

    @Test("Two in the morning still belongs to last evening's night")
    func smallHoursShowTheSameNight() {
        #expect(timeline(sanFrancisco, sanFrancisco.at(2026, 11, 20, 2))
            == timeline(sanFrancisco, sanFrancisco.at(2026, 11, 19, 20)))
    }

    @Test("The colour runs neutral, evening, late night, neutral")
    func samplesFollowTheAnchors() {
        let night = timeline(sanFrancisco, sanFrancisco.at(2026, 11, 19, 20))
        #expect(night.samples.count == 97)
        #expect(night.samples.first == .neutral)
        #expect(night.samples.last == .neutral)
        #expect(sample(night, at: sanFrancisco.at(2026, 11, 19, 20)) == evening.kelvin(warmestPoint: .everydayWarmest))
        #expect(sample(night, at: sanFrancisco.at(2026, 11, 20, 2)) == deep)
    }

    @Test("Every sample is what the resolver decides for that instant")
    func samplesMatchTheResolver() {
        let night = timeline(sanFrancisco, sanFrancisco.at(2026, 11, 19, 20), sampleCount: 49)
        let step = night.end.timeIntervalSince(night.start) / 48
        for (index, kelvin) in night.samples.enumerated() {
            let decision = ScheduleResolver.solarRampDecision(
                at: night.start.addingTimeInterval(Double(index) * step),
                latitude: sanFrancisco.latitude, longitude: sanFrancisco.longitude,
                configuredWarmth: evening, warmestPoint: .everydayWarmest,
                lateNight: LateNightStage(bedtimeMinutes: 23 * 60, target: deep),
                calendar: sanFrancisco.calendar
            )
            let expected = decision.isActiveNow
                ? decision.kelvin ?? decision.target.kelvin(warmestPoint: .everydayWarmest)
                : Kelvin.neutral
            #expect(kelvin == expected)
        }
    }

    @Test("Without a stage the night holds the evening and has no bedtime")
    func noStage() {
        let night = timeline(sanFrancisco, sanFrancisco.at(2026, 11, 19, 20), bedtime: nil)
        #expect(night.bedtime == nil)
        #expect(night.deepeningStart == nil)
        #expect(night.deepeningEnd == nil)
        #expect(night.sunset != nil)
        #expect(sample(night, at: sanFrancisco.at(2026, 11, 20, 2)) == evening.kelvin(warmestPoint: .everydayWarmest))
    }

    @Test("A bedtime before sunset: the deepening starts at sunset and ends an hour later")
    func bedtimeBeforeSunset() throws {
        // Oslo, 21 June: sunset ≈ 22:44 CEST, bedtime 22:00.
        let night = timeline(oslo, oslo.at(2026, 6, 21, 20), bedtime: 22 * 60)
        let sunset = try #require(night.sunset)
        #expect(night.bedtime == oslo.at(2026, 6, 21, 22))
        #expect(night.deepeningStart == sunset)
        #expect(night.deepeningEnd == sunset.addingTimeInterval(3600))
    }

    @Test("Midnight sun: no sunset, no sunrise, nothing deepens")
    func midnightSun() {
        let night = timeline(tromso, tromso.at(2026, 6, 21, 20))
        #expect(night.sunset == nil)
        #expect(night.sunrise == nil)
        #expect(night.deepeningStart == nil)
        // The low midnight sun still warms a little on the existing curve; the stage adds nothing.
        #expect(night.samples == timeline(tromso, tromso.at(2026, 6, 21, 20), bedtime: nil).samples)
    }

    @Test("Polar night: dark from the start, with no sunrise to wait for")
    func polarNight() {
        let night = timeline(tromso, tromso.at(2026, 12, 21, 20))
        #expect(night.sunset == night.start)
        #expect(night.sunrise == nil)
        #expect(night.deepeningStart == tromso.at(2026, 12, 21, 22))
        #expect(sample(night, at: tromso.at(2026, 12, 22, 2)) == deep)
    }

    // MARK: What the strip may print (the handle's Kelvin and where the ease really ends)

    private func labelled(_ place: Place, _ date: Date, bedtime: Int, ease: Int, target: Kelvin? = nil) -> NightTimeline {
        ScheduleResolver.nightTimeline(
            containing: date, latitude: place.latitude, longitude: place.longitude,
            configuredWarmth: evening, warmestPoint: .everydayWarmest,
            lateNight: LateNightStage(bedtimeMinutes: bedtime, target: target ?? deep, easeMinutes: ease),
            calendar: place.calendar
        )
    }

    /// What the resolver puts on screen at `date`.
    private func shown(_ place: Place, _ date: Date, bedtime: Int, ease: Int) -> Kelvin {
        let decision = ScheduleResolver.solarRampDecision(
            at: date, latitude: place.latitude, longitude: place.longitude,
            configuredWarmth: evening, warmestPoint: .everydayWarmest,
            lateNight: LateNightStage(bedtimeMinutes: bedtime, target: deep, easeMinutes: ease),
            calendar: place.calendar
        )
        guard decision.isActiveNow else { return .neutral }
        return decision.kelvin ?? decision.target.kelvin(warmestPoint: .everydayWarmest)
    }

    @Test("An ordinary night: the late-night Kelvin sits under the bedtime handle", arguments: [15, 120])
    func ordinaryNightLabels(ease: Int) {
        let night = labelled(sanFrancisco, sanFrancisco.at(2026, 11, 19, 20), bedtime: 23 * 60, ease: ease)
        #expect(night.bedtimeKelvin == deep)
        #expect(night.heldKelvin == deep)
        #expect(night.heldFrom == sanFrancisco.at(2026, 11, 19, 23))
        #expect(night.kelvinUnderBedtime == deep)
        #expect(night.lateEaseEnd == nil)
    }

    @Test("A late sunset: the handle shows no Kelvin and the late-night Kelvin moves to where the ease ends",
          arguments: [15, 120])
    func lateSunsetLabels(ease: Int) throws {
        // Oslo, 21 June: sunset ≈ 22:44 CEST. Bedtime ten minutes later is inside every ease length.
        let bedtime = 22 * 60 + 54
        let night = labelled(oslo, oslo.at(2026, 6, 21, 20), bedtime: bedtime, ease: ease)
        let sunset = try #require(night.sunset)
        let bedtimeDate = try #require(night.bedtime)
        #expect(sunset < bedtimeDate && bedtimeDate < sunset.addingTimeInterval(Double(ease) * 60))
        #expect(night.deepeningStart == sunset)

        // At bedtime the screen is still on its way: warmer than the evening, short of the target.
        let atBedtime = try #require(night.bedtimeKelvin)
        #expect(atBedtime == shown(oslo, bedtimeDate, bedtime: bedtime, ease: ease))
        #expect(atBedtime > deep && atBedtime < evening.kelvin(warmestPoint: .everydayWarmest))
        #expect(night.kelvinUnderBedtime == nil)

        let end = try #require(night.lateEaseEnd)
        #expect(end.date == sunset.addingTimeInterval(Double(ease) * 60))
        #expect(end.kelvin == deep)
        #expect(shown(oslo, end.date, bedtime: bedtime, ease: ease) == deep)
        #expect(shown(oslo, end.date.addingTimeInterval(-120), bedtime: bedtime, ease: ease) > deep)
    }

    @Test("A bedtime before sunset: the handle shows no Kelvin and the ease ends its length after sunset",
          arguments: [15, 120])
    func bedtimeBeforeSunsetLabels(ease: Int) throws {
        // Oslo, 21 June: sunset ≈ 22:44 CEST, bedtime 22:00. The screen is barely warm at bedtime.
        let night = labelled(oslo, oslo.at(2026, 6, 21, 20), bedtime: 22 * 60, ease: ease)
        let sunset = try #require(night.sunset)
        let atBedtime = try #require(night.bedtimeKelvin)
        #expect(atBedtime == shown(oslo, oslo.at(2026, 6, 21, 22), bedtime: 22 * 60, ease: ease))
        #expect(atBedtime > evening.kelvin(warmestPoint: .everydayWarmest))
        #expect(night.kelvinUnderBedtime == nil)

        let end = try #require(night.lateEaseEnd)
        #expect(end.date == sunset.addingTimeInterval(Double(ease) * 60))
        #expect(end.kelvin == deep)
        #expect(night.heldFrom == end.date)
        #expect(shown(oslo, end.date, bedtime: 22 * 60, ease: ease) == deep)
    }

    @Test("A sunrise before the ease finishes: no Kelvin is promised anywhere")
    func sunriseBeforeTheEaseEnds() throws {
        // Oslo, 21 June: sunrise ≈ 03:54. A 4 AM bedtime's two-hour ease is cut off by it.
        let night = labelled(oslo, oslo.at(2026, 6, 21, 20), bedtime: 4 * 60, ease: 120)
        let sunrise = try #require(night.sunrise)
        let end = try #require(night.deepeningEnd)
        #expect(sunrise < end)
        #expect(night.heldKelvin == nil)
        #expect(night.heldFrom == nil)
        #expect(night.kelvinUnderBedtime == nil)
        #expect(night.lateEaseEnd == nil)
    }

    @Test("A late-night level no warmer than the evening: the evening's Kelvin holds, and only where it is true")
    func noDeeperLabels() {
        let eveningKelvin = evening.kelvin(warmestPoint: .everydayWarmest)
        let ordinary = labelled(sanFrancisco, sanFrancisco.at(2026, 11, 19, 20), bedtime: 23 * 60, ease: 60, target: Kelvin(3000))
        #expect(ordinary.heldKelvin == eveningKelvin)
        #expect(ordinary.heldFrom == ordinary.sunset)
        #expect(ordinary.kelvinUnderBedtime == eveningKelvin)
        #expect(ordinary.lateEaseEnd == nil)

        // Before sunset the screen is not yet at the evening level, and Sunset already marks it.
        let early = labelled(oslo, oslo.at(2026, 6, 21, 20), bedtime: 22 * 60, ease: 60, target: Kelvin(3000))
        #expect(early.heldKelvin == eveningKelvin)
        #expect(early.kelvinUnderBedtime == nil)
        #expect(early.lateEaseEnd == nil)
    }

    @Test("Without a stage, or when the sun stays up, there is nothing to label")
    func nothingToLabel() {
        let plain = timeline(sanFrancisco, sanFrancisco.at(2026, 11, 19, 20), bedtime: nil)
        #expect(plain.bedtimeKelvin == nil)
        #expect(plain.heldKelvin == nil)
        #expect(plain.kelvinUnderBedtime == nil)
        #expect(plain.lateEaseEnd == nil)
        let sunUp = timeline(tromso, tromso.at(2026, 6, 21, 20))
        #expect(sunUp.heldKelvin == nil)
        #expect(sunUp.kelvinUnderBedtime == nil)
        #expect(sunUp.lateEaseEnd == nil)
    }

    // MARK: Dragging the bedtime along the strip

    /// 8 PM through 4 AM, in half hours: the range the Settings controls offer.
    private let bedtimes = 20 * 60...28 * 60

    private func dragged(_ night: NightTimeline, to date: Date, on place: Place) -> Int {
        let fraction = date.timeIntervalSince(night.start) / night.end.timeIntervalSince(night.start)
        return night.bedtimeMinutes(at: fraction, in: bedtimes, step: 30, calendar: place.calendar)
    }

    @Test("A pointer on the strip reads the Mac's clock there, to the half hour")
    func pointerReadsTheClock() {
        let night = timeline(sanFrancisco, sanFrancisco.at(2026, 11, 19, 20))
        #expect(dragged(night, to: sanFrancisco.at(2026, 11, 19, 23), on: sanFrancisco) == 23 * 60)
        #expect(dragged(night, to: sanFrancisco.at(2026, 11, 19, 23, 10), on: sanFrancisco) == 23 * 60)
        #expect(dragged(night, to: sanFrancisco.at(2026, 11, 19, 23, 50), on: sanFrancisco) == 0)
        #expect(dragged(night, to: sanFrancisco.at(2026, 11, 20, 0, 20), on: sanFrancisco) == 30)
    }

    @Test("Past either end of the range the bedtime stays at that end, all the way to the strip's edge")
    func pointerHoldsAtTheNearerEnd() {
        // Summer time puts solar noon near 1:10 PM, so the strip's last hour reads past twelve
        // on the clock: read as a clock time alone, that is an afternoon, the far end of the range.
        let night = timeline(sanFrancisco, sanFrancisco.at(2026, 7, 15, 21))
        #expect(night.bedtimeMinutes(at: 0, in: bedtimes, step: 30, calendar: sanFrancisco.calendar) == 20 * 60)
        #expect(dragged(night, to: sanFrancisco.at(2026, 7, 15, 17), on: sanFrancisco) == 20 * 60)
        #expect(dragged(night, to: sanFrancisco.at(2026, 7, 16, 7), on: sanFrancisco) == 4 * 60)
        #expect(dragged(night, to: sanFrancisco.at(2026, 7, 16, 12, 30), on: sanFrancisco) == 4 * 60)
        #expect(night.bedtimeMinutes(at: 1, in: bedtimes, step: 30, calendar: sanFrancisco.calendar) == 4 * 60)
        #expect(night.bedtimeMinutes(at: 7, in: bedtimes, step: 30, calendar: sanFrancisco.calendar) == 4 * 60)
        #expect(night.bedtimeMinutes(at: -7, in: bedtimes, step: 30, calendar: sanFrancisco.calendar) == 20 * 60)
    }

    @Test("A far-away Sunset location wraps the range around the strip: the gap goes to the nearer end")
    func pointerWithAFarAwayLocation() {
        // Berlin's night on a San Francisco clock runs about 3:06 AM to 3:06 AM, so 4 AM is near
        // the strip's left edge and 8 PM is most of the way along it.
        let night = ScheduleResolver.nightTimeline(
            containing: berlin.at(2026, 11, 19, 20), latitude: berlin.latitude, longitude: berlin.longitude,
            configuredWarmth: evening, warmestPoint: .everydayWarmest,
            lateNight: LateNightStage(bedtimeMinutes: 23 * 60, target: deep), calendar: sanFrancisco.calendar
        )
        #expect(dragged(night, to: sanFrancisco.at(2026, 11, 19, 3, 30), on: sanFrancisco) == 3 * 60 + 30)
        #expect(dragged(night, to: sanFrancisco.at(2026, 11, 19, 10), on: sanFrancisco) == 4 * 60)
        #expect(dragged(night, to: sanFrancisco.at(2026, 11, 19, 15), on: sanFrancisco) == 20 * 60)
        #expect(dragged(night, to: sanFrancisco.at(2026, 11, 19, 22), on: sanFrancisco) == 22 * 60)
        #expect(dragged(night, to: sanFrancisco.at(2026, 11, 20, 2), on: sanFrancisco) == 2 * 60)
    }
}
