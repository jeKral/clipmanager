import XCTest
import ClipManagerCore

final class TelemetryTests: XCTestCase {

    func testAnonymizedInstallIdIs12HexChars() {
        let anon = Telemetry.anonymizedInstallId(Fixtures.installId)
        XCTAssertEqual(anon.count, 12)
        XCTAssertTrue(anon.allSatisfy { $0.isHexDigit })
    }

    func testAnonymizationIsDeterministic() {
        XCTAssertEqual(
            Telemetry.anonymizedInstallId(Fixtures.installId),
            Telemetry.anonymizedInstallId(Fixtures.installId)
        )
    }

    func testAnonymizationDiffersPerInstall() {
        XCTAssertNotEqual(
            Telemetry.anonymizedInstallId(Fixtures.installId),
            Telemetry.anonymizedInstallId(Fixtures.otherInstallId)
        )
    }

    func testAnonymizationNeverLeakstheRawId() {
        let anon = Telemetry.anonymizedInstallId(Fixtures.installId)
        XCTAssertFalse(Fixtures.installId.contains(anon))
        XCTAssertNotEqual(anon, Fixtures.installId)
    }

    func testHeartbeatContainsOnlyAllowedFields() throws {
        let payload = Telemetry.currentHeartbeat(installId: Fixtures.installId, version: "9.9.9", now: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(payload.app, "ClipManager")
        XCTAssertEqual(payload.version, "9.9.9")
        XCTAssertEqual(payload.os, "macOS")
        XCTAssertEqual(payload.installId, Telemetry.anonymizedInstallId(Fixtures.installId))

        // ISO-8601 UTC.
        XCTAssertEqual(payload.ts, "1970-01-01T00:00:00Z")

        // Roundtrip through JSON (what actually goes over the wire).
        let data = try JSONEncoder().encode(payload)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains(Fixtures.installId), "raw installId must not appear on the wire")
    }

    func testBugReportUsesAnonymizedIdAndCarriesLog() throws {
        let report = Telemetry.currentBugReport(
            installId: Fixtures.installId,
            message: "Crash on paste",
            log: "line1\nline2",
            version: "1.2.3",
            now: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(report.installId, Telemetry.anonymizedInstallId(Fixtures.installId))
        XCTAssertEqual(report.message, "Crash on paste")
        XCTAssertEqual(report.log, "line1\nline2")

        let data = try JSONEncoder().encode(report)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains(Fixtures.installId))
    }
}
