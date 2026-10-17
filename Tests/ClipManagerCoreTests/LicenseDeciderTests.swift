import XCTest
@testable import ClipManagerCore

final class LicenseDeciderTests: XCTestCase {

    // MARK: - Helpers

    private func serial(expiry: String, plan: LicensePlan = .solo) -> String {
        LicenseSerial.compose(
            secret: Fixtures.testSecret, installId: Fixtures.installId,
            plan: plan, expiry: expiry
        )
    }

    private func record(expiry: String, plan: LicensePlan = .solo, now: Date) -> LicenseRecord {
        LicenseRecord(
            serial: serial(expiry: expiry, plan: plan),
            plan: plan,
            expiresAt: expiry,
            activatedAt: now
        )
    }

    private func startOfDay(_ year: Int, _ month: Int, _ day: Int) -> Date {
        let cal = Calendar.current
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day
        return cal.startOfDay(for: cal.date(from: comps)!)
    }

    // MARK: - No license

    func testNoLicenseIsBlocked() {
        let decision = LicenseDecider.decide(license: nil, remote: nil, now: Date())
        XCTAssertEqual(decision.state, .blocked)
        XCTAssertFalse(decision.isMeasurementAllowed)
    }

    // MARK: - Valid

    func testValidLicenseIsAllowed() {
        let now = startOfDay(2026, 10, 16)
        let license = record(expiry: "20261231", now: now)
        let decision = LicenseDecider.decide(license: license, remote: nil, now: now)
        XCTAssertEqual(decision.state, .allowed)
        XCTAssertEqual(decision.plan, .solo)
        XCTAssertTrue(decision.isMeasurementAllowed)
    }

    func testValidUntilEndOfExpiryDay() {
        // 2026-12-31 23:59 on the expiry day itself must still be allowed.
        let cal = Calendar.current
        let expiryEnd = cal.startOfDay(for: startOfDay(2026, 12, 31))
        let lastSecond = cal.date(byAdding: .second, value: -1, to: cal.date(byAdding: .day, value: 1, to: expiryEnd)!)!
        let license = record(expiry: "20261231", now: lastSecond)
        let decision = LicenseDecider.decide(license: license, remote: nil, now: lastSecond)
        XCTAssertEqual(decision.state, .allowed)
    }

    // MARK: - Grace period

    func testOneDayAfterExpiryIsGrace() {
        // Expiry 2026-10-01 → grace runs through end of 2026-10-15.
        let now = cal.date(byAdding: .day, value: 1, to: startOfDay(2026, 10, 1))!
        let license = record(expiry: "20261001", now: now)
        let decision = LicenseDecider.decide(license: license, remote: nil, now: now)
        XCTAssertEqual(decision.state, .grace)
        XCTAssertEqual(decision.graceDaysRemaining, 14)
        XCTAssertTrue(decision.isMeasurementAllowed)
    }

    func testLastGraceDay() {
        // 2026-10-15 23:59 — still inside the 14-day window (ends 2026-10-16 00:00).
        let cal = Calendar.current
        let graceEnd = cal.date(byAdding: .day, value: 15, to: startOfDay(2026, 10, 1))!
        let now = cal.date(byAdding: .second, value: -1, to: graceEnd)!
        let license = record(expiry: "20261001", now: now)
        let decision = LicenseDecider.decide(license: license, remote: nil, now: now)
        XCTAssertEqual(decision.state, .grace)
    }

    func testAfterGraceIsBlocked() {
        let now = cal.date(byAdding: .day, value: 16, to: startOfDay(2026, 10, 1))!
        let license = record(expiry: "20261001", now: now)
        let decision = LicenseDecider.decide(license: license, remote: nil, now: now)
        XCTAssertEqual(decision.state, .blocked)
        XCTAssertFalse(decision.isMeasurementAllowed)
    }

    // MARK: - Remote override

    func testRemoteRevokedAlwaysWins() {
        let now = startOfDay(2026, 10, 16)
        let license = record(expiry: "20261231", now: now)
        let decision = LicenseDecider.decide(license: license, remote: .revoked, now: now)
        XCTAssertEqual(decision.state, .blocked)
    }

    func testRemoteRevokedWinsOverNoLicense() {
        let decision = LicenseDecider.decide(license: nil, remote: .revoked, now: Date())
        XCTAssertEqual(decision.state, .blocked)
    }

    func testRemoteExpiredDemotesValidToGrace() {
        let now = startOfDay(2026, 10, 16)
        let license = record(expiry: "20261231", now: now)
        let decision = LicenseDecider.decide(license: license, remote: .expired, now: now)
        XCTAssertEqual(decision.state, .grace)
    }

    func testRemoteUnknownKeepsLocalState() {
        let now = startOfDay(2026, 10, 16)
        let license = record(expiry: "20261231", now: now)
        let decision = LicenseDecider.decide(license: license, remote: .unknown, now: now)
        XCTAssertEqual(decision.state, .allowed)
    }

    func testRemoteOkOnExpiredLicenseStaysPhaseCorrect() {
        let now = cal.date(byAdding: .day, value: 1, to: startOfDay(2026, 10, 1))!
        let license = record(expiry: "20261001", now: now)
        let decision = LicenseDecider.decide(license: license, remote: .ok, now: now)
        XCTAssertEqual(decision.state, .grace)
    }

    // MARK: - Plan display

    func testPlanRoundtrip() {
        let now = startOfDay(2026, 10, 16)
        let license = record(expiry: "20261231", plan: .firma, now: now)
        let decision = LicenseDecider.decide(license: license, remote: nil, now: now)
        XCTAssertEqual(decision.plan, .firma)
        XCTAssertEqual(decision.plan?.displayName, "Firma")
    }

    // MARK: - Czech plural (grace reason)

    func testDaysWordPlural() {
        XCTAssertEqual(LicenseDecider.daysWord(1), "den")
        XCTAssertEqual(LicenseDecider.daysWord(2), "dny")
        XCTAssertEqual(LicenseDecider.daysWord(11), "dní")
        XCTAssertEqual(LicenseDecider.daysWord(14), "dní")
        XCTAssertEqual(LicenseDecider.daysWord(21), "den")
    }

    private var cal: Calendar { Calendar.current }
}
