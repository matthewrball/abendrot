import Testing
import Foundation
@testable import WarmthCore

// MARK: - Late-night phase (what `status --json` reports as `lateNight.phase`)

/// The phase is read off the schedule's own maths, never off a Kelvin comparison: a screen on its
/// way back to day is between the same two colours as one easing in, and only the schedule knows
/// which way it is going. Every instant is fixed.
@Suite("Late-night phase")
struct LateNightPhaseTests {

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

    private let evening = WarmthLevel(strength: 0.7)          // 2412 K on the everyday curve
    private let deep = Kelvin(1200)

    private func phase(
        _ place: Place, _ date: Date, bedtime: Int = 23 * 60, ease: Int = 60,
        target: Kelvin? = nil, warmth: WarmthLevel? = nil
    ) -> LateNightPhase {
        ScheduleResolver.lateNightPhase(
            at: date, latitude: place.latitude, longitude: place.longitude,
            configuredWarmth: warmth ?? evening, warmestPoint: .everydayWarmest,
            lateNight: LateNightStage(bedtimeMinutes: bedtime, target: target ?? deep, easeMinutes: ease),
            calendar: place.calendar
        )
    }

    private func night(_ place: Place, _ date: Date, bedtime: Int, ease: Int) -> NightTimeline {
        ScheduleResolver.nightTimeline(
            containing: date, latitude: place.latitude, longitude: place.longitude,
            configuredWarmth: evening, warmestPoint: .everydayWarmest,
            lateNight: LateNightStage(bedtimeMinutes: bedtime, target: deep, easeMinutes: ease),
            calendar: place.calendar
        )
    }

    @Test("The wire values are the four documented strings")
    func rawValues() {
        #expect(LateNightPhase.inactive.rawValue == "inactive")
        #expect(LateNightPhase.easing.rawValue == "easing")
        #expect(LateNightPhase.held.rawValue == "held")
        #expect(LateNightPhase.releasing.rawValue == "releasing")
    }

    @Test("An ordinary night: inactive, easing, held, releasing after sunrise, inactive by day")
    func ordinaryNight() {
        #expect(phase(sanFrancisco, sanFrancisco.at(2026, 11, 19, 15)) == .inactive)
        #expect(phase(sanFrancisco, sanFrancisco.at(2026, 11, 19, 20)) == .inactive)   // evening, before the ease
        #expect(phase(sanFrancisco, sanFrancisco.at(2026, 11, 19, 22)) == .inactive)   // the ease starts here
        #expect(phase(sanFrancisco, sanFrancisco.at(2026, 11, 19, 22, 1)) == .easing)
        #expect(phase(sanFrancisco, sanFrancisco.at(2026, 11, 19, 22, 59)) == .easing)
        #expect(phase(sanFrancisco, sanFrancisco.at(2026, 11, 19, 23)) == .held)
        #expect(phase(sanFrancisco, sanFrancisco.at(2026, 11, 20, 2)) == .held)
        #expect(phase(sanFrancisco, sanFrancisco.at(2026, 11, 20, 10)) == .inactive)
    }

    @Test("Every morning the stage is releasing from sunrise until the screen is neutral, never easing",
          arguments: [15, 60, 120])
    func morningIsReleasing(ease: Int) throws {
        let timeline = night(sanFrancisco, sanFrancisco.at(2026, 11, 19, 20), bedtime: 23 * 60, ease: ease)
        let sunrise = try #require(timeline.sunrise)
        #expect(phase(sanFrancisco, sunrise.addingTimeInterval(-60), ease: ease) == .held)
        #expect(phase(sanFrancisco, sunrise.addingTimeInterval(120), ease: ease) == .releasing)
        #expect(phase(sanFrancisco, sunrise.addingTimeInterval(15 * 60), ease: ease) == .releasing)
        var seen: Set<LateNightPhase> = []
        var date = sunrise.addingTimeInterval(60)
        while date < timeline.end {
            seen.insert(phase(sanFrancisco, date, ease: ease))
            date += 60
        }
        #expect(seen == [.releasing, .inactive])
    }

    @Test("A sunrise that stops the ease short: easing until sunrise, releasing after it, never easing again")
    func sunriseStopsTheEaseShort() throws {
        // Oslo, 21 June: sunrise ≈ 03:54. A 4 AM bedtime's two-hour ease starts at 02:00.
        let timeline = night(oslo, oslo.at(2026, 6, 21, 20), bedtime: 4 * 60, ease: 120)
        let sunrise = try #require(timeline.sunrise)
        #expect(sunrise < oslo.at(2026, 6, 22, 4))
        #expect(phase(oslo, oslo.at(2026, 6, 22, 1, 30), bedtime: 4 * 60, ease: 120) == .inactive)
        #expect(phase(oslo, oslo.at(2026, 6, 22, 3), bedtime: 4 * 60, ease: 120) == .easing)
        #expect(phase(oslo, sunrise.addingTimeInterval(120), bedtime: 4 * 60, ease: 120) == .releasing)
        var date = sunrise.addingTimeInterval(60)
        while date < timeline.end {
            let now = phase(oslo, date, bedtime: 4 * 60, ease: 120)
            #expect(now == .releasing || now == .inactive, "\(now) at \(date)")
            date += 60
        }
    }

    @Test("Polar night: held through the dark morning, releasing over the last hour before midday")
    func polarNightReleasesTowardMidday() {
        // Tromsø, 21 December: the sun never rises. Mean solar noon is ≈ 11:44 CET.
        #expect(phase(tromso, tromso.at(2026, 12, 21, 22, 30)) == .easing)
        #expect(phase(tromso, tromso.at(2026, 12, 21, 23)) == .held)
        #expect(phase(tromso, tromso.at(2026, 12, 22, 9)) == .held)
        #expect(phase(tromso, tromso.at(2026, 12, 22, 11)) == .releasing)
        #expect(phase(tromso, tromso.at(2026, 12, 22, 11, 40)) == .releasing)
        #expect(phase(tromso, tromso.at(2026, 12, 22, 12, 30)) == .inactive)
    }

    @Test("A late sunset: easing from sunset, held once the full ease has run", arguments: [15, 120])
    func lateSunset(ease: Int) throws {
        let timeline = night(oslo, oslo.at(2026, 6, 21, 20), bedtime: 22 * 60, ease: ease)
        let sunset = try #require(timeline.sunset)
        #expect(phase(oslo, oslo.at(2026, 6, 21, 22), bedtime: 22 * 60, ease: ease) == .inactive)
        #expect(phase(oslo, sunset.addingTimeInterval(5 * 60), bedtime: 22 * 60, ease: ease) == .easing)
        #expect(phase(oslo, sunset.addingTimeInterval(Double(ease) * 60), bedtime: 22 * 60, ease: ease) == .held)
    }

    @Test("A stage that adds nothing is inactive all night")
    func nothingToAdd() {
        // A late-night level no warmer than the evening.
        #expect(phase(sanFrancisco, sanFrancisco.at(2026, 11, 19, 23, 30), target: Kelvin(3000)) == .inactive)
        // Midnight sun: no sunset, so the ease never starts.
        #expect(phase(tromso, tromso.at(2026, 6, 21, 23, 30)) == .inactive)
    }

    @Test("The phase agrees with the resolver: a stage Kelvin exists exactly when the phase is not inactive")
    func agreesWithTheResolver() {
        var date = sanFrancisco.at(2026, 11, 19, 12)
        while date < sanFrancisco.at(2026, 11, 20, 12) {
            let decision = ScheduleResolver.solarRampDecision(
                at: date, latitude: sanFrancisco.latitude, longitude: sanFrancisco.longitude,
                configuredWarmth: evening, warmestPoint: .everydayWarmest,
                lateNight: LateNightStage(bedtimeMinutes: 23 * 60, target: deep), calendar: sanFrancisco.calendar
            )
            let now = phase(sanFrancisco, date)
            #expect((decision.isActiveNow && decision.kelvin != nil) == (now != .inactive), "\(now) at \(date)")
            if now == .held { #expect(decision.kelvin == deep) }
            date += 7 * 60
        }
    }

    @Test("A screen held neutral, or a stage that is not running, reports inactive whatever the schedule says")
    func gates() {
        for phase in [LateNightPhase.inactive, .easing, .held, .releasing] {
            #expect(phase.reported(stageRunning: true, screenHeldNeutral: false) == phase)
            #expect(phase.reported(stageRunning: true, screenHeldNeutral: true) == .inactive)
            #expect(phase.reported(stageRunning: false, screenHeldNeutral: false) == .inactive)
        }
    }
}
