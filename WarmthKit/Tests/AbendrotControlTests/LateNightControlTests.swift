import XCTest
import WarmthCore
@testable import AbendrotControl

// MARK: - LateNightControlTests
//
// The control surface of Sunset mode's late-night stage (issue #36): the preference keys, the
// validators the CLI and the app both run, the patch fields, and the optional snapshot object.
final class LateNightControlTests: XCTestCase {

    // MARK: Keys

    func testLateNightPreferenceKeysEqualTheirLiteralStrings() {
        XCTAssertEqual(PreferenceKey.lateNightEnabled, "lateNightEnabled")
        XCTAssertEqual(PreferenceKey.bedtimeMinutes, "bedtimeMinutes")
        XCTAssertEqual(PreferenceKey.lateNightWarmthStrength, "lateNightWarmthStrength")
        XCTAssertEqual(PreferenceKey.lateNightCozy, "lateNightCozy")
        XCTAssertEqual(PreferenceKey.lateNightEaseMinutes, "lateNightEaseMinutes")
    }

    // MARK: Bedtime validation

    func testValidatedBedtimeAcceptsEveryOfferedBedtime() throws {
        // 20:00 through 04:00 in half-hour steps is 17 bedtimes.
        var accepted: [Int] = []
        for minutes in 0..<1440 where (try? ControlValidation.validatedBedtimeMinutes(minutes)) != nil {
            accepted.append(minutes)
        }
        XCTAssertEqual(accepted.count, 17)
        XCTAssertEqual(accepted.filter { $0 < 720 }, [0, 30, 60, 90, 120, 150, 180, 210, 240])
        XCTAssertEqual(accepted.filter { $0 >= 720 }, [1200, 1230, 1260, 1290, 1320, 1350, 1380, 1410])
    }

    func testValidatedBedtimeRejectsOutOfRangeLoudly() {
        for minutes in [19 * 60 + 30, 4 * 60 + 30, 12 * 60, 5 * 60, -30, 1440, 1680] {
            XCTAssertThrowsError(try ControlValidation.validatedBedtimeMinutes(minutes), "\(minutes)") { error in
                let message = (error as? ControlError)?.description ?? ""
                XCTAssertTrue(message.contains("20:00"), message)
                XCTAssertTrue(message.contains("04:00"), message)
            }
        }
    }

    func testValidatedBedtimeRejectsOffStepRatherThanSnapping() {
        for minutes in [23 * 60 + 15, 23 * 60 + 1, 20 * 60 + 29, 45] {
            XCTAssertThrowsError(try ControlValidation.validatedBedtimeMinutes(minutes), "\(minutes)") { error in
                let message = (error as? ControlError)?.description ?? ""
                XCTAssertTrue(message.contains("30-minute"), message)
            }
        }
    }

    func testBedtimeRulesAreTheCoreOnes() {
        // One definition: the validator must agree with WarmthCore for every minute of the day.
        for minutes in -5..<1445 {
            XCTAssertEqual(
                (try? ControlValidation.validatedBedtimeMinutes(minutes)) != nil,
                LateNightStage.isAllowedBedtime(minutesOfDay: minutes),
                "\(minutes)"
            )
        }
    }

    // MARK: Bedtime parsing

    func testParsedBedtimeAccepts24HourClock() throws {
        XCTAssertEqual(try ControlValidation.parsedBedtime("23:00"), 1380)
        XCTAssertEqual(try ControlValidation.parsedBedtime("23:30"), 1410)
        XCTAssertEqual(try ControlValidation.parsedBedtime("20:00"), 1200)
        XCTAssertEqual(try ControlValidation.parsedBedtime("00:00"), 0)
        XCTAssertEqual(try ControlValidation.parsedBedtime("0:30"), 30)
        XCTAssertEqual(try ControlValidation.parsedBedtime("04:00"), 240)
        XCTAssertEqual(try ControlValidation.parsedBedtime("4:00"), 240)
        XCTAssertEqual(try ControlValidation.parsedBedtime(" 22:30 "), 1350)
    }

    func testParsedBedtimeAccepts12HourForms() throws {
        XCTAssertEqual(try ControlValidation.parsedBedtime("11pm"), 1380)
        XCTAssertEqual(try ControlValidation.parsedBedtime("11:30pm"), 1410)
        XCTAssertEqual(try ControlValidation.parsedBedtime("11:30 PM"), 1410)
        XCTAssertEqual(try ControlValidation.parsedBedtime("8PM"), 1200)
        XCTAssertEqual(try ControlValidation.parsedBedtime("12am"), 0)
        XCTAssertEqual(try ControlValidation.parsedBedtime("12:30am"), 30)
        XCTAssertEqual(try ControlValidation.parsedBedtime("1am"), 60)
        XCTAssertEqual(try ControlValidation.parsedBedtime("4:00am"), 240)
        XCTAssertEqual(try ControlValidation.parsedBedtime("10 p.m."), 1320)
    }

    func testParsedBedtimeRejectsValidClockTimesOutsideTheRules() {
        // Well-formed times the app does not offer: out of range, then off the half hour.
        for raw in ["19:30", "12:00", "04:30", "7pm", "5am", "12pm", "noon"] {
            XCTAssertThrowsError(try ControlValidation.parsedBedtime(raw), raw)
        }
        for raw in ["23:15", "22:45", "11:10pm", "00:01"] {
            XCTAssertThrowsError(try ControlValidation.parsedBedtime(raw), raw) { error in
                XCTAssertTrue(((error as? ControlError)?.description ?? "").contains("30-minute"), raw)
            }
        }
    }

    func testParsedBedtimeRejectsGarbage() {
        let garbage = [
            "", " ", "bedtime", "23", "11", "2300", "23:0", "23:000", "24:00", "25:00", "23:60", "-1:00",
            "23:00:00", "13pm", "0pm", "0am", "23:00pm", "11:30xm", "11p", "pm", ":30", "23:", "１１pm",
            "11pm; rm -rf", "1e3", "23.5", "11 30 pm",
        ]
        for raw in garbage {
            XCTAssertThrowsError(try ControlValidation.parsedBedtime(raw), "'\(raw)' should be rejected") { error in
                guard case ControlError.badInput = error else {
                    return XCTFail("'\(raw)' threw \(error), not ControlError.badInput")
                }
            }
        }
    }

    func testBedtimeClockFormatting() {
        XCTAssertEqual(LateNightSnapshot.clock(minutes: 1380), "23:00")
        XCTAssertEqual(LateNightSnapshot.clock(minutes: 30), "00:30")
        XCTAssertEqual(LateNightSnapshot.clock(minutes: 240), "04:00")
        XCTAssertEqual(LateNightSnapshot.clock(minutes: 1200), "20:00")
        // Every offered bedtime survives format → parse.
        for minutes in 0..<1440 where LateNightStage.isAllowedBedtime(minutesOfDay: minutes) {
            XCTAssertEqual(try ControlValidation.parsedBedtime(LateNightSnapshot.clock(minutes: minutes)), minutes)
        }
    }

    // MARK: Ease validation

    func testValidatedEaseAcceptsOnlyTheAllowedSet() throws {
        for minutes in [15, 30, 45, 60, 90, 120] {
            XCTAssertEqual(try ControlValidation.validatedEaseMinutes(minutes), minutes)
        }
        for minutes in [0, -15, 1, 14, 16, 20, 59, 61, 75, 105, 119, 121, 180, 240, Int.max, Int.min] {
            XCTAssertThrowsError(try ControlValidation.validatedEaseMinutes(minutes), "\(minutes)") { error in
                let message = (error as? ControlError)?.description ?? ""
                XCTAssertTrue(message.contains("15, 30, 45, 60, 90, 120"), message)
            }
        }
        XCTAssertEqual(LateNightStage.allowedEaseMinutes.filter {
            (try? ControlValidation.validatedEaseMinutes($0)) != nil
        }, LateNightStage.allowedEaseMinutes)
    }

    // MARK: SettingsPatch

    func testLateNightPatchFieldsRoundTrip() throws {
        let patch = SettingsPatch(
            lateNightEnabled: true, bedtimeMinutes: 30, lateNightWarmthStrength: 0.85,
            lateNightCozy: false, lateNightEaseMinutes: 90
        )
        let decoded = try JSONDecoder().decode(SettingsPatch.self, from: JSONEncoder().encode(patch))
        XCTAssertEqual(decoded, patch)
        XCTAssertEqual(decoded.lateNightEnabled, true)
        XCTAssertEqual(decoded.bedtimeMinutes, 30)
        XCTAssertEqual(decoded.lateNightWarmthStrength, 0.85)
        XCTAssertEqual(decoded.lateNightCozy, false)
        XCTAssertEqual(decoded.lateNightEaseMinutes, 90)
        XCTAssertFalse(decoded.isEmpty)
    }

    func testEachLateNightFieldAloneMakesAPatchNonEmpty() {
        XCTAssertTrue(SettingsPatch().isEmpty)
        XCTAssertFalse(SettingsPatch(lateNightEnabled: false).isEmpty)
        XCTAssertFalse(SettingsPatch(bedtimeMinutes: 0).isEmpty)
        XCTAssertFalse(SettingsPatch(lateNightWarmthStrength: 0).isEmpty)
        XCTAssertFalse(SettingsPatch(lateNightCozy: false).isEmpty)
        XCTAssertFalse(SettingsPatch(lateNightEaseMinutes: 15).isEmpty)
    }

    func testPatchFromAnOlderCLIDecodesWithNoLateNightFields() throws {
        // What a CLI that predates the stage sends: none of the new keys.
        let json = #"{"cozy":true,"pausesForFullScreen":false}"#
        let patch = try JSONDecoder().decode(SettingsPatch.self, from: Data(json.utf8))
        XCTAssertEqual(patch.cozy, true)
        XCTAssertNil(patch.lateNightEnabled)
        XCTAssertNil(patch.bedtimeMinutes)
        XCTAssertNil(patch.lateNightWarmthStrength)
        XCTAssertNil(patch.lateNightCozy)
        XCTAssertNil(patch.lateNightEaseMinutes)
    }

    func testLateNightPatchSurvivesTheMessageEnvelope() throws {
        let message = ControlMessage(
            requestID: UUID().uuidString, writtenAt: Date(timeIntervalSince1970: 1_700_000_000),
            patch: SettingsPatch(bedtimeMinutes: 1410, lateNightEaseMinutes: 30)
        )
        let userInfo = try message.toUserInfo()
        let plist = try PropertyListSerialization.data(fromPropertyList: userInfo, format: .binary, options: 0)
        let back = try PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any]
        let decoded = ControlMessage.from(userInfo: back)
        XCTAssertEqual(decoded?.patch?.bedtimeMinutes, 1410)
        XCTAssertEqual(decoded?.patch?.lateNightEaseMinutes, 30)
        XCTAssertEqual(decoded?.schemaVersion, 1, "new optional fields must not need a schema bump")
    }

    // MARK: Snapshot

    private func snapshot(lateNight: LateNightSnapshot?) -> ControlStateSnapshot {
        ControlStateSnapshot(
            appVersion: "1.0.2", appBuild: "7", pid: 4242, appLaunchID: "LAUNCH",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000), lastAppliedRequestID: "REQ-1",
            isEnabled: true, scheduleMode: .sunset, isScheduleActiveNow: true, isRevealing: false,
            globalWarmthStrength: 0.7, globalKelvin: 2412, warmestPointKelvin: 1900,
            revealMode: "hold", excludedApps: [], lateNight: lateNight, displays: []
        )
    }

    func testLateNightSnapshotDerivesClockAndKelvin() {
        let warm = LateNightSnapshot(
            enabled: true, bedtimeMinutes: 30, warmthStrength: 1, cozy: false, easeMinutes: 45, phase: "held"
        )
        XCTAssertEqual(warm.bedtime, "00:30")
        XCTAssertEqual(warm.bedtimeMinutes, 30)
        XCTAssertEqual(warm.kelvin, Kelvin.everydayWarmest.value)
        XCTAssertEqual(warm.easeMinutes, 45)
        XCTAssertEqual(warm.phase, "held")

        // The slider reads on the everyday curve whatever the live ceiling is.
        let half = LateNightSnapshot(enabled: true, bedtimeMinutes: 1380, warmthStrength: 0.5, cozy: false, easeMinutes: 60)
        XCTAssertEqual(half.kelvin, WarmthLevel(strength: 0.5).kelvin(warmestPoint: .everydayWarmest).value)
        XCTAssertNil(half.phase)

        // Cozy at bedtime goes to the floor and leaves the saved strength alone.
        let cozy = LateNightSnapshot(enabled: true, bedtimeMinutes: 1380, warmthStrength: 0.5, cozy: true, easeMinutes: 60)
        XCTAssertEqual(cozy.kelvin, Kelvin.warmestSupported.value)
        XCTAssertEqual(cozy.warmthStrength, 0.5)
        XCTAssertEqual(LateNightSnapshot.targetKelvin(strength: 0.5, cozy: true), Kelvin.warmestSupported)
    }

    func testConfiguredStageAppliesTheAppsOwnDefaults() {
        // Nothing saved: off, 23:00, full everyday warmth, no Cozy, the default hour.
        let unset = LateNightSnapshot.configured(
            enabled: nil, bedtimeMinutes: nil, warmthStrength: nil, cozy: nil, easeMinutes: nil
        )
        XCTAssertEqual(unset, LateNightSnapshot(
            enabled: false, bedtimeMinutes: 1380, warmthStrength: 1, cozy: false, easeMinutes: 60
        ))
        XCTAssertNil(unset.phase)
        // Hand-edited values land where the app's own load puts them.
        let edited = LateNightSnapshot.configured(
            enabled: true, bedtimeMinutes: 13 * 60, warmthStrength: 7, cozy: true, easeMinutes: 100
        )
        XCTAssertEqual(edited.bedtimeMinutes, 1200, "an afternoon bedtime moves to the nearer end, 20:00")
        XCTAssertEqual(edited.warmthStrength, 1, "an invalid strength falls back to full")
        XCTAssertEqual(edited.easeMinutes, 90, "an ease off the set snaps to the nearest length")
        XCTAssertEqual(LateNightSnapshot.configured(
            enabled: true, bedtimeMinutes: 5 * 60, warmthStrength: 0.25, cozy: false, easeMinutes: 15
        ), LateNightSnapshot(enabled: true, bedtimeMinutes: 240, warmthStrength: 0.25, cozy: false, easeMinutes: 15))
        XCTAssertEqual(LateNightStage.clampedBedtime(minutesOfDay: 1440 + 30), 30)
        XCTAssertEqual(LateNightStage.clampedBedtime(minutesOfDay: 11 * 60), 240)
    }

    func testStoredBedtimeSnapsToTheHalfHourStep() {
        // A hand-written 23:15 is a time the CLI rejects and the stepper cannot reach: it snaps
        // to the nearest offered time, the earlier one on a tie.
        XCTAssertEqual(LateNightStage.clampedBedtime(minutesOfDay: 23 * 60 + 15), 23 * 60)
        XCTAssertEqual(LateNightStage.clampedBedtime(minutesOfDay: 23 * 60 + 14), 23 * 60)
        XCTAssertEqual(LateNightStage.clampedBedtime(minutesOfDay: 23 * 60 + 16), 23 * 60 + 30)
        XCTAssertEqual(LateNightStage.clampedBedtime(minutesOfDay: 23 * 60 + 50), 0, "snaps across midnight")
        XCTAssertEqual(LateNightStage.clampedBedtime(minutesOfDay: 7), 0)
        XCTAssertEqual(LateNightStage.clampedBedtime(minutesOfDay: 3 * 60 + 59), 240)
        XCTAssertEqual(LateNightStage.clampedBedtime(minutesOfDay: 4 * 60 + 10), 240)
        XCTAssertEqual(LateNightStage.clampedBedtime(minutesOfDay: 19 * 60 + 55), 1200)
        // Whatever goes in, an offered bedtime comes out, and an offered bedtime is left alone.
        for minutes in -3000...3000 {
            let clamped = LateNightStage.clampedBedtime(minutesOfDay: minutes)
            XCTAssertTrue(LateNightStage.isAllowedBedtime(minutesOfDay: clamped), "\(minutes) → \(clamped)")
        }
        for minutes in 0..<1440 where LateNightStage.isAllowedBedtime(minutesOfDay: minutes) {
            XCTAssertEqual(LateNightStage.clampedBedtime(minutesOfDay: minutes), minutes)
        }
        XCTAssertEqual(LateNightSnapshot.configured(
            enabled: true, bedtimeMinutes: 23 * 60 + 15, warmthStrength: 1, cozy: false, easeMinutes: 60
        ).bedtime, "23:00")
    }

    func testCorruptStoredNumbersNeverTrap() {
        // `defaults write … -float -1e30` reads back through NSNumber.intValue as Int.min.
        for garbage in [Int.min, Int.min + 1, -1, 0, Int.max - 1, Int.max] {
            let stage = LateNightSnapshot.configured(
                enabled: true, bedtimeMinutes: garbage, warmthStrength: 1, cozy: false, easeMinutes: garbage
            )
            XCTAssertTrue(LateNightStage.isAllowedBedtime(minutesOfDay: stage.bedtimeMinutes), "\(garbage)")
            XCTAssertTrue(LateNightStage.allowedEaseMinutes.contains(stage.easeMinutes ?? -1), "\(garbage)")
            XCTAssertEqual(stage.bedtime, LateNightSnapshot.clock(minutes: stage.bedtimeMinutes))
            // The stage the engine is handed from the same numbers.
            let core = LateNightStage(bedtimeMinutes: garbage, target: Kelvin(stage.kelvin), easeMinutes: garbage)
            XCTAssertTrue((0..<1440).contains(core.bedtimeMinutes))
            XCTAssertTrue((1...1440).contains(core.easeMinutes))
            XCTAssertTrue(core.rampDuration.isFinite)
        }
        XCTAssertEqual(LateNightSnapshot.configured(
            enabled: true, bedtimeMinutes: .min, warmthStrength: 1, cozy: false, easeMinutes: .min
        ).easeMinutes, 15)
        XCTAssertEqual(LateNightSnapshot.configured(
            enabled: true, bedtimeMinutes: .max, warmthStrength: 1, cozy: false, easeMinutes: .max
        ).easeMinutes, 120)
        // A strength that is not a number in 0...1 falls back to full, and the Kelvin stays sane.
        for garbage in [Double.nan, .signalingNaN, .infinity, -.infinity, -1e30, 1e30, -0.0001, 1.0001] {
            let stage = LateNightSnapshot.configured(
                enabled: true, bedtimeMinutes: 1380, warmthStrength: garbage, cozy: false, easeMinutes: 60
            )
            XCTAssertEqual(stage.warmthStrength, 1, "\(garbage)")
            XCTAssertEqual(stage.kelvin, Kelvin.everydayWarmest.value, "\(garbage)")
            // The raw value never traps the colour rule either.
            let raw = LateNightSnapshot.targetKelvin(strength: garbage, cozy: false)
            XCTAssertTrue((Kelvin.everydayWarmest...Kelvin.neutral).contains(raw), "\(garbage) → \(raw.value)")
        }
        XCTAssertEqual(WarmthLevel(strength: .nan).strength, 0)
    }

    func testPhaseConstantsMatchTheCorePhases() {
        XCTAssertEqual(LateNightSnapshot.phaseInactive, LateNightPhase.inactive.rawValue)
        XCTAssertEqual(LateNightSnapshot.phaseEasing, LateNightPhase.easing.rawValue)
        XCTAssertEqual(LateNightSnapshot.phaseHeld, LateNightPhase.held.rawValue)
        XCTAssertEqual(LateNightSnapshot.phaseReleasing, LateNightPhase.releasing.rawValue)
    }

    func testAnUnknownPhaseStringStillDecodes() throws {
        // A newer app may report a phase this build has never heard of.
        let json = #"{"enabled":true,"bedtime":"23:00","bedtimeMinutes":1380,"warmthStrength":1,"kelvin":1900,"cozy":false,"easeMinutes":60,"phase":"somethingNew"}"#
        let decoded = try JSONDecoder().decode(LateNightSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.phase, "somethingNew")
        XCTAssertEqual(AbendrotControl.schemaVersion, 1)
    }

    func testSnapshotWithLateNightRoundTrips() throws {
        let stage = LateNightSnapshot(
            enabled: true, bedtimeMinutes: 1410, warmthStrength: 0.9, cozy: false, easeMinutes: 120, phase: "easing"
        )
        let original = snapshot(lateNight: stage)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ControlStateSnapshot.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.lateNight, stage)

        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let lateNight = try XCTUnwrap(object["lateNight"] as? [String: Any])
        XCTAssertEqual(
            Set(lateNight.keys),
            ["enabled", "bedtime", "bedtimeMinutes", "warmthStrength", "kelvin", "cozy", "easeMinutes", "phase"]
        )
        XCTAssertEqual(lateNight["bedtime"] as? String, "23:30")
        XCTAssertEqual(lateNight["bedtimeMinutes"] as? Int, 1410)
        XCTAssertEqual(lateNight["easeMinutes"] as? Int, 120)
        XCTAssertEqual(lateNight["phase"] as? String, "easing")
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
    }

    func testSnapshotFromAnOlderAppDecodesWithoutLateNight() throws {
        // A snapshot exactly as the build before this one wrote it: no `lateNight` key at all.
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot(lateNight: nil))) as? [String: Any]
        )
        object.removeValue(forKey: "lateNight")
        XCTAssertNil(object["lateNight"])
        let data = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(ControlStateSnapshot.self, from: data)
        XCTAssertNil(decoded.lateNight)
        XCTAssertEqual(decoded.pid, 4242)
        XCTAssertEqual(decoded.scheduleMode, .sunset)
    }

    func testLateNightObjectFromAnOlderAppDecodesWithoutEaseOrPhase() throws {
        // A stage object missing the fields added last must still decode: every one that could be
        // absent is optional, so a partial object never takes the whole snapshot down.
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot(lateNight: nil))) as? [String: Any]
        )
        object["lateNight"] = ["enabled": true, "bedtime": "23:00", "bedtimeMinutes": 1380,
                               "warmthStrength": 1.0, "kelvin": 1900, "cozy": false]
        let decoded = try JSONDecoder().decode(
            ControlStateSnapshot.self, from: JSONSerialization.data(withJSONObject: object)
        )
        XCTAssertEqual(decoded.lateNight?.enabled, true)
        XCTAssertNil(decoded.lateNight?.easeMinutes)
        XCTAssertNil(decoded.lateNight?.phase)
    }

    func testLivenessDecodesFromASnapshotCarryingLateNight() throws {
        let stage = LateNightSnapshot(enabled: true, bedtimeMinutes: 1380, warmthStrength: 1, cozy: true, easeMinutes: 15)
        let data = try JSONEncoder().encode(snapshot(lateNight: stage))
        let liveness = try JSONDecoder().decode(ControlLiveness.self, from: data)
        XCTAssertEqual(liveness.pid, 4242)
        XCTAssertEqual(liveness.lastAppliedRequestID, "REQ-1")
        XCTAssertEqual(liveness.schemaVersion, AbendrotControl.schemaVersion)
    }

    func testLivenessSurvivesAFutureLateNightShape() throws {
        // A later app may reshape `lateNight`; liveness and ack must not care.
        let json = """
        {"schemaVersion": 1, "pid": 77, "appLaunchID": "L", "updatedAt": 803703602.0,
         "lastAppliedRequestID": "REQ-9", "lateNight": "reshaped-into-a-string"}
        """
        let liveness = try JSONDecoder().decode(ControlLiveness.self, from: Data(json.utf8))
        XCTAssertEqual(liveness.pid, 77)
        XCTAssertEqual(liveness.lastAppliedRequestID, "REQ-9")
    }

    func testSchemaVersionIsNotBumpedForTheStage() {
        XCTAssertEqual(AbendrotControl.schemaVersion, 1)
    }
}
