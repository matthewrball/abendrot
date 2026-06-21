import XCTest
import WarmthCore
@testable import AbendrotControl

// MARK: - AbendrotControlTests
//
// The HARD GATE for the shared control schema (spec §1.6). These prove the wire shape both the
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
            clearUserCoordinate: false
        )
        let data = try JSONEncoder().encode(patch)
        let decoded = try JSONDecoder().decode(SettingsPatch.self, from: data)
        XCTAssertEqual(patch, decoded)
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
}
