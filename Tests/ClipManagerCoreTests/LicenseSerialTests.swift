import XCTest
import ClipManagerCore

final class LicenseSerialTests: XCTestCase {

    // MARK: - Parsing

    func testParseValidSerial() {
        let serial = LicenseSerial(string: Fixtures.validSerial)
        XCTAssertNotNil(serial)
        XCTAssertEqual(serial?.plan, .solo)
        XCTAssertEqual(serial?.expiry, Fixtures.futureExpiry)
        XCTAssertEqual(serial?.payload, Fixtures.fixedPayload)
        XCTAssertEqual(serial?.check.count, 8)
    }

    func testParseIsCaseInsensitiveOnCheckAndPlan() {
        let upper = Fixtures.validSerial.uppercased()
        let serial = LicenseSerial(string: upper)
        XCTAssertNotNil(serial)
        XCTAssertEqual(serial?.plan, .solo)
    }

    func testNormalizedStringRoundtrip() {
        let serial = LicenseSerial(string: Fixtures.validSerial)!
        XCTAssertEqual(LicenseSerial(string: serial.normalizedString), serial)
    }

    // MARK: - Format rejection

    func testRejectsWrongPrefix() {
        let bad = Fixtures.validSerial.replacingOccurrences(of: "CLIP-", with: "CLPK-")
        XCTAssertNil(LicenseSerial(string: bad))
    }

    func testRejectsUnknownPlan() {
        let bad = Fixtures.validSerial.replacingOccurrences(of: "-SOLO-", with: "-PRO-")
        XCTAssertNil(LicenseSerial(string: bad))
    }

    func testRejectsImpossibleExpiry() {
        // 2026-02-30 does not exist.
        let bad = Fixtures.validSerial.replacingOccurrences(of: "-20991231-", with: "-20260230-")
        XCTAssertNil(LicenseSerial(string: bad))
    }

    func testRejectsPastCenturyExpiry() {
        let bad = Fixtures.validSerial.replacingOccurrences(of: "-20991231-", with: "-19991231-")
        XCTAssertNil(LicenseSerial(string: bad))
    }

    func testRejectsShortPayload() {
        let serial = LicenseSerial.compose(
            secret: Fixtures.testSecret, installId: Fixtures.installId,
            plan: .solo, expiry: Fixtures.futureExpiry, payload: String(Fixtures.fixedPayload.dropLast())
        )
        XCTAssertNil(LicenseSerial(string: serial))
    }

    func testRejectsPayloadWithForbiddenCharacters() {
        // 'I' and '0' are not in the license alphabet.
        let serial = LicenseSerial.compose(
            secret: Fixtures.testSecret, installId: Fixtures.installId,
            plan: .solo, expiry: Fixtures.futureExpiry, payload: "II00II00II00II00II00II"
        )
        XCTAssertNil(LicenseSerial(string: serial))
    }

    func testRejectsWrongCheckLength() {
        let parts = Fixtures.validSerial.split(separator: "-")
        let bad = parts.joined(separator: "-") + "f"
        XCTAssertNil(LicenseSerial(string: bad))
    }

    func testRejectsGarbage() {
        XCTAssertNil(LicenseSerial(string: ""))
        XCTAssertNil(LicenseSerial(string: "not-a-serial"))
        XCTAssertNil(LicenseSerial(string: "CLIP-SOLO-20991231"))
    }

    // MARK: - InstallId normalization

    func testNormalizedInstallId() {
        XCTAssertEqual(
            LicenseSerial.normalizedInstallId("A1B2C3D4-E5F6-4A7B-8C9D-0E1F2A3B4C5D"),
            Fixtures.installId
        )
        // Without hyphens.
        XCTAssertEqual(
            LicenseSerial.normalizedInstallId("a1b2c3d4e5f64a7b8c9d0e1f2a3b4c5d"),
            Fixtures.installId
        )
        XCTAssertNil(LicenseSerial.normalizedInstallId("nope"))
    }

    // MARK: - Expiry date

    func testExpiryDateIsStartOfDay() {
        let serial = LicenseSerial(string: Fixtures.validSerial)!
        let date = serial.expiryDate!
        let cal = Calendar.current
        XCTAssertEqual(cal.component(.year, from: date), 2099)
        XCTAssertEqual(cal.component(.month, from: date), 12)
        XCTAssertEqual(cal.component(.day, from: date), 31)
        XCTAssertEqual(date, cal.startOfDay(for: date))
    }

    // MARK: - Verification

    func testVerifyValidSerial() throws {
        let serial = LicenseSerial(string: Fixtures.validSerial)!
        try serial.verify(installId: Fixtures.installId, secret: Fixtures.testSecret, now: Date())
    }

    func testVerifyAcceptsNonCanonicalInstallId() throws {
        let serial = LicenseSerial(string: Fixtures.validSerial)!
        // Uppercase input must be normalized to the canonical lower-case form.
        try serial.verify(installId: Fixtures.installId.uppercased(), secret: Fixtures.testSecret, now: Date())
    }

    func testVerifyRejectsWrongInstallId() {
        let serial = LicenseSerial(string: Fixtures.validSerial)!
        XCTAssertThrowsError(
            try serial.verify(installId: Fixtures.otherInstallId, secret: Fixtures.testSecret, now: Date())
        ) { error in
            XCTAssertEqual(error as? LicenseSerial.VerifyError, .invalidCheck)
        }
    }

    func testVerifyRejectsWrongSecret() {
        let serial = LicenseSerial(string: Fixtures.validSerial)!
        XCTAssertThrowsError(
            try serial.verify(installId: Fixtures.installId, secret: "some-other-secret", now: Date())
        ) { error in
            XCTAssertEqual(error as? LicenseSerial.VerifyError, .invalidCheck)
        }
    }

    func testVerifyRejectsCorruptedPayload() {
        let parts = Fixtures.validSerial.split(separator: "-").map(String.init)
        var payload = Array(parts[3])
        payload[0] = payload[0] == "A" ? "B" : "A"
        let corrupted = [parts[0], parts[1], parts[2], String(payload), parts[4]].joined(separator: "-")
        let serial = LicenseSerial(string: corrupted)!
        XCTAssertThrowsError(
            try serial.verify(installId: Fixtures.installId, secret: Fixtures.testSecret, now: Date())
        ) { error in
            XCTAssertEqual(error as? LicenseSerial.VerifyError, .invalidCheck)
        }
    }

    func testVerifyRejectsMissingSecret() {
        let serial = LicenseSerial(string: Fixtures.validSerial)!
        XCTAssertThrowsError(
            try serial.verify(installId: Fixtures.installId, secret: nil, now: Date())
        ) { error in
            XCTAssertEqual(error as? LicenseSerial.VerifyError, .secretUnavailable)
        }
    }

    func testVerifyRejectsExpiredSerial() {
        let expired = LicenseSerial.compose(
            secret: Fixtures.testSecret, installId: Fixtures.installId,
            plan: .solo, expiry: "20200101", payload: Fixtures.fixedPayload
        )
        let serial = LicenseSerial(string: expired)!
        XCTAssertThrowsError(
            try serial.verify(installId: Fixtures.installId, secret: Fixtures.testSecret, now: Date())
        ) { error in
            XCTAssertEqual(error as? LicenseSerial.VerifyError, .expired)
        }
    }

    func testComputeCheckIsDeterministic() {
        let a = LicenseSerial.computeCheck(
            secret: Fixtures.testSecret, installId: Fixtures.installId,
            plan: .solo, expiry: Fixtures.futureExpiry, payload: Fixtures.fixedPayload
        )
        let b = LicenseSerial.computeCheck(
            secret: Fixtures.testSecret, installId: Fixtures.installId,
            plan: .solo, expiry: Fixtures.futureExpiry, payload: Fixtures.fixedPayload
        )
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.count, 8)
        XCTAssertEqual(a, a.lowercased())
    }

    func testDifferentPlansProduceDifferentChecks() {
        let solo = LicenseSerial.computeCheck(
            secret: Fixtures.testSecret, installId: Fixtures.installId,
            plan: .solo, expiry: Fixtures.futureExpiry, payload: Fixtures.fixedPayload
        )
        let team = LicenseSerial.computeCheck(
            secret: Fixtures.testSecret, installId: Fixtures.installId,
            plan: .team, expiry: Fixtures.futureExpiry, payload: Fixtures.fixedPayload
        )
        XCTAssertNotEqual(solo, team)
    }
}
