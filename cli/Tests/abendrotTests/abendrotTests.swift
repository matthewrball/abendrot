import XCTest
import ArgumentParser
import WarmthCore
@testable import abendrot
import AbendrotControl

// MARK: - abendrotTests
//
// Unit coverage for the CLI's pure logic: the exclude add/remove set math, the Kelvin→strength
// curve inversion (must track the engine), validation rejects, and the get-value resolver. The live
// transport (CFPreferences + notification + ack) is exercised by the end-to-end round-trip against a
// running app, not here.
final class abendrotTests: XCTestCase {
    // MARK: exclude add/remove math (the CLI computes the FULL replacement set)

    func testExcludeAddProducesSortedUnion() {
        let current = ["com.b.app", "com.a.app"]
        let next = Set(current).union(["com.c.app"]).sorted()
        XCTAssertEqual(next, ["com.a.app", "com.b.app", "com.c.app"])
    }

    func testExcludeAddIsIdempotent() {
        let current = ["com.a.app"]
        let next = Set(current).union(["com.a.app"]).sorted()
        XCTAssertEqual(next, ["com.a.app"])
    }

    func testExcludeRemoveProducesSortedDifference() {
        let current = ["com.a.app", "com.b.app", "com.c.app"]
        let next = Set(current).subtracting(["com.b.app"]).sorted()
        XCTAssertEqual(next, ["com.a.app", "com.c.app"])
    }

    func testExcludeRemoveMissingIsNoOp() {
        let current = ["com.a.app"]
        let next = Set(current).subtracting(["com.z.app"]).sorted()
        XCTAssertEqual(next, ["com.a.app"])
    }

    func testExcludeRemoveUsesValidatedID() throws {
        let current = ["com.a.app", "com.figma.Desktop"]
        let id = try ControlValidation.validatedBundleID("com.figma.Desktop")
        let next = Set(current).subtracting([id]).sorted()
        XCTAssertEqual(next, ["com.a.app"])
    }

    func testHourPatchLastsOneHourAndLeavesTheToggleAlone() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let patch = PauseCommand.hourPatch(at: now)
        XCTAssertEqual(patch.pauseUntil, now.addingTimeInterval(PausePolicy.oneHour))
        XCTAssertEqual(patch.pauseKind, TimedPause.Kind.oneHour.rawValue)
        XCTAssertNil(patch.isEnabled)
        XCTAssertNil(patch.clearPause)
    }

    func testSunrisePatchUsesTheComputedSunrise() throws {
        let now = Date(timeIntervalSince1970: 1_782_057_600)
        let until = try XCTUnwrap(PausePolicy.nextSunrise(
            at: now, latitude: 34.05, longitude: -118.24))
        let patch = try PauseCommand.sunrisePatch(at: now, latitude: 34.05, longitude: -118.24)
        XCTAssertEqual(patch.pauseUntil, until)
        XCTAssertEqual(patch.pauseKind, TimedPause.Kind.untilSunrise.rawValue)
        XCTAssertNil(patch.isEnabled)
    }

    func testSunrisePatchRejectsALocationWithNoSunrise() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 12, day: 21, hour: 12))!
        XCTAssertNil(PausePolicy.nextSunrise(at: now, latitude: 80, longitude: 0))
        assertBadInput(try { _ = try PauseCommand.sunrisePatch(at: now, latitude: 80, longitude: 0) }())
    }

    func testPauseRequiresWarmthOn() {
        XCTAssertNoThrow(try PauseCommand.requireWarmth(true))
        assertBadInput(try PauseCommand.requireWarmth(false))
        assertBadInput(try PauseCommand.requireWarmth(nil))
    }

    func testResumeClearsThePauseWithoutTouchingTheToggle() {
        let patch = PauseCommand.resumePatch()
        XCTAssertEqual(patch.clearPause, true)
        XCTAssertNil(patch.isEnabled)
        XCTAssertNil(patch.pauseUntil)
        XCTAssertNil(patch.pauseKind)
    }

    func testFullscreenPatchAcceptsOnlyOnOrOff() throws {
        XCTAssertEqual(try PauseCommand.fullscreenPatch("on").pausesForFullScreen, true)
        XCTAssertEqual(try PauseCommand.fullscreenPatch("off").pausesForFullScreen, false)
        assertBadInput(try { _ = try PauseCommand.fullscreenPatch("maybe") }())
    }

    // MARK: Kelvin → strength curve (must invert WarmthLevel.kelvin and stay monotonic)

    func testWarmthCurveEndpoints() {
        let warmest = Kelvin.everydayWarmest   // 1900K
        // Neutral target → ~0 strength; warmest target → ~1 strength.
        XCTAssertEqual(WarmthCurve.strength(forKelvin: Kelvin.neutral, warmestPoint: warmest), 0.0, accuracy: 0.02)
        XCTAssertEqual(WarmthCurve.strength(forKelvin: warmest, warmestPoint: warmest), 1.0, accuracy: 0.02)
    }

    func testWarmthCurveIsExactAtTheEnds() {
        // The search used to stop one step short of the end: 1900K came back as
        // 0.9999999701976776 (1 − 2⁻²⁵), and that is what was stored and printed.
        for warmest in [Kelvin.everydayWarmest, Kelvin.warmestSupported, Kelvin(2700)] {
            XCTAssertEqual(WarmthCurve.strength(forKelvin: warmest, warmestPoint: warmest), 1.0)
            XCTAssertEqual(WarmthCurve.strength(forKelvin: Kelvin.warmestSupported, warmestPoint: warmest), 1.0)
            XCTAssertEqual(WarmthCurve.strength(forKelvin: Kelvin.neutral, warmestPoint: warmest), 0.0)
        }
        // In between, the strength returned really produces the Kelvin asked for.
        for kelvin in stride(from: 1900, through: 6500, by: 50) {
            let strength = WarmthCurve.strength(forKelvin: Kelvin(kelvin), warmestPoint: .everydayWarmest)
            XCTAssertEqual(WarmthLevel(strength: strength).kelvin(warmestPoint: .everydayWarmest).value, kelvin)
        }
    }

    func testLateNightWarmthIsStoredExactlyAsAsked() throws {
        for asked in [1.0, 0.0, 0.5, 0.8, 0.1, 0.35] {
            XCTAssertEqual(try LateNightCommand.warmthPatch(strength: asked, kelvin: nil).patch.lateNightWarmthStrength, asked)
        }
        XCTAssertEqual(try LateNightCommand.warmthPatch(strength: nil, kelvin: 1900).patch.lateNightWarmthStrength, 1.0)
        XCTAssertEqual(try LateNightCommand.warmthPatch(strength: nil, kelvin: 1000).patch.lateNightWarmthStrength, 1.0)
        XCTAssertEqual(try LateNightCommand.warmthPatch(strength: nil, kelvin: 6500).patch.lateNightWarmthStrength, 0.0)

        // Through the same CFPreferences write and read the persist path uses, in a throwaway domain.
        let domain = "app.abendrot.cli-tests.\(UUID().uuidString)" as CFString
        defer {
            CFPreferencesSetAppValue("strength" as CFString, nil, domain)
            CFPreferencesAppSynchronize(domain)
        }
        let stored = try XCTUnwrap(try LateNightCommand.warmthPatch(strength: nil, kelvin: 1900).patch.lateNightWarmthStrength)
        CFPreferencesSetAppValue("strength" as CFString, stored as CFNumber, domain)
        CFPreferencesAppSynchronize(domain)
        let read = (CFPreferencesCopyAppValue("strength" as CFString, domain) as? NSNumber)?.doubleValue
        XCTAssertEqual(read, 1.0)
        let report = LateNightSnapshot.configured(
            enabled: true, bedtimeMinutes: 1380, warmthStrength: read, cozy: false, easeMinutes: 60
        )
        XCTAssertEqual(report.warmthStrength, 1.0)
        XCTAssertEqual(String(describing: report.warmthStrength), "1.0")
    }

    func testLateNightReportsEveryPhase() {
        func stage(_ phase: String?) -> LateNightSnapshot {
            LateNightSnapshot.configured(
                enabled: true, bedtimeMinutes: 1380, warmthStrength: 1, cozy: false, easeMinutes: 60, phase: phase
            )
        }
        func now(_ phase: String?) -> String? {
            LateNightReport.human(stage: stage(phase), mode: .sunset)
                .split(separator: "\n").first { $0.hasPrefix("Now:") }.map(String.init)
        }
        XCTAssertEqual(now("easing"), "Now:        easing")
        XCTAssertEqual(now("held"), "Now:        holding the late-night colour")
        XCTAssertEqual(now("releasing"), "Now:        releasing back to day")
        XCTAssertEqual(now("inactive"), "Now:        not active")
        XCTAssertNil(now(nil))
        XCTAssertNil(now("somethingNew"), "an unknown phase prints no Now line")

        let plan = "Late night: " + LateNightReport.plan(stage(nil))
        XCTAssertEqual(StatusReport.lateNightLine(stage: stage("easing"), mode: .sunset), plan + " (easing now)")
        XCTAssertEqual(StatusReport.lateNightLine(stage: stage("held"), mode: .sunset), plan + " (holding now)")
        XCTAssertEqual(StatusReport.lateNightLine(stage: stage("releasing"), mode: .sunset), plan + " (releasing now)")
        XCTAssertEqual(StatusReport.lateNightLine(stage: stage("inactive"), mode: .sunset), plan)
        XCTAssertEqual(StatusReport.lateNightLine(stage: stage("somethingNew"), mode: .sunset), plan)
    }

    func testCorruptStoredLateNightNumbersReportSanely() {
        // What NSNumber.intValue / doubleValue hand back for `defaults write … -float -1e30`.
        let stage = LateNightSnapshot.configured(
            enabled: true, bedtimeMinutes: .min, warmthStrength: -1e30, cozy: false, easeMinutes: .min
        )
        XCTAssertFalse(LateNightReport.human(stage: stage, mode: .sunset).isEmpty)
        XCTAssertNotNil(StatusReport.lateNightLine(stage: stage, mode: .sunset))
        XCTAssertEqual(stage.easeMinutes, 15)
        XCTAssertEqual(stage.warmthStrength, 1)
        XCTAssertEqual(NSNumber(value: -1e30 as Float).intValue, Int.min)
    }

    func testWarmthCurveTracksEngineForwardMapping() {
        // For a few strengths, invert the Kelvin the engine would produce and recover the strength.
        let warmest = Kelvin(1900)
        for s in [0.1, 0.35, 0.6, 0.85] {
            let kelvin = WarmthLevel(strength: s).kelvin(warmestPoint: warmest)
            let recovered = WarmthCurve.strength(forKelvin: kelvin, warmestPoint: warmest)
            XCTAssertEqual(recovered, s, accuracy: 0.02, "curve did not invert at strength \(s)")
        }
    }

    func testWarmthCurveIsMonotonic() {
        let warmest = Kelvin(1900)
        // Warmer (lower K) target ⇒ higher strength.
        let coolStrength = WarmthCurve.strength(forKelvin: Kelvin(4000), warmestPoint: warmest)
        let warmStrength = WarmthCurve.strength(forKelvin: Kelvin(2200), warmestPoint: warmest)
        XCTAssertLessThan(coolStrength, warmStrength)
    }

    // MARK: validation rejects (shared with the app)

    func testValidationRejectsOutOfRange() {
        XCTAssertThrowsError(try ControlValidation.validatedStrength(50))
        XCTAssertThrowsError(try ControlValidation.validatedKelvin(50))
        XCTAssertThrowsError(try ControlValidation.validatedRevealMode("foo"))
        XCTAssertThrowsError(try ControlValidation.validatedRevealHold(.infinity))
        XCTAssertThrowsError(try ControlValidation.validatedRevealHold(301))
        XCTAssertNoThrow(try ControlValidation.validatedStrength(0.8))
        XCTAssertNoThrow(try ControlValidation.validatedKelvin(1900))
        XCTAssertNoThrow(try ControlValidation.validatedRevealMode("toggle"))
        XCTAssertNoThrow(try ControlValidation.validatedRevealHold(10))
    }

    func testModeParsingRejectsUnknown() {
        XCTAssertNil(ControlScheduleMode(rawValue: "foo"))
        XCTAssertEqual(ControlScheduleMode(rawValue: "always-on"), .alwaysOn)
        XCTAssertEqual(ControlScheduleMode(rawValue: "off"), .off)
        XCTAssertEqual(ControlScheduleMode(rawValue: "sunset"), .sunset)
    }

    // MARK: cozy on|off parsing (case-insensitive; rejects anything else)

    func testCozyOnOffParsing() {
        XCTAssertEqual(boolFromOnOff("on"), true)
        XCTAssertEqual(boolFromOnOff("off"), false)
        XCTAssertEqual(boolFromOnOff("ON"), true)
        XCTAssertEqual(boolFromOnOff("Off"), false)
        // Anything else is rejected → the command throws exit 2.
        XCTAssertNil(boolFromOnOff("maybe"))
        XCTAssertNil(boolFromOnOff("true"))
        XCTAssertNil(boolFromOnOff(""))
    }

    func testCozyPatchCarriesOnlyCozy() {
        // `cozy on` must send a cozy-only patch (the app routes it through setCozy) — not a raw
        // max-warmth write, so the screen warmth is held rather than left to drift.
        let on = SettingsPatch(cozy: true)
        XCTAssertEqual(on.cozy, true)
        XCTAssertNil(on.warmestPointKelvin)
        XCTAssertFalse(on.isEmpty)
        let off = SettingsPatch(cozy: false)
        XCTAssertEqual(off.cozy, false)
    }

    func testWarmthPreferenceKeepsManualCozySeparateFromNormalModes() {
        XCTAssertEqual(Control.warmthPreferenceKey(mode: .alwaysOn, cozy: true),
                       PreferenceKey.manualCozyWarmthStrength)
        XCTAssertEqual(Control.warmthPreferenceKey(mode: .alwaysOn, cozy: false),
                       PreferenceKey.manualWarmthStrength)
        for mode in [ControlScheduleMode.sunset, .off] {
            for cozy in [false, true] {
                XCTAssertEqual(Control.warmthPreferenceKey(mode: mode, cozy: cozy),
                               PreferenceKey.globalWarmthStrength)
            }
        }
    }

    // MARK: set location argument shape

    func testSetLocationRejectsAutoWithCoordinates() throws {
        let command = try SetLocation.parse(["1", "2", "--auto"])
        assertBadInput(try command.run())
    }

    func testSetLocationRejectsPartialCoordinates() throws {
        let command = try SetLocation.parse(["1"])
        assertBadInput(try command.run())
    }

    // MARK: exclude bundle-id validation

    func testValidatedBundleIDAcceptsRealIDs() throws {
        XCTAssertEqual(try ControlValidation.validatedBundleID("com.apple.dt.Xcode"), "com.apple.dt.Xcode")
        XCTAssertEqual(try ControlValidation.validatedBundleID("com.example.App-2"), "com.example.App-2")
        XCTAssertEqual(try ControlValidation.validatedBundleID("a.b"), "a.b")
    }

    func testValidatedBundleIDRejectsHostileInput() {
        let overlength = "com." + String(repeating: "a", count: ControlValidation.maximumBundleIDBytes)
        for bad in [
            "",
            "   ",
            "\t\n",
            "frobnicate",
            "../../evil",
            "com..example",
            ".com.example",
            "com.example.",
            "com/example",
            "com\\example",
            "com.example\nbad",
            "com.example\u{0001}bad",
            "com.example;rm",
            "com.bad id",
            "com.exämple.App",
            "com．example.App",
            overlength,
        ] {
            XCTAssertThrowsError(try ControlValidation.validatedBundleID(bad), "accepted \(bad.debugDescription)")
        }
    }

    func testPersistedBundleIDNormalizationSelfHealsNextMutationInput() {
        XCTAssertEqual(
            ControlValidation.normalizedPersistedBundleIDs([
                "../../evil",
                "com.apple.dt.Xcode",
                "com.apple.dt.Xcode",
                "org.example.App-2",
                "com.example;rm",
            ]),
            ["com.apple.dt.Xcode", "org.example.App-2"]
        )
    }

    // MARK: get --json structured shapes (lossless warmth, structured location)

    func testGetReportJSONObjectRejectsUnknownKey() {
        XCTAssertNil(GetReport.jsonObject(forKey: "nonsense"))
    }

    func testGetReportJSONObjectModeIsSimpleShape() {
        // Non-special keys keep the {key:value} shape.
        let mode = GetReport.jsonObject(forKey: "mode")
        XCTAssertNotNil(mode)
        XCTAssertTrue(mode!.hasPrefix("{\"mode\":\""), "got \(mode!)")
    }

    func testCozyDerivationRuleMatchesCeiling() {
        // The CLI `get cozy` / status surfacing derive cozy from the persisted ceiling via the shared
        // schema helper — on exactly when the warmest point sits below the everyday 1900K cap.
        XCTAssertTrue(ControlStateSnapshot.isCozy(warmestPointKelvin: 500))
        XCTAssertTrue(ControlStateSnapshot.isCozy(warmestPointKelvin: 1899))
        XCTAssertFalse(ControlStateSnapshot.isCozy(warmestPointKelvin: 1900))
        XCTAssertFalse(ControlStateSnapshot.isCozy(warmestPointKelvin: 2700))
    }

    func testGetReportJSONObjectCozyIsQuotedOnOff() {
        // `get cozy --json` keeps the simple {key:value} shape, value quoted as a string ("on"/"off").
        let cozy = GetReport.jsonObject(forKey: "cozy")
        XCTAssertNotNil(cozy)
        XCTAssertTrue(cozy!.hasPrefix("{\"cozy\":\""), "got \(cozy!)")
        XCTAssertTrue(cozy!.contains("on") || cozy!.contains("off"), "got \(cozy!)")
    }

    // MARK: get-value resolver

    func testGetReportRejectsUnknownKey() {
        XCTAssertNil(GetReport.value(forKey: "nonsense"))
    }

    func testGetReportJSONValueQuotingRules() {
        XCTAssertEqual(GetReport.jsonValue("true"), "true")
        XCTAssertEqual(GetReport.jsonValue("false"), "false")
        XCTAssertEqual(GetReport.jsonValue("0.80"), "0.80")
        XCTAssertEqual(GetReport.jsonValue("sunset"), "\"sunset\"")
        XCTAssertEqual(GetReport.jsonValue("auto"), "\"auto\"")
    }

    // MARK: state.json reads are bounded and no-follow

    func testReadLivenessRejectsStateSymlink() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let referent = directory.appendingPathComponent("referent.json")
        let state = directory.appendingPathComponent("state.json")
        try JSONEncoder().encode(liveness()).write(to: referent)
        try FileManager.default.createSymbolicLink(atPath: state.path, withDestinationPath: referent.path)

        XCTAssertNil(Control.readLiveness(fileURL: state))
    }

    func testReadSnapshotRejectsCorruptStateFile() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = directory.appendingPathComponent("state.json")
        try Data("not json".utf8).write(to: state)

        XCTAssertNil(Control.readSnapshot(fileURL: state))
    }

    func testReadLivenessRejectsOversizedStateFile() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = directory.appendingPathComponent("state.json")
        try Data(repeating: 0, count: SecureAtomicFileWriter.maxSnapshotBytes + 1).write(to: state)

        XCTAssertNil(Control.readLiveness(fileURL: state))
    }

    // MARK: late-night (Sunset mode's second stage)

    private func stage(
        enabled: Bool = true, bedtime: Int = 1380, strength: Double = 1, cozy: Bool = false,
        ease: Int? = 60, phase: String? = nil
    ) -> LateNightSnapshot {
        LateNightSnapshot(enabled: enabled, bedtimeMinutes: bedtime, warmthStrength: strength,
                          cozy: cozy, easeMinutes: ease, phase: phase)
    }

    func testLateNightCommandsParse() throws {
        XCTAssertTrue(try Abendrot.parseAsRoot(["late-night"]) is LateNightStatus)
        XCTAssertTrue(try Abendrot.parseAsRoot(["late-night", "--json"]) is LateNightStatus)
        XCTAssertTrue(try Abendrot.parseAsRoot(["late-night", "status", "--json"]) is LateNightStatus)
        XCTAssertTrue(try Abendrot.parseAsRoot(["late-night", "on"]) is LateNightOn)
        XCTAssertTrue(try Abendrot.parseAsRoot(["late-night", "off"]) is LateNightOff)
        XCTAssertTrue(try Abendrot.parseAsRoot(["late-night", "bedtime", "23:30"]) is LateNightBedtime)
        XCTAssertTrue(try Abendrot.parseAsRoot(["late-night", "warmth", "0.8"]) is LateNightWarmth)
        XCTAssertTrue(try Abendrot.parseAsRoot(["late-night", "warmth", "--kelvin", "2200"]) is LateNightWarmth)
        XCTAssertTrue(try Abendrot.parseAsRoot(["late-night", "cozy", "on"]) is LateNightCozy)
        XCTAssertTrue(try Abendrot.parseAsRoot(["late-night", "ease", "90"]) is LateNightEase)
        XCTAssertThrowsError(try Abendrot.parseAsRoot(["late-night", "maybe"]))
        XCTAssertThrowsError(try Abendrot.parseAsRoot(["late-night", "ease", "soon"]))
        XCTAssertThrowsError(try Abendrot.parseAsRoot(["late-night", "bedtime"]))
    }

    func testLateNightOnOffPatchCarriesOnlyTheToggle() {
        let on = LateNightCommand.enabledPatch(true)
        XCTAssertEqual(on, SettingsPatch(lateNightEnabled: true))
        XCTAssertNil(on.isEnabled, "late-night on must not touch the master toggle")
        XCTAssertNil(on.scheduleMode, "late-night on must not switch the mode")
        XCTAssertEqual(LateNightCommand.enabledPatch(false), SettingsPatch(lateNightEnabled: false))
    }

    func testLateNightBedtimePatchAcceptsOfferedTimes() throws {
        XCTAssertEqual(try LateNightCommand.bedtimePatch("23:30"), SettingsPatch(bedtimeMinutes: 1410))
        XCTAssertEqual(try LateNightCommand.bedtimePatch("20:00").bedtimeMinutes, 1200)
        XCTAssertEqual(try LateNightCommand.bedtimePatch("00:30").bedtimeMinutes, 30)
        XCTAssertEqual(try LateNightCommand.bedtimePatch("04:00").bedtimeMinutes, 240)
        XCTAssertEqual(try LateNightCommand.bedtimePatch("11pm").bedtimeMinutes, 1380)
        XCTAssertEqual(try LateNightCommand.bedtimePatch("11:30pm").bedtimeMinutes, 1410)
        XCTAssertEqual(try LateNightCommand.bedtimePatch("12:30AM").bedtimeMinutes, 30)
    }

    func testLateNightBedtimePatchRejectsOffStepOutOfRangeAndGarbage() {
        for raw in ["23:15", "22:45", "11:10pm"] {            // off the half hour
            assertBadInput(try { _ = try LateNightCommand.bedtimePatch(raw) }())
        }
        for raw in ["19:30", "04:30", "12:00", "7pm", "5am"] {   // outside 20:00–04:00
            assertBadInput(try { _ = try LateNightCommand.bedtimePatch(raw) }())
        }
        for raw in ["", "late", "23", "2300", "24:00", "23:60", "13pm", "23:00pm", "11p", "23:00:00"] {
            assertBadInput(try { _ = try LateNightCommand.bedtimePatch(raw) }())
        }
    }

    func testLateNightCozyPatchAcceptsOnlyOnOrOff() throws {
        XCTAssertEqual(try LateNightCommand.cozyPatch("on"), SettingsPatch(lateNightCozy: true))
        XCTAssertEqual(try LateNightCommand.cozyPatch("OFF"), SettingsPatch(lateNightCozy: false))
        XCTAssertNil(try LateNightCommand.cozyPatch("on").cozy, "must not flip the everyday Cozy mode")
        assertBadInput(try { _ = try LateNightCommand.cozyPatch("maybe") }())
    }

    func testLateNightWarmthPatchFromStrength() throws {
        let result = try LateNightCommand.warmthPatch(strength: 0.5, kelvin: nil)
        XCTAssertEqual(result.patch, SettingsPatch(lateNightWarmthStrength: 0.5))
        XCTAssertNil(result.note)
        XCTAssertNil(result.patch.lateNightCozy, "the Settings slider leaves 'Switch to Cozy' alone; so does this")
        XCTAssertNil(result.patch.globalWarmthStrength, "must not touch the evening warmth")
        XCTAssertEqual(try LateNightCommand.warmthPatch(strength: 0, kelvin: nil).patch.lateNightWarmthStrength, 0)
        XCTAssertEqual(try LateNightCommand.warmthPatch(strength: 1, kelvin: nil).patch.lateNightWarmthStrength, 1)
        assertBadInput(try { _ = try LateNightCommand.warmthPatch(strength: 1.5, kelvin: nil) }())
        assertBadInput(try { _ = try LateNightCommand.warmthPatch(strength: -0.1, kelvin: nil) }())
        assertBadInput(try { _ = try LateNightCommand.warmthPatch(strength: .nan, kelvin: nil) }())
    }

    func testLateNightWarmthPatchFromKelvinUsesTheEverydayCurve() throws {
        for target in [1900, 2200, 2700, 3400, 5000] {
            let result = try LateNightCommand.warmthPatch(strength: nil, kelvin: target)
            let strength = try XCTUnwrap(result.patch.lateNightWarmthStrength)
            let landed = WarmthLevel(strength: strength).kelvin(warmestPoint: .everydayWarmest).value
            XCTAssertEqual(landed, target, accuracy: 15, "\(target)K")
            XCTAssertNil(result.note)
        }
        // Warmer than the slider reaches: lands on its warmest end and says how to go further.
        let floor = try LateNightCommand.warmthPatch(strength: nil, kelvin: 1200)
        XCTAssertEqual(try XCTUnwrap(floor.patch.lateNightWarmthStrength), 1, accuracy: 0.001)
        XCTAssertTrue(try XCTUnwrap(floor.note).contains("late-night cozy on"))
        assertBadInput(try { _ = try LateNightCommand.warmthPatch(strength: nil, kelvin: 100) }())
        assertBadInput(try { _ = try LateNightCommand.warmthPatch(strength: nil, kelvin: 9000) }())
    }

    func testLateNightWarmthPatchRejectsBothOrNeither() {
        assertBadInput(try { _ = try LateNightCommand.warmthPatch(strength: 0.5, kelvin: 2200) }())
        assertBadInput(try { _ = try LateNightCommand.warmthPatch(strength: nil, kelvin: nil) }())
    }

    func testLateNightEasePatchAcceptsOnlyTheAllowedLengths() throws {
        for minutes in [15, 30, 45, 60, 90, 120] {
            XCTAssertEqual(try LateNightCommand.easePatch(minutes), SettingsPatch(lateNightEaseMinutes: minutes))
        }
        for minutes in [0, -30, 10, 20, 50, 75, 100, 121, 180] {
            assertBadInput(try { _ = try LateNightCommand.easePatch(minutes) }())
        }
    }

    func testLateNightNotesSayWhenAChangeWaitsOnSomethingElse() {
        // Sunset mode, stage on, nothing in the way: nothing to add.
        XCTAssertEqual(LateNightCommand.notes(for: SettingsPatch(bedtimeMinutes: 1380), mode: .sunset, stage: stage()), [])
        // Another mode: saved, but says where it acts.
        let manual = LateNightCommand.notes(for: SettingsPatch(lateNightEnabled: true), mode: .alwaysOn, stage: stage(enabled: false))
        XCTAssertEqual(manual.count, 1)
        XCTAssertTrue(manual[0].contains("Sunset mode"), manual[0])
        XCTAssertTrue(manual[0].contains("always-on"), manual[0])
        // Stage off: a bedtime is saved for later. Turning it on or off needs no such note.
        let off = LateNightCommand.notes(for: SettingsPatch(bedtimeMinutes: 1380), mode: .sunset, stage: stage(enabled: false))
        XCTAssertTrue(off.contains { $0.contains("late-night on") }, "\(off)")
        XCTAssertEqual(LateNightCommand.notes(for: SettingsPatch(lateNightEnabled: true), mode: .sunset, stage: stage(enabled: false)), [])
        XCTAssertEqual(LateNightCommand.notes(for: SettingsPatch(lateNightEnabled: false), mode: .sunset, stage: stage()), [])
        // Warmth while 'Switch to Cozy at bedtime' is on: saved, Cozy still wins, as in Settings.
        let cozy = LateNightCommand.notes(for: SettingsPatch(lateNightWarmthStrength: 0.5), mode: .sunset, stage: stage(cozy: true))
        XCTAssertTrue(cozy.contains { $0.contains("late-night cozy off") }, "\(cozy)")
        XCTAssertEqual(LateNightCommand.notes(for: SettingsPatch(lateNightWarmthStrength: 0.5), mode: .sunset, stage: stage()), [])
    }

    func testGetReportLateNightKeys() {
        let night = stage(bedtime: 30, strength: 0.5, cozy: false, ease: 90)
        XCTAssertEqual(GetReport.lateNightValue(forKey: "late-night", stage: night)?.value, "on")
        XCTAssertEqual(GetReport.lateNightValue(forKey: "late-night", stage: stage(enabled: false))?.value, "off")
        XCTAssertEqual(GetReport.lateNightValue(forKey: "bedtime", stage: night)?.value, "00:30")
        XCTAssertEqual(GetReport.lateNightValue(forKey: "late-night-warmth", stage: night)?.value, "0.50")
        XCTAssertEqual(GetReport.lateNightValue(forKey: "late-night-kelvin", stage: night)?.value, String(night.kelvin))
        XCTAssertEqual(GetReport.lateNightValue(forKey: "late-night-cozy", stage: night)?.value, "off")
        XCTAssertEqual(GetReport.lateNightValue(forKey: "late-night-ease", stage: night)?.value, "90")
        XCTAssertEqual(GetReport.lateNightValue(forKey: "late-night-ease", stage: stage(ease: nil))?.value, "60")
        XCTAssertNil(GetReport.lateNightValue(forKey: "late-night-nonsense", stage: night))
        XCTAssertNil(GetReport.lateNightValue(forKey: "warmth", stage: night))
        // Cozy at bedtime reports Cozy's floor and keeps the saved strength.
        let cozy = stage(strength: 0.5, cozy: true)
        XCTAssertEqual(GetReport.lateNightValue(forKey: "late-night-kelvin", stage: cozy)?.value,
                       String(Kelvin.warmestSupported.value))
        XCTAssertEqual(GetReport.lateNightValue(forKey: "late-night-warmth", stage: cozy)?.value, "0.50")
    }

    func testGetResolvesEveryDocumentedKey() {
        // Every key the help text names resolves, against whatever is saved on this Mac (read-only).
        XCTAssertEqual(GetReport.keys.suffix(6), [
            "late-night", "bedtime", "late-night-warmth", "late-night-kelvin", "late-night-cozy", "late-night-ease",
        ])
        for key in GetReport.keys {
            XCTAssertNotNil(GetReport.value(forKey: key), key)
            XCTAssertNotNil(GetReport.jsonObject(forKey: key), key)
        }
        XCTAssertTrue(GetReport.jsonObject(forKey: "bedtime")!.hasPrefix("{\"bedtime\":\""))
        XCTAssertTrue(GetReport.jsonObject(forKey: "late-night")!.hasPrefix("{\"late-night\":\"o"))
        XCTAssertTrue(GetReport.jsonObject(forKey: "late-night-ease")!.hasPrefix("{\"late-night-ease\":"))
        XCTAssertFalse(GetReport.jsonObject(forKey: "late-night-ease")!.contains("\":\""), "ease is a bare number")
    }

    func testLateNightReportJSONShape() throws {
        let night = stage(bedtime: 1410, strength: 0.9, cozy: false, ease: 45, phase: "easing")
        let json = LateNightReport.json(stage: night, mode: .sunset)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), [
            "enabled", "bedtime", "bedtimeMinutes", "warmthStrength", "kelvin", "cozy", "easeMinutes",
            "phase", "scheduleMode", "activeInCurrentMode",
        ])
        XCTAssertEqual(object["enabled"] as? Bool, true)
        XCTAssertEqual(object["bedtime"] as? String, "23:30")
        XCTAssertEqual(object["bedtimeMinutes"] as? Int, 1410)
        XCTAssertEqual(object["warmthStrength"] as? Double, 0.9)
        XCTAssertEqual(object["kelvin"] as? Int, night.kelvin)
        XCTAssertEqual(object["cozy"] as? Bool, false)
        XCTAssertEqual(object["easeMinutes"] as? Int, 45)
        XCTAssertEqual(object["phase"] as? String, "easing")
        XCTAssertEqual(object["scheduleMode"] as? String, "sunset")
        XCTAssertEqual(object["activeInCurrentMode"] as? Bool, true)

        // App closed: no phase key. Another mode, or the stage off: not active.
        let closed = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(LateNightReport.json(stage: stage(), mode: .alwaysOn).utf8)) as? [String: Any])
        XCTAssertNil(closed["phase"])
        XCTAssertEqual(closed["scheduleMode"] as? String, "always-on")
        XCTAssertEqual(closed["activeInCurrentMode"] as? Bool, false)
        let disabled = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(LateNightReport.json(stage: stage(enabled: false), mode: .sunset).utf8)) as? [String: Any])
        XCTAssertEqual(disabled["activeInCurrentMode"] as? Bool, false)
    }

    func testLateNightReportHumanText() {
        let text = LateNightReport.human(stage: stage(bedtime: 1410, strength: 1, ease: 90), mode: .sunset)
        XCTAssertTrue(text.contains("Late night: on"), text)
        XCTAssertTrue(text.contains("23:30"), text)
        XCTAssertTrue(text.contains("1 hr 30 min"), text)
        XCTAssertTrue(text.contains("1900K"), text)
        XCTAssertFalse(text.contains("Sunset mode"), text)

        let manual = LateNightReport.human(stage: stage(cozy: true), mode: .alwaysOn)
        XCTAssertTrue(manual.contains("takes effect in Sunset mode"), manual)
        XCTAssertTrue(manual.contains("Cozy"), manual)
        XCTAssertTrue(LateNightReport.human(stage: stage(enabled: false), mode: .sunset).contains("Late night: off"))
        XCTAssertTrue(LateNightReport.human(stage: stage(phase: "held"), mode: .sunset).contains("holding"))
    }

    func testStatusGainsALateNightLineOnlyWhenTheStageIsOn() {
        func snapshot(_ lateNight: LateNightSnapshot?, mode: ControlScheduleMode = .sunset) -> ControlStateSnapshot {
            ControlStateSnapshot(
                appVersion: "1.0.2", appBuild: "7", pid: 1, appLaunchID: "L", updatedAt: Date(),
                lastAppliedRequestID: nil, isEnabled: true, scheduleMode: mode, isScheduleActiveNow: true,
                isRevealing: false, globalWarmthStrength: 0.7, globalKelvin: 2412, warmestPointKelvin: 1900,
                revealMode: "hold", excludedApps: [], lateNight: lateNight, displays: []
            )
        }
        XCTAssertFalse(StatusReport.human(snapshot: snapshot(nil), running: true).contains("Late night"))
        XCTAssertFalse(StatusReport.human(snapshot: snapshot(stage(enabled: false)), running: true).contains("Late night"))
        let on = StatusReport.human(snapshot: snapshot(stage(bedtime: 1410, ease: 30, phase: "easing")), running: true)
        XCTAssertTrue(on.contains("Late night: bedtime 23:30"), on)
        XCTAssertTrue(on.contains("30 min"), on)
        XCTAssertTrue(on.contains("easing now"), on)
        // A snapshot left by an app that died keeps its last phase; it must not be reported.
        let stale = snapshot(stage(bedtime: 1410, ease: 30, phase: "easing"))
        XCTAssertFalse(StatusReport.human(snapshot: stale, running: false).contains("easing now"))
        XCTAssertFalse(StatusReport.json(snapshot: stale, running: false).contains("\"phase\""))
        XCTAssertTrue(StatusReport.json(snapshot: stale, running: true).contains("\"phase\":\"easing\""))
        let manual = StatusReport.human(snapshot: snapshot(stage(), mode: .alwaysOn), running: true)
        XCTAssertTrue(manual.contains("takes effect in Sunset mode"), manual)

        // status --json carries the whole object, and an older app's snapshot simply has none.
        let json = StatusReport.json(snapshot: snapshot(stage(bedtime: 1410, ease: 30)), running: true)
        let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        let lateNight = object?["lateNight"] as? [String: Any]
        XCTAssertEqual(lateNight?["bedtime"] as? String, "23:30")
        XCTAssertEqual(lateNight?["easeMinutes"] as? Int, 30)
        let older = try? JSONSerialization.jsonObject(
            with: Data(StatusReport.json(snapshot: snapshot(nil), running: true).utf8)) as? [String: Any]
        XCTAssertNil(older?["lateNight"])
    }

    private func assertBadInput(_ expression: @autoclosure () throws -> Void, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            XCTAssertEqual(error as? ExitCode, ExitCode(CLIExit.badInput), file: file, line: line)
        }
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("abendrot-cli-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }

    private func liveness() -> ControlLiveness {
        ControlLiveness(
            schemaVersion: AbendrotControl.schemaVersion,
            pid: ProcessInfo.processInfo.processIdentifier,
            appLaunchID: UUID().uuidString,
            updatedAt: Date(),
            lastAppliedRequestID: nil
        )
    }
}
