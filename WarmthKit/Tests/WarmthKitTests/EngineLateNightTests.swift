import Testing
import Foundation
@testable import WarmthKit
@testable import HardwareDDC
@testable import WarmthCore

/// The engine's side of the late-night stage (issue #36): the resolved Kelvin reaches the backends
/// and the published state, pinned displays stay pinned, and with no stage nothing changes.
@Suite("Engine late-night stage")
struct EngineLateNightTests {
    private static let coordinate = TimeZoneCoordinates.Coordinate(latitude: 37.77, longitude: -122.42)
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }
    private static func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private let evening = WarmthLevel(strength: 0.7)
    private let stage = LateNightStage(bedtimeMinutes: 23 * 60, target: Kelvin(1200))

    private func makeEngine(
        at date: Date,
        displays: [DisplayIdentity]
    ) async -> (WarmthEngine, FaultInjectingBackend) {
        let overlay = FaultInjectingBackend(method: .overlay)
        let engine = WarmthEngine.test(backends: [overlay], store: InMemoryDDCSnapshotStore(), displays: displays)
        await engine.setScheduleContextForTesting(date: date, coordinate: Self.coordinate, calendar: Self.calendar)
        await engine.start()
        await engine.setScheduleMode(.followSystemNightShift)
        await engine.setWarmth(evening)
        await engine.setEnabled(true)
        return (engine, overlay)
    }

    @Test("Without a stage the display gets the evening Kelvin and no resolved Kelvin is published")
    func noStageIsUnchanged() async {
        let display = DisplayIdentity.fixture()
        let (engine, overlay) = await makeEngine(at: Self.at(20, 1), displays: [display])
        #expect(await overlay.applied[display] == evening.kelvin(warmestPoint: .everydayWarmest))
        #expect(await engine.state.resolvedKelvin == nil)
        #expect(await engine.state.resolvedWarmth == evening)
    }

    @Test("After bedtime the display gets the late-night Kelvin, and the state says so")
    func plateauReachesBackendAndState() async {
        let display = DisplayIdentity.fixture()
        let (engine, overlay) = await makeEngine(at: Self.at(20, 1), displays: [display])
        await engine.setLateNightStage(stage)
        #expect(await overlay.applied[display] == Kelvin(1200))
        #expect(await engine.state.resolvedKelvin == Kelvin(1200))
        #expect(await engine.state.isScheduleActiveNow)
    }

    @Test("Before the ramp the stage changes nothing on screen")
    func eveningIsUntouched() async {
        let display = DisplayIdentity.fixture()
        let (engine, overlay) = await makeEngine(at: Self.at(19, 20), displays: [display])
        await engine.setLateNightStage(stage)
        #expect(await overlay.applied[display] == evening.kelvin(warmestPoint: .everydayWarmest))
        #expect(await engine.state.resolvedKelvin == nil)
    }

    @Test("The minute tick advances the ramp")
    func tickAdvancesRamp() async {
        let display = DisplayIdentity.fixture()
        let (engine, overlay) = await makeEngine(at: Self.at(19, 22, 15), displays: [display])
        await engine.setLateNightStage(stage)
        let early = await overlay.applied[display]
        await engine.setScheduleContextForTesting(date: Self.at(19, 22, 45), coordinate: Self.coordinate, calendar: Self.calendar)
        await engine.simulateRampTick()
        let late = await overlay.applied[display]
        #expect(early != nil && late != nil)
        #expect((late ?? .neutral) < (early ?? .neutral))
        #expect((late ?? .neutral) > Kelvin(1200))
        #expect(await engine.state.resolvedKelvin == late)
    }

    @Test("A display with its own warmth stays pinned through the night")
    func overriddenDisplayStaysPinned() async {
        let followed = DisplayIdentity.fixture(displayID: 1)
        let pinned = DisplayIdentity.fixture(displayID: 2)
        let (engine, overlay) = await makeEngine(at: Self.at(20, 1), displays: [followed, pinned])
        let own = WarmthLevel(strength: 0.3)
        await engine.setWarmthOverride(true, for: pinned)
        await engine.setWarmth(own, for: pinned)
        await engine.setLateNightStage(stage)
        #expect(await overlay.applied[followed] == Kelvin(1200))
        #expect(await overlay.applied[pinned] == own.kelvin(warmestPoint: .everydayWarmest))
    }

    @Test("Evening at zero: neutral and inactive at dusk, warm after bedtime")
    func eveningZero() async {
        let display = DisplayIdentity.fixture()
        let (engine, overlay) = await makeEngine(at: Self.at(19, 19), displays: [display])
        await engine.setWarmth(.off)
        await engine.setLateNightStage(stage)
        #expect(await engine.state.isScheduleActiveNow == false)
        #expect((await overlay.applied[display] ?? .neutral) == .neutral)

        await engine.setScheduleContextForTesting(date: Self.at(20, 1), coordinate: Self.coordinate, calendar: Self.calendar)
        await engine.simulateRampTick()
        #expect(await engine.state.isScheduleActiveNow)
        #expect(await overlay.applied[display] == Kelvin(1200))
    }

    @Test("Turning the stage off returns to the evening Kelvin in one pass")
    func clearingStageRestoresEvening() async {
        let display = DisplayIdentity.fixture()
        let (engine, overlay) = await makeEngine(at: Self.at(20, 1), displays: [display])
        await engine.setLateNightStage(stage)
        await engine.setLateNightStage(nil)
        #expect(await overlay.applied[display] == evening.kelvin(warmestPoint: .everydayWarmest))
        #expect(await engine.state.resolvedKelvin == nil)
    }

    @Test("The stage's ease length reaches the display: a short ease has not begun where the hour has")
    func easeLengthReachesBackend() async {
        // 22:30 with a 23:00 bedtime: halfway through the default hour, before a 15-minute ease.
        let display = DisplayIdentity.fixture()
        let (engine, overlay) = await makeEngine(at: Self.at(19, 22, 30), displays: [display])
        let eveningKelvin = evening.kelvin(warmestPoint: .everydayWarmest)

        await engine.setLateNightStage(stage)
        let hour = await overlay.applied[display] ?? .neutral
        #expect(hour < eveningKelvin && hour > Kelvin(1200))

        // Only the ease changed, and the engine must still re-apply.
        await engine.setLateNightStage(LateNightStage(bedtimeMinutes: 23 * 60, target: Kelvin(1200), easeMinutes: 15))
        #expect(await overlay.applied[display] == eveningKelvin)
        #expect(await engine.state.resolvedKelvin == nil)

        await engine.setLateNightStage(LateNightStage(bedtimeMinutes: 23 * 60, target: Kelvin(1200), easeMinutes: 120))
        let long = await overlay.applied[display] ?? .neutral
        #expect(long < hour && long > Kelvin(1200))
        #expect(await engine.state.resolvedKelvin == long)
    }

    @Test("Manual mode ignores the stage")
    func manualIgnoresStage() async {
        let display = DisplayIdentity.fixture()
        let (engine, overlay) = await makeEngine(at: Self.at(20, 1), displays: [display])
        await engine.setLateNightStage(stage)
        await engine.setScheduleMode(.alwaysOn)
        #expect(await overlay.applied[display] == evening.kelvin(warmestPoint: .everydayWarmest))
        #expect(await engine.state.resolvedKelvin == nil)
    }
}
