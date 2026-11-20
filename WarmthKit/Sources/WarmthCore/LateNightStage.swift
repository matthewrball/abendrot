import Foundation

// MARK: - Late-night deepening

/// The opt-in second stage of Sunset mode: after the evening has arrived with the real sunset,
/// ease further to `target` by a clock bedtime and hold it until the real sunrise.
///
/// Bedtime follows the Mac's own clock (the calendar the resolver is handed), while sunset and
/// sunrise follow the Sunset location. They differ only when the user pins a far-away city.
public struct LateNightStage: Hashable, Sendable {
    /// Local minute of the day (0..<1440) at which the late-night warmth is fully reached.
    public let bedtimeMinutes: Int
    /// The colour temperature held from bedtime until sunrise.
    public let target: Kelvin
    /// Length, in minutes, of the ease that ENDS at bedtime.
    public let easeMinutes: Int

    /// Length of the ease that ENDS at bedtime.
    public var rampDuration: TimeInterval { TimeInterval(easeMinutes) * 60 }

    public static let defaultBedtimeMinutes = 23 * 60
    /// The ease length when the user has not chosen one: the hour the stage first shipped with.
    public static let defaultEaseMinutes = 60
    public static let defaultRampDuration = TimeInterval(defaultEaseMinutes) * 60
    /// The ease lengths Settings and the CLI offer.
    public static let allowedEaseMinutes = [15, 30, 45, 60, 90, 120]

    /// The bedtimes Settings and the CLI offer, counted from the evening's midnight so the range
    /// can cross it: 8 PM through 4 AM is `1200...1680`.
    public static let bedtimeRange = 20 * 60...28 * 60
    public static let bedtimeStep = 30

    public init(bedtimeMinutes: Int, target: Kelvin, easeMinutes: Int = LateNightStage.defaultEaseMinutes) {
        self.bedtimeMinutes = ((bedtimeMinutes % 1440) + 1440) % 1440
        self.target = target
        // A day at most: a corrupt length must not push the ramp's dates out of range.
        self.easeMinutes = min(1440, max(1, easeMinutes))
    }

    /// The allowed ease length closest to `minutes`; the shorter one on a tie.
    public static func nearestEaseMinutes(to minutes: Int) -> Int {
        guard let shortest = allowedEaseMinutes.min(), let longest = allowedEaseMinutes.max() else {
            return defaultEaseMinutes
        }
        // Held inside the set first: a corrupt stored value can be Int.min or Int.max, and the
        // distance to it would overflow.
        let bounded = min(max(minutes, shortest), longest)
        return allowedEaseMinutes.min { abs($0 - bounded) < abs($1 - bounded) } ?? defaultEaseMinutes
    }

    /// The allowed length `offset` places along from `minutes` (its nearest allowed length),
    /// stopping at either end: what a stepper's minus and plus ask for.
    public static func easeMinutes(stepping minutes: Int, by offset: Int) -> Int {
        let index = allowedEaseMinutes.firstIndex(of: nearestEaseMinutes(to: minutes)) ?? 0
        let last = allowedEaseMinutes.count - 1
        return allowedEaseMinutes[min(max(index + min(max(offset, -last), last), 0), last)]
    }

    /// A length as a compact label: "15 min", "1 hr", "1 hr 30 min".
    public static func easeText(minutes: Int) -> String {
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return "\(rest) min" }
        return rest == 0 ? "\(hours) hr" : "\(hours) hr \(rest) min"
    }

    /// The same length in full words, for VoiceOver: "1 hour 30 minutes".
    public static func easeSpokenText(minutes: Int) -> String {
        let hours = minutes / 60, rest = minutes % 60
        let hourText = "\(hours) \(hours == 1 ? "hour" : "hours")"
        let minuteText = "\(rest) \(rest == 1 ? "minute" : "minutes")"
        if hours == 0 { return minuteText }
        return rest == 0 ? hourText : "\(hourText) \(minuteText)"
    }

    /// Any minute count as a clock bedtime (`0..<1440`) the app offers: a time outside
    /// `bedtimeRange` moves to the nearer end, and a time off the `bedtimeStep` snaps to the
    /// nearest step, the earlier one on a tie. What the app does with a stored value, so
    /// `isAllowedBedtime` holds for everything this returns.
    public static func clampedBedtime(minutesOfDay minutes: Int) -> Int {
        let clock = ((minutes % 1440) + 1440) % 1440
        let evening = clock < 12 * 60 ? clock + 1440 : clock
        let inRange = min(max(evening, bedtimeRange.lowerBound), bedtimeRange.upperBound)
        let past = inRange - bedtimeRange.lowerBound
        let steps = (past + (bedtimeStep - 1) / 2) / bedtimeStep
        return min(bedtimeRange.lowerBound + steps * bedtimeStep, bedtimeRange.upperBound) % 1440
    }

    /// Whether a clock time (minutes after midnight, `0..<1440`) is a bedtime the app offers:
    /// inside `bedtimeRange` and on a `bedtimeStep`.
    public static func isAllowedBedtime(minutesOfDay: Int) -> Bool {
        guard (0..<1440).contains(minutesOfDay) else { return false }
        let evening = minutesOfDay < 12 * 60 ? minutesOfDay + 1440 : minutesOfDay
        return bedtimeRange.contains(evening) && (evening - bedtimeRange.lowerBound) % bedtimeStep == 0
    }
}

extension ScheduleResolver {

    /// Sunset mode with a late-night stage. Wherever the stage contributes nothing (daytime, the
    /// evening before the ramp, a target no warmer than the evening) this returns the plain
    /// `solarRampDecision` unchanged, so the existing curve is the baseline, not a reimplementation.
    ///
    /// The blend is linear in mired as an offset from neutral, under the solar envelope:
    /// `neutral + solar × (lerp(evening, night, nightFactor) − neutral)`. The envelope is what
    /// releases the stage at sunrise, so there is no second ramp to schedule there.
    public static func solarRampDecision(
        at date: Date,
        latitude: Double,
        longitude: Double,
        configuredWarmth: WarmthLevel,
        warmestPoint: Kelvin,
        lateNight: LateNightStage,
        calendar: Calendar = .current
    ) -> ScheduleDecision {
        let evening = solarRampDecision(
            at: date, latitude: latitude, longitude: longitude, configuredWarmth: configuredWarmth
        )
        guard evening.isActiveNow else { return evening }

        let neutralMired = 1_000_000.0 / Double(Kelvin.neutral.value)
        let warmestMired = 1_000_000.0 / Double(warmestPoint.value)
        let eveningMired = neutralMired + configuredWarmth.strength * (warmestMired - neutralMired)
        let nightMired = 1_000_000.0 / Double(lateNight.target.value)

        let night = nightMired > eveningMired
            ? lateNightFactor(
                at: date, latitude: latitude, longitude: longitude,
                bedtimeMinutes: lateNight.bedtimeMinutes, rampDuration: lateNight.rampDuration,
                calendar: calendar
            )
            : 0
        guard night > 0 else {
            // An evening set to zero is neutral, not "warming at 0%": with a stage that can warm
            // later, the icon and the warmed-time count must not start at sunset.
            return evening.target == .off ? .inactive : evening
        }

        let elevation = solarElevationDegrees(at: date, latitude: latitude, longitude: longitude)
        let solar = rampFactor(elevation: elevation, rampStart: rampStartElevation, rampFull: rampFullElevation)
        let mired = neutralMired + solar * (eveningMired + night * (nightMired - eveningMired) - neutralMired)
        let kelvin = Kelvin(Int((1_000_000.0 / mired).rounded()))
        guard kelvin < .neutral else { return .inactive }

        // The strength the user's own slider would need to show this Kelvin — pegged at its warm
        // end once the stage has gone past it. Drives the locked popover readout.
        let span = warmestMired - neutralMired
        let equivalent = span > 0 ? (mired - neutralMired) / span : 1
        return ScheduleDecision(isActiveNow: true, target: WarmthLevel(strength: equivalent), kelvin: kelvin)
    }

    /// 0 through the day and evening, easing to 1 over `rampDuration` (the stage's ease) ending at
    /// bedtime, then 1 until the following midday.
    ///
    /// One cycle is a mean solar day at the Sunset location, noon to noon, so the reset always
    /// lands where the sun is highest: invisible when there is a real day, and a gentle ease when
    /// there is not (polar night). Every edge is a ramp between dated instants, never a wall-clock
    /// comparison, so DST and odd bedtimes cannot produce a step or run the fade backwards.
    ///
    /// The ramp never starts before the sun has set: with a bedtime earlier than sunset it starts
    /// at sunset instead, so the evening anchor is always reached first. It never runs on into
    /// daylight either: sunrise holds it where it is.
    ///
    /// The release towards the following midday keeps the default length whatever the ease is:
    /// it is the reset, not the ease before bed, and a short ease must not sharpen it.
    static func lateNightFactor(
        at date: Date,
        latitude: Double,
        longitude: Double,
        bedtimeMinutes: Int,
        rampDuration: TimeInterval = LateNightStage.defaultRampDuration,
        calendar: Calendar
    ) -> Double {
        lateNightProgress(
            at: date, latitude: latitude, longitude: longitude,
            bedtimeMinutes: bedtimeMinutes, rampDuration: rampDuration, calendar: calendar
        )?.factor ?? 0
    }

    /// The two ramps behind `lateNightFactor`, kept apart so the phase can tell which one is
    /// governing. Nil before the ease starts, or on a night with no sunset or no bedtime.
    struct LateNightProgress {
        /// How far the ease before bed has run, 0 upward; 1 and over is done. Frozen at sunrise.
        let rising: Double
        /// The release towards the following midday: over 1 until its last hour, then down to 0.
        let falling: Double
        /// True once the sun has come back up since the ease started.
        let sunIsBackUp: Bool

        var factor: Double { min(1, max(0, min(rising, falling))) }
    }

    static func lateNightProgress(
        at date: Date,
        latitude: Double,
        longitude: Double,
        bedtimeMinutes: Int,
        rampDuration: TimeInterval,
        calendar: Calendar
    ) -> LateNightProgress? {
        let ramp = max(60, rampDuration)
        let (noon, nextNoon) = nightCycle(containing: date, longitude: longitude)
        guard let bedtime = bedtimeInstant(bedtimeMinutes, from: noon, before: nextNoon, calendar: calendar),
              date > bedtime.addingTimeInterval(-ramp),
              let sunset = firstInstant(
                  from: noon, through: date, latitude: latitude, longitude: longitude, sunIsDown: true
              )
        else { return nil }

        let rampStart = max(bedtime.addingTimeInterval(-ramp), sunset)
        // The sun coming back up stops the deepening where it has got to, so daylight only ever
        // cools the screen. Up before the ramp starts, it leaves the night as it was.
        let sunrise = date > rampStart
            ? firstInstant(from: rampStart, through: date, latitude: latitude, longitude: longitude, sunIsDown: false)
            : nil
        let rising = (sunrise ?? date).timeIntervalSince(rampStart) / ramp
        let falling = nextNoon.timeIntervalSince(date) / LateNightStage.defaultRampDuration
        return LateNightProgress(rising: rising, falling: falling, sunIsBackUp: sunrise != nil)
    }

    /// What the stage is doing to the screen at `date`, from the same ramps the decision uses.
    ///
    /// - `inactive`: the stage adds nothing (day, the evening before the ease, a late-night level
    /// no warmer than the evening, a night with no sunset).
    /// - `easing`: the ease before bed is running and the screen is getting warmer.
    /// - `held`: the ease has finished and nothing is moving.
    /// - `releasing`: the screen is on its way back to day, either because the sun is up again
    /// or, with no sunrise, over the last hour before midday.
    ///
    /// A sunrise that stops the ease short goes straight from `easing` to `releasing`: the
    /// instant that stops the ease is the instant daylight starts cooling the screen, so the
    /// stage is never held part-way.
    public static func lateNightPhase(
        at date: Date,
        latitude: Double,
        longitude: Double,
        configuredWarmth: WarmthLevel,
        warmestPoint: Kelvin,
        lateNight: LateNightStage,
        calendar: Calendar = .current
    ) -> LateNightPhase {
        let decision = solarRampDecision(
            at: date, latitude: latitude, longitude: longitude,
            configuredWarmth: configuredWarmth, warmestPoint: warmestPoint,
            lateNight: lateNight, calendar: calendar
        )
        // Only the stage resolves a Kelvin of its own: without one the plain evening is in charge.
        guard decision.isActiveNow, decision.kelvin != nil,
              let progress = lateNightProgress(
                  at: date, latitude: latitude, longitude: longitude,
                  bedtimeMinutes: lateNight.bedtimeMinutes, rampDuration: lateNight.rampDuration,
                  calendar: calendar
              )
        else { return .inactive }
        if progress.sunIsBackUp || progress.falling < min(1, progress.rising) { return .releasing }
        return progress.rising < 1 ? .easing : .held
    }

    /// The mean solar day at the Sunset location that contains `date`, noon to noon: 12:00 UTC
    /// shifted by four minutes per degree of longitude.
    private static func nightCycle(containing date: Date, longitude: Double) -> (noon: Date, nextNoon: Date) {
        let day = 86_400.0
        let noonOffset = day / 2 - longitude * 240
        let cycle = ((date.timeIntervalSince1970 - noonOffset) / day).rounded(.down)
        let noon = Date(timeIntervalSince1970: cycle * day + noonOffset)
        return (noon, noon.addingTimeInterval(day))
    }

    /// The one instant in the cycle when the Mac's clock reads the bedtime.
    fileprivate static func bedtimeInstant(
        _ bedtimeMinutes: Int, from noon: Date, before nextNoon: Date, calendar: Calendar
    ) -> Date? {
        let minutes = ((bedtimeMinutes % 1440) + 1440) % 1440
        let clock = DateComponents(hour: minutes / 60, minute: minutes % 60)
        guard let bedtime = calendar.nextDate(after: noon, matching: clock, matchingPolicy: .nextTime),
              bedtime < nextNoon
        else { return nil }
        return bedtime
    }

    /// The first whole minute on the clock in `[start, end]` with the sun at or below the sunset
    /// horizon (`sunIsDown`) or above it, so the time printed from it is the one `sunsetTime`
    /// prints. `start` itself when that already holds (polar night, for a sunset); `end` when the
    /// crossing falls in its last part-minute; nil when it never happens.
    private static func firstInstant(
        from start: Date, through end: Date, latitude: Double, longitude: Double, sunIsDown: Bool
    ) -> Date? {
        func holds(_ instant: Date) -> Bool {
            let down = solarElevationDegrees(at: instant, latitude: latitude, longitude: longitude) <= rampFullElevation
            return down == sunIsDown
        }
        if holds(start) { return start }
        let coarse = 5.0 * 60
        var instant = start
        while instant < end {
            let next = min(end, instant.addingTimeInterval(coarse))
            if holds(next) {
                // `start` is mean solar noon, which is on a whole minute only at the prime meridian.
                let wholeMinutes = (instant.timeIntervalSince1970 / 60).rounded(.down) + 1
                var minute = Date(timeIntervalSince1970: wholeMinutes * 60)
                while minute < next, !holds(minute) { minute.addTimeInterval(60) }
                return min(minute, end)
            }
            instant = next
        }
        return nil
    }
}

// MARK: - Late-night phase

/// What the late-night stage is doing to the screen. The raw values are the `lateNight.phase`
/// strings of `abendrot status --json`.
public enum LateNightPhase: String, Sendable, Hashable, CaseIterable {
    case inactive
    case easing
    case held
    case releasing

    /// The phase to report, given what the schedule alone says (`self`). A stage that is not
    /// running (off, warmth off, another mode) or a screen held neutral over it (a timed or
    /// until-sunrise pause, a full-screen pause, a true-colour reveal) is `inactive`.
    public func reported(stageRunning: Bool, screenHeldNeutral: Bool) -> LateNightPhase {
        stageRunning && !screenHeldNeutral ? self : .inactive
    }
}

// MARK: - Night timeline (read model for the Settings anchors strip)

/// One night laid out for display: the anchors, and the colour between them.
public struct NightTimeline: Equatable, Sendable {
    /// Mean solar noon at the Sunset location, opening the night. `end` is the next one.
    public let start: Date
    public let end: Date
    /// When the sun goes down. `start` when it is already down (polar night); nil when it stays up.
    public let sunset: Date?
    /// When the sun is back up. Nil when it never set, or does not rise before `end`.
    public let sunrise: Date?
    /// When the Mac's clock reads the bedtime. Nil without a stage.
    public let bedtime: Date?
    /// The ease into the late-night colour. It ends at bedtime, unless the sun sets less than
    /// the stage's ease length before bedtime: then it starts at sunset and ends that much
    /// later. A sunrise before `deepeningEnd` stops the ease there, short of the late-night
    /// colour. Nil without a stage, or when the sun stays up.
    public let deepeningStart: Date?
    public let deepeningEnd: Date?
    /// The colour on screen at the instant `bedtime`. Nil without one.
    public let bedtimeKelvin: Kelvin?
    /// The colour the night settles at and holds: the late-night level, or the evening's when
    /// that is at least as warm. Nil on a night that never gets there: no stage, no bedtime, the
    /// sun stays up, or it is up again before the ease finishes.
    public let heldKelvin: Kelvin?
    /// When the screen first shows `heldKelvin`: `deepeningEnd`, or `sunset` when the stage adds
    /// nothing to the evening.
    public let heldFrom: Date?
    /// The colour on screen at evenly spaced instants from `start` through `end`.
    public let samples: [Kelvin]
}

extension NightTimeline {

    /// A moment on the strip and the colour the screen shows at it.
    public struct Mark: Equatable, Sendable {
        public let date: Date
        public let kelvin: Kelvin
    }

    /// The Kelvin to print under the Bedtime handle: the held colour, and only when the screen
    /// really shows it at bedtime. Nil when the screen is still on its way there (a late sunset,
    /// a bedtime before sunset) or never arrives.
    public var kelvinUnderBedtime: Kelvin? {
        guard let bedtimeKelvin, bedtimeKelvin == heldKelvin else { return nil }
        return bedtimeKelvin
    }

    /// Where the ease really ends when that is after bedtime, with the late-night colour it
    /// reaches there. Nil on an ordinary night (the handle carries the colour), when the stage
    /// adds nothing to the evening, and when the ease never finishes.
    public var lateEaseEnd: Mark? {
        guard let bedtime, let heldFrom, let heldKelvin, heldFrom == deepeningEnd, heldFrom > bedtime else {
            return nil
        }
        return Mark(date: heldFrom, kelvin: heldKelvin)
    }

    /// The bedtime a pointer `fraction` of the way along the night asks for: minutes after
    /// midnight on `calendar`, to the nearest `step`, inside `range`. The range counts from the
    /// evening's midnight, so 8 PM through 4 AM is `1200...1680`.
    ///
    /// The pointer is held inside the range as it lies on this night before the clock is read.
    /// Reading the clock first cannot tell the two ends apart: the night runs solar noon to solar
    /// noon, so wherever that falls after twelve on the clock (all summer time) the night's last
    /// stretch reads as an afternoon and would send a late bedtime back to the earliest one.
    public func bedtimeMinutes(
        at fraction: Double, in range: ClosedRange<Int>, step: Int, calendar: Calendar
    ) -> Int {
        var instant = start.addingTimeInterval(min(1, max(0, fraction)) * end.timeIntervalSince(start))
        if let earliest = ScheduleResolver.bedtimeInstant(range.lowerBound, from: start, before: end, calendar: calendar),
           let latest = ScheduleResolver.bedtimeInstant(range.upperBound, from: start, before: end, calendar: calendar) {
            if earliest <= latest {
                instant = min(max(instant, earliest), latest)
            } else if instant > latest, instant < earliest {
                // A far-away Sunset location wraps the range around the night's ends, leaving
                // the gap in the middle: take whichever end the pointer is closer to.
                instant = instant.timeIntervalSince(latest) < earliest.timeIntervalSince(instant) ? latest : earliest
            }
        }
        let time = calendar.dateComponents([.hour, .minute], from: instant)
        let minutes = (time.hour ?? 0) * 60 + (time.minute ?? 0)
        let grain = max(1, step)
        let snapped = Int((Double(minutes) / Double(grain)).rounded()) * grain
        return ((snapped % 1440) + 1440) % 1440
    }
}

extension ScheduleResolver {

    /// The night containing `date`, sampled through the same decisions the engine applies, so
    /// what Settings draws is what the screen does.
    public static func nightTimeline(
        containing date: Date,
        latitude: Double,
        longitude: Double,
        configuredWarmth: WarmthLevel,
        warmestPoint: Kelvin,
        lateNight: LateNightStage?,
        calendar: Calendar = .current,
        sampleCount: Int = 97
    ) -> NightTimeline {
        let (noon, nextNoon) = nightCycle(containing: date, longitude: longitude)
        let sunset = firstInstant(
            from: noon, through: nextNoon, latitude: latitude, longitude: longitude, sunIsDown: true
        )
        let sunrise = sunset.flatMap {
            firstInstant(from: $0, through: nextNoon, latitude: latitude, longitude: longitude, sunIsDown: false)
        }
        let bedtime = lateNight.flatMap {
            bedtimeInstant($0.bedtimeMinutes, from: noon, before: nextNoon, calendar: calendar)
        }
        let ramp = lateNight?.rampDuration ?? LateNightStage.defaultRampDuration
        var deepeningStart: Date?
        if let bedtime, let sunset {
            deepeningStart = max(bedtime.addingTimeInterval(-ramp), sunset)
        }

        let deepeningEnd = deepeningStart?.addingTimeInterval(ramp)

        func shown(at instant: Date) -> Kelvin {
            let decision = lateNight.map {
                solarRampDecision(
                    at: instant, latitude: latitude, longitude: longitude,
                    configuredWarmth: configuredWarmth, warmestPoint: warmestPoint,
                    lateNight: $0, calendar: calendar
                )
            } ?? solarRampDecision(
                at: instant, latitude: latitude, longitude: longitude, configuredWarmth: configuredWarmth
            )
            guard decision.isActiveNow else { return .neutral }
            return decision.kelvin ?? decision.target.kelvin(warmestPoint: warmestPoint)
        }

        // The colour the night settles at, and when. The stage only ever warms: a late-night
        // level no warmer than the evening leaves the evening's own colour held from sunset.
        var heldKelvin: Kelvin?
        var heldFrom: Date?
        if let lateNight, bedtime != nil, let sunset {
            let eveningKelvin = configuredWarmth.kelvin(warmestPoint: warmestPoint)
            if lateNight.target < eveningKelvin {
                if let deepeningEnd, sunrise.map({ $0 > deepeningEnd }) ?? true {
                    heldKelvin = lateNight.target
                    heldFrom = deepeningEnd
                }
            } else {
                heldKelvin = eveningKelvin
                heldFrom = sunset
            }
        }

        let count = max(2, sampleCount)
        let step = nextNoon.timeIntervalSince(noon) / Double(count - 1)
        let samples = (0..<count).map { shown(at: noon.addingTimeInterval(Double($0) * step)) }

        return NightTimeline(
            start: noon, end: nextNoon, sunset: sunset, sunrise: sunrise, bedtime: bedtime,
            deepeningStart: deepeningStart,
            deepeningEnd: deepeningEnd,
            bedtimeKelvin: bedtime.map(shown(at:)),
            heldKelvin: heldKelvin,
            heldFrom: heldFrom,
            samples: samples
        )
    }
}
