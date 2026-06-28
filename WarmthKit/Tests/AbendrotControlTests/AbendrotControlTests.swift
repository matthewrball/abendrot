import XCTest
import WarmthCore
@testable import AbendrotControl

// MARK: - AbendrotControlTests
//
// The HARD GATE for the shared control schema. These prove the wire shape both the
// app and the `abendrot` CLI depend on stays stable: constant strings (a silent key rename would
// break cross-process control), Codable round-trips, the lossless CLI↔engine schedule mapping,
// the distributed-notification plist round-trip, and that the CLI writes the SAME scheduleMode
// `Data` the app reads.
final class AbendrotControlTests: XCTestCase {

    // MARK: Constants & keys (regression guard against silent rename)

    func testSchemaVersionIsOne() {
        XCTAssertEqual(AbendrotControl.schemaVersion, 1)
    }

    func testPreferenceKeysEqualTheirLiteralStrings() {
        // These literals are the persisted CFPreferences keys. If anyone renames one, the CLI and
        // the running app silently stop seeing each other's writes — so pin every one.
        XCTAssertEqual(PreferenceKey.isEnabled, "isEnabled")
        XCTAssertEqual(PreferenceKey.globalWarmthStrength, "globalWarmthStrength")
        XCTAssertEqual(PreferenceKey.manualWarmthStrength, "manualWarmthStrength")
        XCTAssertEqual(PreferenceKey.warmestPointKelvin, "warmestPointKelvin")
        XCTAssertEqual(PreferenceKey.scheduleMode, "scheduleMode")
        XCTAssertEqual(PreferenceKey.revealMode, "revealMode")
        XCTAssertEqual(PreferenceKey.excludedApps, "excludedApps")
        XCTAssertEqual(PreferenceKey.userLatitude, "userLatitude")
        XCTAssertEqual(PreferenceKey.userLongitude, "userLongitude")
    }

    func testIdentityConstants() {
        XCTAssertEqual(AbendrotControl.appBundleID, "app.abendrot.Abendrot")
        XCTAssertEqual(AbendrotControl.preferenceDomain, "app.abendrot.Abendrot")
        XCTAssertEqual(AbendrotControl.settingsChangedNotification, "app.abendrot.settingsChanged")
        XCTAssertEqual(AbendrotControl.appSupportDirectoryName, "Abendrot")
        XCTAssertEqual(AbendrotControl.stateFileName, "state.json")
    }

    // MARK: SettingsPatch Codable round-trip

    func testSettingsPatchCodableRoundTrip() throws {
        let patch = SettingsPatch(
            isEnabled: true,
            globalWarmthStrength: 0.8,
            warmestPointKelvin: 1900,
            scheduleMode: .alwaysOn,
            revealMode: "toggle",
            excludedApps: ["com.apple.dt.Xcode", "com.figma.Desktop"],
            userLatitude: 51.5,
            userLongitude: -0.12,
            clearUserCoordinate: false,
            cozy: true
        )
        let data = try JSONEncoder().encode(patch)
        let decoded = try JSONDecoder().decode(SettingsPatch.self, from: data)
        XCTAssertEqual(patch, decoded)
        XCTAssertEqual(decoded.cozy, true)
    }

    func testCozyOnlyPatchRoundTripsAndIsNotEmpty() throws {
        // A `cozy on/off` command sends a patch with ONLY `cozy` set — it must survive the wire and
        // not read as a no-op (the app skips an empty patch).
        let patch = SettingsPatch(cozy: false)
        XCTAssertFalse(patch.isEmpty)
        let data = try JSONEncoder().encode(patch)
        let decoded = try JSONDecoder().decode(SettingsPatch.self, from: data)
        XCTAssertEqual(patch, decoded)
        XCTAssertEqual(decoded.cozy, false)
        // Every other field stays nil — cozy is a standalone master toggle.
        XCTAssertNil(decoded.warmestPointKelvin)
        XCTAssertNil(decoded.globalWarmthStrength)
    }

    func testEmptySettingsPatchRoundTripAndIsEmpty() throws {
        let patch = SettingsPatch()
        XCTAssertTrue(patch.isEmpty)
        let data = try JSONEncoder().encode(patch)
        let decoded = try JSONDecoder().decode(SettingsPatch.self, from: data)
        XCTAssertEqual(patch, decoded)
        XCTAssertTrue(decoded.isEmpty)
    }

    // MARK: ControlScheduleMode ↔ ScheduleMode (lossless, .off NOT collapsed)

    func testControlScheduleModeRoundTripsForAllCases() {
        for mode in ControlScheduleMode.allCases {
            let engine = mode.toScheduleMode()
            XCTAssertEqual(ControlScheduleMode(engine), mode, "round-trip failed for \(mode)")
        }
    }

    func testOffStaysOffNotCollapsedToSunset() {
        // The UI collapses .off → Sunset; the control surface must NOT.
        XCTAssertEqual(ControlScheduleMode.off.toScheduleMode(), ScheduleMode.off)
        XCTAssertEqual(ControlScheduleMode(.off), .off)
    }

    func testDormantEngineCasesProjectToSunset() {
        XCTAssertEqual(ControlScheduleMode(.followSystemNightShift), .sunset)
        XCTAssertEqual(ControlScheduleMode(.solar(latitude: 0, longitude: 0)), .sunset)
        XCTAssertEqual(ControlScheduleMode(.alwaysOn), .alwaysOn)
    }

    func testControlScheduleModeRawValues() {
        XCTAssertEqual(ControlScheduleMode.sunset.rawValue, "sunset")
        XCTAssertEqual(ControlScheduleMode.alwaysOn.rawValue, "always-on")
        XCTAssertEqual(ControlScheduleMode.off.rawValue, "off")
    }

    // MARK: ControlStateSnapshot / DisplaySnapshot Codable round-trip

    func testSnapshotCodableRoundTrip() throws {
        let snapshot = ControlStateSnapshot(
            appVersion: "0.1.0",
            appBuild: "1",
            pid: 4242,
            appLaunchID: UUID().uuidString,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastAppliedRequestID: UUID().uuidString,
            isEnabled: true,
            scheduleMode: .sunset,
            isScheduleActiveNow: true,
            isRevealing: false,
            globalWarmthStrength: 0.7,
            globalKelvin: 2700,
            warmestPointKelvin: 1900,
            revealMode: "hold",
            excludedApps: ["com.apple.dt.Xcode"],
            displays: [
                DisplaySnapshot(
                    id: UUID().uuidString,
                    name: "Built-in",
                    appliedMethod: "overlay",
                    preferredMethod: nil,
                    warmthStrength: 0.7,
                    warmthOverridden: false,
                    isHardwareDDCEnabled: false,
                    lastError: nil
                ),
            ]
        )
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(ControlStateSnapshot.self, from: data)
        XCTAssertEqual(snapshot, decoded)
        // 1900K ceiling ⇒ cozy off; the field rides through the wire.
        XCTAssertFalse(decoded.cozy)
    }

    func testSnapshotDerivesCozyFromWarmestPoint() {
        // The derivation rule (warmestPointKelvin < everydayWarmest) is the single source of truth, and
        // the init must apply it so `cozy` can never disagree with the ceiling it's reported alongside.
        XCTAssertTrue(ControlStateSnapshot.isCozy(warmestPointKelvin: 500))
        XCTAssertTrue(ControlStateSnapshot.isCozy(warmestPointKelvin: 1899))
        XCTAssertFalse(ControlStateSnapshot.isCozy(warmestPointKelvin: 1900))
        XCTAssertFalse(ControlStateSnapshot.isCozy(warmestPointKelvin: 2700))

        func snapshot(maxK: Int) -> ControlStateSnapshot {
            ControlStateSnapshot(
                appVersion: "0.1.0", appBuild: "1", pid: 1, appLaunchID: "L",
                updatedAt: Date(timeIntervalSince1970: 0), lastAppliedRequestID: nil,
                isEnabled: true, scheduleMode: .sunset, isScheduleActiveNow: false,
                isRevealing: false, globalWarmthStrength: 0.7, globalKelvin: 2700,
                warmestPointKelvin: maxK, revealMode: "hold", excludedApps: [], displays: [])
        }
        XCTAssertTrue(snapshot(maxK: 500).cozy)     // expanded range in effect
        XCTAssertFalse(snapshot(maxK: 1900).cozy)   // everyday ceiling
    }

    // MARK: ControlLiveness — forward-compatible decode of a future snapshot

    func testLivenessDecodesFromFullSnapshotJSON() throws {
        // The minimal liveness view must decode from a real full-snapshot encoding (same field
        // names/types), so the CLI's liveness/ack path works against the current app.
        let snapshot = ControlStateSnapshot(
            appVersion: "0.1.0", appBuild: "1", pid: 4242,
            appLaunchID: UUID().uuidString,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastAppliedRequestID: "REQ-1",
            isEnabled: true, scheduleMode: .sunset, isScheduleActiveNow: true,
            isRevealing: false, globalWarmthStrength: 0.7, globalKelvin: 2700,
            warmestPointKelvin: 1900, revealMode: "hold", excludedApps: [], displays: [])
        let data = try JSONEncoder().encode(snapshot)
        let liveness = try JSONDecoder().decode(ControlLiveness.self, from: data)
        XCTAssertEqual(liveness.pid, 4242)
        XCTAssertEqual(liveness.lastAppliedRequestID, "REQ-1")
        XCTAssertEqual(liveness.schemaVersion, AbendrotControl.schemaVersion)
    }

    func testLivenessDecodesFromForwardIncompatibleSnapshot() throws {
        // A FUTURE app snapshot: a higher schemaVersion, a brand-new REQUIRED field, and a changed
        // type on a field the liveness view does not read. The full `ControlStateSnapshot` would
        // fail to decode this, but `ControlLiveness` must still recover pid + ack so `status`
        // reports running:true and a `set` can still confirm against a newer app.
        // `updatedAt` is a numeric Date (seconds since the 2001 reference) — the default Codable
        // encoding the app writes and the CLI decodes (no .iso8601 strategy on the read path).
        let futureJSON = """
        {
          "schemaVersion": 99,
          "pid": 5150,
          "appLaunchID": "LAUNCH-XYZ",
          "updatedAt": 803703602.008142,
          "lastAppliedRequestID": "REQ-FUTURE",
          "brandNewRequiredField": {"nested": [1, 2, 3]},
          "isEnabled": "yes-now-a-string",
          "displays": "no-longer-an-array"
        }
        """
        let data = Data(futureJSON.utf8)
        XCTAssertNil(try? JSONDecoder().decode(ControlStateSnapshot.self, from: data),
                     "the full snapshot should NOT decode a forward-incompatible payload")
        let liveness = try JSONDecoder().decode(ControlLiveness.self, from: data)
        XCTAssertEqual(liveness.schemaVersion, 99)
        XCTAssertEqual(liveness.pid, 5150)
        XCTAssertEqual(liveness.lastAppliedRequestID, "REQ-FUTURE")
    }

    func testLivenessCodableRoundTrip() throws {
        let liveness = ControlLiveness(
            schemaVersion: 1, pid: 321, appLaunchID: UUID().uuidString,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastAppliedRequestID: nil)
        let data = try JSONEncoder().encode(liveness)
        let decoded = try JSONDecoder().decode(ControlLiveness.self, from: data)
        XCTAssertEqual(liveness, decoded)
    }

    // MARK: Transport-safety — the userInfo dict survives a real plist round-trip

    func testControlMessageSurvivesPlistRoundTrip() throws {
        let original = ControlMessage(
            requestID: UUID().uuidString,
            writtenAt: Date(timeIntervalSince1970: 1_700_000_000),
            patch: SettingsPatch(
                isEnabled: false,
                globalWarmthStrength: 0.42,
                scheduleMode: .off,
                excludedApps: ["a.b.c"]
            )
        )
        let userInfo = try original.toUserInfo()

        // Serialize the dict to a binary plist and back — exactly what crosses the distributed
        // notification boundary — then decode the message and assert equality.
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: userInfo, format: .binary, options: 0)
        let roundTripped = try PropertyListSerialization.propertyList(
            from: plistData, options: [], format: nil)
        let dict = try XCTUnwrap(roundTripped as? [String: Any])

        // Scalars survive for cheap inspection.
        XCTAssertEqual(dict[ControlMessage.userInfoSchemaKey] as? Int, AbendrotControl.schemaVersion)
        XCTAssertEqual(dict[ControlMessage.userInfoRequestIDKey] as? String, original.requestID)

        let decoded = try XCTUnwrap(ControlMessage.from(userInfo: dict))
        XCTAssertEqual(decoded, original)
    }

    func testControlMessageFromUserInfoReturnsNilWhenPayloadAbsent() {
        XCTAssertNil(ControlMessage.from(userInfo: nil))
        XCTAssertNil(ControlMessage.from(userInfo: ["unrelated": "value"]))
    }

    func testRevealActionMessageRoundTrip() throws {
        let original = ControlMessage(
            requestID: UUID().uuidString,
            writtenAt: Date(timeIntervalSince1970: 1_700_000_000),
            action: .reveal(holdSeconds: 3)
        )
        let userInfo = try original.toUserInfo()
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: userInfo, format: .binary, options: 0)
        let dict = try XCTUnwrap(
            try PropertyListSerialization.propertyList(from: plistData, options: [], format: nil)
                as? [String: Any])
        let decoded = try XCTUnwrap(ControlMessage.from(userInfo: dict))
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.action, .reveal(holdSeconds: 3))
    }

    // MARK: scheduleMode wire-compat — the CLI writes the SAME Data AppModel reads

    func testScheduleModeWireCompatWithEngineCodable() throws {
        // The CLI persists scheduleMode as JSONEncoder().encode(controlMode.toScheduleMode()).
        // The app reads it as JSONDecoder().decode(ScheduleMode.self, ...). Prove that round-trips
        // for every control mode — i.e. the CLI and AppModel agree on the exact bytes.
        for mode in ControlScheduleMode.allCases {
            let engineMode = mode.toScheduleMode()
            let data = try JSONEncoder().encode(engineMode)
            let decoded = try JSONDecoder().decode(ScheduleMode.self, from: data)
            XCTAssertEqual(decoded, engineMode, "wire mismatch for \(mode)")
        }
    }

    func testAlwaysOnWireExactlyEqualsEngineAlwaysOn() throws {
        let data = try JSONEncoder().encode(ControlScheduleMode.alwaysOn.toScheduleMode())
        let decoded = try JSONDecoder().decode(ScheduleMode.self, from: data)
        XCTAssertEqual(decoded, ScheduleMode.alwaysOn)
    }

    // MARK: Validation

    func testValidationAcceptsInRangeAndRejectsOutOfRange() throws {
        XCTAssertEqual(try ControlValidation.validatedStrength(0.0), 0.0)
        XCTAssertEqual(try ControlValidation.validatedStrength(1.0), 1.0)
        XCTAssertThrowsError(try ControlValidation.validatedStrength(1.1))
        XCTAssertThrowsError(try ControlValidation.validatedStrength(-0.1))

        XCTAssertEqual(try ControlValidation.validatedKelvin(500), 500)
        XCTAssertEqual(try ControlValidation.validatedKelvin(6500), 6500)
        XCTAssertThrowsError(try ControlValidation.validatedKelvin(499))
        XCTAssertThrowsError(try ControlValidation.validatedKelvin(6501))

        XCTAssertEqual(try ControlValidation.validatedRevealMode("hold"), "hold")
        XCTAssertEqual(try ControlValidation.validatedRevealMode("toggle"), "toggle")
        XCTAssertThrowsError(try ControlValidation.validatedRevealMode("flash"))
    }

    func testControlErrorCarriesMessage() {
        let error = ControlError.badInput("warmth must be 0.0–1.0, got 50.0")
        XCTAssertEqual(error.description, "warmth must be 0.0–1.0, got 50.0")
    }

    func testValidatedCoordinateAcceptsInRangeAndRejectsBad() throws {
        // Valid corners + a normal point round-trip the pair unchanged.
        let london = try ControlValidation.validatedCoordinate(lat: 51.5, lon: -0.12)
        XCTAssertEqual(london.lat, 51.5)
        XCTAssertEqual(london.lon, -0.12)
        XCTAssertNoThrow(try ControlValidation.validatedCoordinate(lat: -90, lon: -180))
        XCTAssertNoThrow(try ControlValidation.validatedCoordinate(lat: 90, lon: 180))

        // Non-finite and out-of-range values are rejected (the reachable-crash class this guards).
        XCTAssertThrowsError(try ControlValidation.validatedCoordinate(lat: .nan, lon: 0))
        XCTAssertThrowsError(try ControlValidation.validatedCoordinate(lat: 0, lon: .nan))
        XCTAssertThrowsError(try ControlValidation.validatedCoordinate(lat: .infinity, lon: 0))
        XCTAssertThrowsError(try ControlValidation.validatedCoordinate(lat: 0, lon: 1e308))
        XCTAssertThrowsError(try ControlValidation.validatedCoordinate(lat: 999, lon: 0))
        XCTAssertThrowsError(try ControlValidation.validatedCoordinate(lat: 0, lon: 999))
    }
}
