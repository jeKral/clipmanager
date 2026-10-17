import XCTest
import ClipManagerCore

final class LicenseStoreTests: XCTestCase {

    private var tempDir: URL!
    private var store: LicenseStore!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LicenseStoreTests-\(UUID().uuidString)")
        store = LicenseStore(baseDirectory: tempDir, secret: Fixtures.testSecret)
    }

    override func tearDownWithError() throws {
        store = nil
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
    }

    // MARK: - Install config

    func testFirstLaunchCreatesInstallId() {
        XCTAssertFalse(store.installId.isEmpty)
        XCTAssertNotNil(UUID(uuidString: store.installId))
    }

    func testInstallIdIsStableAcrossRestarts() {
        let id = store.installId
        let dir = tempDir
        let secret = Fixtures.testSecret

        // Simulate a relaunch: new store instance on the same directory.
        let reloaded = LicenseStore(baseDirectory: dir, secret: secret)
        XCTAssertEqual(reloaded.installId, id)
    }

    func testTelemetryTogglePersists() {
        store.setTelemetryEnabled(false)
        let reloaded = LicenseStore(baseDirectory: tempDir, secret: Fixtures.testSecret)
        XCTAssertEqual(reloaded.telemetryEnabled, false)
    }

    func testRelayURLPersistsAndNormalizesScheme() {
        store.setRelayURL("10.0.0.5:9999")
        XCTAssertEqual(store.relayURL, "http://10.0.0.5:9999")

        let reloaded = LicenseStore(baseDirectory: tempDir, secret: Fixtures.testSecret)
        XCTAssertEqual(reloaded.relayURL, "http://10.0.0.5:9999")
    }

    // MARK: - Activation

    /// A valid serial bound to this store's (random) installId.
    private func boundSerial() -> String {
        LicenseSerial.compose(
            secret: Fixtures.testSecret, installId: store.installId,
            plan: .solo, expiry: Fixtures.futureExpiry, payload: Fixtures.fixedPayload
        )
    }

    func testNoLicenseStartsBlocked() {
        XCTAssertTrue(store.secretConfigured)
        XCTAssertNil(store.license)
        XCTAssertEqual(store.decision.state, .blocked)
        XCTAssertFalse(store.decision.isMeasurementAllowed)
    }

    func testActivateValidSerial() throws {
        let serial = boundSerial()
        try store.activate(serial: serial)
        XCTAssertEqual(store.decision.state, .allowed)
        XCTAssertEqual(store.license?.plan, .solo)
        XCTAssertTrue(store.decision.isMeasurementAllowed)

        // Survives a relaunch.
        let reloaded = LicenseStore(baseDirectory: tempDir, secret: Fixtures.testSecret)
        XCTAssertEqual(reloaded.decision.state, .allowed)
        XCTAssertEqual(reloaded.license?.serial, serial)
    }

    func testActivateTrimsWhitespace() throws {
        try store.activate(serial: "  " + boundSerial().lowercased() + "\n")
        XCTAssertEqual(store.decision.state, .allowed)
    }

    func testActivateRejectsSerialBoundToAnotherInstall() {
        XCTAssertThrowsError(try store.activate(serial: Fixtures.otherInstallSerial)) { error in
            XCTAssertEqual(error as? LicenseSerial.VerifyError, .invalidCheck)
        }
        // Nothing persisted.
        XCTAssertNil(store.license)
        XCTAssertEqual(store.decision.state, .blocked)
    }

    func testActivateRejectsExpiredSerial() {
        let expired = LicenseSerial.compose(
            secret: Fixtures.testSecret, installId: store.installId,
            plan: .solo, expiry: "20200101"
        )
        XCTAssertThrowsError(try store.activate(serial: expired)) { error in
            XCTAssertEqual(error as? LicenseSerial.VerifyError, .expired)
        }
    }

    func testActivateRejectsGarbage() {
        XCTAssertThrowsError(try store.activate(serial: "totally-bogus"))
    }

    func testActivateFailsClosedWithoutSecret() throws {
        let noSecret = LicenseStore(baseDirectory: tempDir, secret: nil)
        XCTAssertThrowsError(try noSecret.activate(serial: Fixtures.validSerial)) { error in
            XCTAssertEqual(error as? LicenseSerial.VerifyError, .secretUnavailable)
        }
    }

    // MARK: - Remote results

    func testRemoteRevokedBlocksEvenWithValidLocalLicense() throws {
        try store.activate(serial: boundSerial())
        XCTAssertEqual(store.decision.state, .allowed)

        store.applyRemote(.revoked, note: "customer disputed")
        XCTAssertEqual(store.decision.state, .blocked)

        // The verdict is cached on disk → survives relaunch.
        let reloaded = LicenseStore(baseDirectory: tempDir, secret: Fixtures.testSecret)
        XCTAssertEqual(reloaded.decision.state, .blocked)
    }

    func testRemoteOkRestoresAllowed() throws {
        try store.activate(serial: boundSerial())
        store.applyRemote(.expired, note: nil)
        XCTAssertEqual(store.decision.state, .grace)

        store.applyRemote(.ok, note: nil)
        XCTAssertEqual(store.decision.state, .allowed)
    }

    func testRemoteUnknownDoesNotOverwriteCache() throws {
        try store.activate(serial: boundSerial())
        store.applyRemote(.ok, note: nil)
        store.applyRemote(.unknown, note: nil)
        XCTAssertEqual(store.remoteStatus, .ok)
        XCTAssertEqual(store.decision.state, .allowed)
    }

    // MARK: - Expiry phase (decider path)

    /// Bypasses `activate()` (which refuses expired serials) by writing the
    /// record directly, then checks the stored licence is evaluated against
    /// `now` — deterministically in the past, so the test never depends on
    /// the wall clock.
    private func storedRecord(expiry: String, plan: LicensePlan = .solo) throws -> LicenseStore {
        let serial = LicenseSerial.compose(
            secret: Fixtures.testSecret, installId: store.installId,
            plan: plan, expiry: expiry
        )
        let record = LicenseRecord(
            serial: serial,
            plan: plan,
            expiresAt: expiry,
            activatedAt: Date(timeIntervalSince1970: 0)
        )
        try AtomicFile.writeJSON(record, to: store.licenseURL)
        return LicenseStore(baseDirectory: tempDir, secret: Fixtures.testSecret)
    }

    func testLongExpiredLicenseIsBlocked() throws {
        // Expiry 2020-01-01 → grace window ended 2020-01-16, long ago.
        let reloaded = try storedRecord(expiry: "20200101")
        reloaded.refresh(now: Date())
        XCTAssertEqual(reloaded.decision.state, .blocked)
        XCTAssertFalse(reloaded.decision.isMeasurementAllowed)
    }

    func testReactivationReplacesStoredLicense() throws {
        let first = LicenseSerial.compose(
            secret: Fixtures.testSecret, installId: store.installId,
            plan: .solo, expiry: Fixtures.futureExpiry, payload: "QQQQQQQQQQQQQQQQQQ22"
        )
        let second = LicenseSerial.compose(
            secret: Fixtures.testSecret, installId: store.installId,
            plan: .team, expiry: Fixtures.futureExpiry, payload: "WWWWWWWWWWWWWWWWWW33"
        )
        try store.activate(serial: first)
        XCTAssertEqual(store.license?.plan, .solo)

        try store.activate(serial: second)
        XCTAssertEqual(store.license?.plan, .team)
        XCTAssertEqual(store.license?.serial, second)
    }
}
