import XCTest
import ClipManagerCore

/// Interoperability test: the Python generator (Scripts/generate_license.py)
/// and the Swift verifier (LicenseSerial.verify) must agree byte-for-byte.
/// A fixed payload makes the generated serial deterministic, so the HMAC
/// output of both implementations is compared directly.
final class GoldenRoundtripTests: XCTestCase {

    private var scriptURL: URL!

    override func setUpWithError() throws {
        // #filePath is Tests/ClipManagerCoreTests/GoldenRoundtripTests.swift
        let file = URL(fileURLWithPath: #filePath)
        let root = file
            .deletingLastPathComponent() // Tests/ClipManagerCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // package root
        scriptURL = root.appendingPathComponent("Scripts/generate_license.py")
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            throw XCTSkip("Scripts/generate_license.py not found at \(scriptURL.path)")
        }
    }

    private func runPython(_ args: [String]) throws -> (exitCode: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3"] + args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        try process.run()
        done.wait()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    func testSwiftAcceptsSerialGeneratedByPython() throws {
        let result = try runPython([
            scriptURL.path,
            "--secret", Fixtures.testSecret,
            "--install-id", Fixtures.installId,
            "--plan", "solo",
            "--expiry", Fixtures.futureExpiry,
            "--payload", Fixtures.fixedPayload,
        ])
        XCTAssertEqual(result.exitCode, 0, "python: \(result.output)")
        let serial = result.output.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let parsed = LicenseSerial(string: serial) else {
            return XCTFail("Swift could not parse the Python-generated serial: \(serial)")
        }
        try parsed.verify(installId: Fixtures.installId, secret: Fixtures.testSecret, now: Date())

        // Byte-for-byte HMAC parity with Swift's own computation.
        XCTAssertEqual(
            parsed.check,
            LicenseSerial.computeCheck(
                secret: Fixtures.testSecret, installId: Fixtures.installId,
                plan: .solo, expiry: Fixtures.futureExpiry, payload: Fixtures.fixedPayload
            )
        )
    }

    func testPythonAcceptsSerialGeneratedBySwift() throws {
        let result = try runPython([
            scriptURL.path,
            "--secret", Fixtures.testSecret,
            "--verify",
            "--serial", Fixtures.validSerial,
            "--install-id", Fixtures.installId,
        ])
        XCTAssertEqual(result.exitCode, 0, "python: \(result.output)")
        XCTAssertTrue(result.output.contains("valid"))
    }

    func testPythonRejectsSerialBoundToAnotherInstall() throws {
        let result = try runPython([
            scriptURL.path,
            "--secret", Fixtures.testSecret,
            "--verify",
            "--serial", Fixtures.validSerial,
            "--install-id", Fixtures.otherInstallId,
        ])
        XCTAssertEqual(result.exitCode, 1, "python should reject: \(result.output)")
    }

    func testPythonRejectsTamperedPayload() throws {
        let parts = Fixtures.validSerial.split(separator: "-").map(String.init)
        var payload = Array(parts[3])
        payload[0] = payload[0] == "A" ? "B" : "A"
        let tampered = [parts[0], parts[1], parts[2], String(payload), parts[4]].joined(separator: "-")

        let result = try runPython([
            scriptURL.path,
            "--secret", Fixtures.testSecret,
            "--verify",
            "--serial", tampered,
            "--install-id", Fixtures.installId,
        ])
        XCTAssertEqual(result.exitCode, 1, "python should reject: \(result.output)")
    }
}
