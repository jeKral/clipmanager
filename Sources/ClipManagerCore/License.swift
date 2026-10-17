import Foundation
import CryptoKit

// MARK: - LicensePlan

/// Business plan encoded in the `PLAN` part of the serial number.
public enum LicensePlan: String, Codable, CaseIterable, Sendable {
    case solo = "SOLO"
    case team = "TEAM"
    case firma = "FIRMA"

    public var displayName: String {
        switch self {
        case .solo:  return "Solo"
        case .team:  return "Team"
        case .firma: return "Firma"
        }
    }
}

// MARK: - LicenseSerial

/// Serial number format: `{PREFIX}-{PLAN}-{EXPIRY YYYYMMDD}-{PAYLOAD 20}-{CHECK 8}`
///
/// - `PREFIX`  — `CLIP` (application identifier)
/// - `PLAN`    — `SOLO` | `TEAM` | `FIRMA`
/// - `EXPIRY`  — expiry date, valid through the end of that calendar day
/// - `PAYLOAD` — 20 random chars from an unambiguous alphabet (A–Z without
///               `I`/`O`, plus `23456789`; no `0`/`1`/`I`/`O`)
/// - `CHECK`   — first 8 hex chars of `HMAC-SHA256(secret, "installId|plan|expiry|payload")`
///               where `installId` is the canonical lower-case hyphenated UUID.
///
/// The checksum binds the serial to a specific installation, so a serial
/// issued for one `installId` is rejected everywhere else.
public struct LicenseSerial: Equatable, Sendable {

    public static let prefix = "CLIP"
    /// 32-character alphabet: A–Z without I, O + digits 23456789.
    public static let payloadAlphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    public static let payloadLength = 20
    public static let checkLength = 8
    /// Days the app keeps measuring after the license expires.
    public static let graceDays = 14

    public let plan: LicensePlan
    /// "YYYYMMDD"
    public let expiry: String
    public let payload: String
    /// 8 lowercase hex chars.
    public let check: String

    /// Canonical form: `CLIP-{PLAN}-{EXPIRY}-{PAYLOAD}-{check lowercase}`.
    public var normalizedString: String {
        "\(LicenseSerial.prefix)-\(plan.rawValue)-\(expiry)-\(payload)-\(check)"
    }

    /// Parses and validates the FORMAT only (no checksum, no installId, no expiry).
    public init?(string: String) {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 5 else { return nil }
        guard String(parts[0]) == LicenseSerial.prefix else { return nil }
        guard let plan = LicensePlan(rawValue: String(parts[1])) else { return nil }
        let expiry = String(parts[2])
        guard Self.isValidExpiry(expiry) else { return nil }
        let payload = String(parts[3])
        guard payload.count == Self.payloadLength,
              payload.allSatisfy({ Self.payloadAlphabet.contains($0) }) else { return nil }
        let check = String(parts[4]).lowercased()
        guard check.count == Self.checkLength, check.allSatisfy({ $0.isHexDigit }) else { return nil }
        self.plan = plan
        self.expiry = expiry
        self.payload = payload
        self.check = check
    }

    // MARK: Expiry helpers

    private static func isValidExpiry(_ s: String) -> Bool {
        guard s.count == 8, s.allSatisfy({ $0.isNumber }) else { return false }
        guard let y = Int(s.prefix(4)), let m = Int(s.dropFirst(4).prefix(2)), let d = Int(s.dropFirst(6)) else {
            return false
        }
        guard y >= 2000, m >= 1, m <= 12, d >= 1 else { return false }
        // Reject impossible dates like 2026-02-30: the calendar would roll them over.
        let cal = Calendar.current
        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = d
        guard let date = cal.date(from: comps) else { return false }
        let back = cal.dateComponents([.year, .month, .day], from: date)
        return back.year == y && back.month == m && back.day == d
    }

    /// Start of the expiry day in the local time zone.
    public var expiryDate: Date? {
        guard let y = Int(expiry.prefix(4)),
              let m = Int(expiry.dropFirst(4).prefix(2)),
              let d = Int(expiry.dropFirst(6)) else { return nil }
        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = d
        return Calendar.current.date(from: comps)
    }

    // MARK: Install ID

    /// Canonical form of an installation UUID: lower-case, hyphenated.
    /// Accepts hyphenated (36 chars) or plain 32-hex input, either case —
    /// matching Python's `uuid.UUID`.
    public static func normalizedInstallId(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let uuid = UUID(uuidString: trimmed) {
            return uuid.uuidString.lowercased()
        }
        guard trimmed.count == 32, trimmed.allSatisfy({ $0.isHexDigit }) else { return nil }
        return "\(trimmed.prefix(8))-\(trimmed.dropFirst(8).prefix(4))-\(trimmed.dropFirst(12).prefix(4))-\(trimmed.dropFirst(16).prefix(4))-\(trimmed.dropFirst(20))"
    }

    // MARK: HMAC

    /// `first 8 hex chars of HMAC-SHA256(secret, "installId|plan|expiry|payload")`
    public static func computeCheck(
        secret: String,
        installId: String,
        plan: LicensePlan,
        expiry: String,
        payload: String
    ) -> String {
        let message = "\(installId)|\(plan.rawValue)|\(expiry)|\(payload)"
        let key = HMAC<SHA256>.Key(data: Data(secret.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
        return mac.prefix(4).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Verify (offline)

    public enum VerifyError: Error, Equatable, LocalizedError {
        case invalidFormat
        case invalidCheck          // checksum mismatch — also covers a serial bound to another installId
        case expired
        case secretUnavailable     // the binary was built without a license secret

        public var errorDescription: String? {
            switch self {
            case .invalidFormat:     return "Neplatný formát sériového čísla."
            case .invalidCheck:      return "Sériové číslo neodpovídá této instalaci (kontrolní kód nesešel)."
            case .expired:           return "Sériové číslo je již vypršelé."
            case .secretUnavailable: return "Licenční systém není nakonfigurován (chybí HMAC secret)."
            }
        }
    }

    /// Offline verification: format (guaranteed by init) + installId binding via HMAC + expiry.
    /// Zero latency, works without network.
    public func verify(installId: String, secret: String?, now: Date = Date()) throws {
        guard let secret else { throw VerifyError.secretUnavailable }

        guard let canonical = LicenseSerial.normalizedInstallId(installId) else {
            throw VerifyError.invalidFormat
        }

        // Expiry first: an expired serial must not be (re-)activated.
        if let expiryDate = self.expiryDate {
            let cal = Calendar.current
            let endOfExpiryDay = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: expiryDate)) ?? expiryDate
            if now >= endOfExpiryDay { throw VerifyError.expired }
        }

        let expected = LicenseSerial.computeCheck(
            secret: secret,
            installId: canonical,
            plan: plan,
            expiry: expiry,
            payload: payload
        )
        guard expected == check else { throw VerifyError.invalidCheck }
    }

    // MARK: Compose (used by tests; production generation lives in Scripts/generate_license.py)

    public static func compose(
        secret: String,
        installId: String,
        plan: LicensePlan,
        expiry: String,
        payload: String? = nil
    ) -> String {
        let p = payload ?? (0..<Self.payloadLength).map { _ in String(Self.payloadAlphabet.randomElement()!) }.joined()
        let check = computeCheck(secret: secret, installId: installId, plan: plan, expiry: expiry, payload: p)
        return "\(prefix)-\(plan.rawValue)-\(expiry)-\(p)-\(check)"
    }
}

// MARK: - Remote license status (relay)

/// Status returned by the relay's license endpoint, cached on disk so the
/// decision works offline too. `unknown` (relay unreachable / serial not in
/// registry) keeps the local decision in effect.
public enum RemoteLicenseStatus: String, Codable, Sendable {
    case ok
    case expired
    case revoked
    case unknown
}

// MARK: - License decision

/// Outcome of the offline + remote-aware licensing decision.
public struct LicenseDecision: Equatable, Sendable {
    public enum State: String, Equatable, Sendable {
        case allowed  // valid license
        case grace    // expired, 14-day grace window — measuring still works
        case blocked  // inactive / expired after grace / revoked
    }

    public let state: State
    public let plan: LicensePlan?
    public let expiresAt: Date?
    /// Only meaningful in `.grace` — whole days left in the grace window.
    public let graceDaysRemaining: Int?
    /// Czech, user-facing explanation.
    public let reason: String

    public init(
        state: State,
        plan: LicensePlan?,
        expiresAt: Date?,
        graceDaysRemaining: Int?,
        reason: String
    ) {
        self.state = state
        self.plan = plan
        self.expiresAt = expiresAt
        self.graceDaysRemaining = graceDaysRemaining
        self.reason = reason
    }

    public var isMeasurementAllowed: Bool { state != .blocked }
}

public enum LicenseDecider {

    /// Pure decision function.
    ///
    /// Rules:
    /// 1. Remote `revoked` always wins → blocked.
    /// 2. No stored license → blocked ("inactive").
    /// 3. Local phase: valid (`now < end of expiry day`) → grace (`+14 days`)
    ///    → blocked.
    /// 4. Remote `expired` while local still says valid (clock skew) → demote
    ///    to grace. Remote `unknown`/nil → local state stands.
    public static func decide(
        license: LicenseRecord?,
        remote: RemoteLicenseStatus?,
        now: Date,
        calendar: Calendar = .current
    ) -> LicenseDecision {
        if remote == .revoked {
            return LicenseDecision(
                state: .blocked,
                plan: license?.plan,
                expiresAt: license.flatMap { $0.expiryDate },
                graceDaysRemaining: nil,
                reason: "Licence byla zrušena administrátorem."
            )
        }

        guard let license, let serial = LicenseSerial(string: license.serial), let expiryStart = serial.expiryDate else {
            let reason: String
            if license == nil {
                reason = "Licence není aktivována. Zadejte sériové číslo v Nastavení."
            } else {
                reason = "Uložená licence je neplatná."
            }
            return LicenseDecision(state: .blocked, plan: nil, expiresAt: nil, graceDaysRemaining: nil, reason: reason)
        }

        let expiryEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: expiryStart))!
        let graceEnd = calendar.date(byAdding: .day, value: LicenseSerial.graceDays, to: expiryEnd)!

        var phase: Phase
        if now < expiryEnd {
            phase = .valid
        } else if now < graceEnd {
            phase = .grace
        } else {
            phase = .blocked
        }
        if remote == .expired, phase == .valid {
            phase = .grace
        }

        switch phase {
        case .valid:
            let formatter = DateFormatter()
            formatter.dateFormat = "d. M. yyyy"
            formatter.locale = Locale(identifier: "cs_CZ")
            return LicenseDecision(
                state: .allowed,
                plan: serial.plan,
                expiresAt: expiryStart,
                graceDaysRemaining: nil,
                reason: "Licence je platná do \(formatter.string(from: expiryStart))."
            )

        case .grace:
            let remaining = max(0, Int(ceil(graceEnd.timeIntervalSince(now) / 86_400)))
            return LicenseDecision(
                state: .grace,
                plan: serial.plan,
                expiresAt: expiryStart,
                graceDaysRemaining: remaining,
                reason: "Licence vypršela. Běží milostné období — zbývá \(remaining) \(daysWord(remaining))."
            )

        case .blocked:
            return LicenseDecision(
                state: .blocked,
                plan: serial.plan,
                expiresAt: expiryStart,
                graceDaysRemaining: 0,
                reason: "Licence vypršela a milostné období (14 dní) je ukončeno."
            )
        }
    }

    private enum Phase { case valid, grace, blocked }

    /// Czech plural: 1 den / 2 dny / 3 dny / 4 dny / 5 dní / 11 dní ...
    static func daysWord(_ n: Int) -> String {
        let d = n % 10
        let t = n % 100
        if t >= 11 && t <= 14 { return "dní" }
        switch d {
        case 1: return "den"
        case 2...4: return "dny"
        default: return "dní"
        }
    }
}
