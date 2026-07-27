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

    // MARK: Kelvin → strength curve (must invert WarmthLevel.kelvin and stay monotonic)

    func testWarmthCurveEndpoints() {
        let warmest = Kelvin.everydayWarmest   // 1900K
        // Neutral target → ~0 strength; warmest target → ~1 strength.
        XCTAssertEqual(WarmthCurve.strength(forKelvin: Kelvin.neutral, warmestPoint: warmest), 0.0, accuracy: 0.02)
        XCTAssertEqual(WarmthCurve.strength(forKelvin: warmest, warmestPoint: warmest), 1.0, accuracy: 0.02)
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
