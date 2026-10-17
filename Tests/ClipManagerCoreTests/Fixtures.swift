import XCTest
import ClipManagerCore

/// Shared fixtures for the license test suite.
///
/// `testSecret` is a FIXED secret used only by the unit tests (and the
/// golden roundtrip with Scripts/generate_license.py) — it is deliberately
/// not the build-time `CLIP_LICENSE_SECRET`, so the tests also pass when
/// the binary was built fail-closed (secret = nil).
enum Fixtures {

    static let testSecret = "unit-test-secret-do-not-ship"

    /// A well-formed lower-case hyphenated installation UUID.
    static let installId = "a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d"

    /// Another installId (for negative binding tests).
    static let otherInstallId = "ffffffff-eeee-4ddd-9ccc-888877776666"

    /// Far-future expiry (always "valid" at test time).
    static let futureExpiry = "20991231"

    /// A fixed 20-char payload from the license alphabet.
    static let fixedPayload = "ABCDEFGHJKLMNPQR2345"

    /// A valid serial for `installId` (far-future, plan solo).
    static var validSerial: String {
        LicenseSerial.compose(
            secret: testSecret,
            installId: installId,
            plan: .solo,
            expiry: futureExpiry,
            payload: fixedPayload
        )
    }

    /// A valid serial bound to `otherInstallId`.
    static var otherInstallSerial: String {
        LicenseSerial.compose(
            secret: testSecret,
            installId: otherInstallId,
            plan: .solo,
            expiry: futureExpiry,
            payload: fixedPayload
        )
    }
}
