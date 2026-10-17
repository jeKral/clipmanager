import Foundation
import Combine

// MARK: - Persisted models

/// Local installation config. `installId` is a UUID v4 created on first
/// launch; it identifies the installation, not the hardware.
public struct InstallConfig: Codable, Equatable, Sendable {
    public let installId: String
    public var relayURL: String
    public var telemetryEnabled: Bool

    public init(installId: String, relayURL: String = defaultRelayURL, telemetryEnabled: Bool = true) {
        self.installId = installId
        self.relayURL = relayURL
        self.telemetryEnabled = telemetryEnabled
    }

    public static let defaultRelayURL = "http://127.0.0.1:8787"
}

/// Persisted license state.
public struct LicenseRecord: Codable, Equatable, Sendable {
    public let serial: String
    public let plan: LicensePlan
    /// "YYYYMMDD"
    public let expiresAt: String
    public let activatedAt: Date

    public init(serial: String, plan: LicensePlan, expiresAt: String, activatedAt: Date) {
        self.serial = serial
        self.plan = plan
        self.expiresAt = expiresAt
        self.activatedAt = activatedAt
    }

    public var expiryDate: Date? {
        LicenseSerial(string: serial)?.expiryDate
    }
}

/// Cached result of the remote (relay) license check — lets the decision
/// work offline.
public struct RemoteLicenseCache: Codable, Equatable, Sendable {
    public let status: RemoteLicenseStatus
    public let note: String?
    public let checkedAt: Date
}

// MARK: - LicenseStore

/// Owns the persistent licensing state (config, license, remote cache), all
/// written atomically to JSON files. Re-publishes `decision` whenever the
/// inputs change, so the UI and the monitoring gate react automatically.
public final class LicenseStore: ObservableObject {

    public static let defaultDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent("ClipManager", isDirectory: true)
    }()

    public let baseDirectory: URL
    private let secret: String?
    private let calendar: Calendar

    @Published public private(set) var config: InstallConfig
    @Published public private(set) var license: LicenseRecord?
    @Published public private(set) var remoteCache: RemoteLicenseCache?
    @Published public private(set) var decision: LicenseDecision

    // MARK: - Init

    public convenience init(
        baseDirectory: URL? = nil,
        secret: String? = SecretConfig.licenseSecret,
        calendar: Calendar = .current
    ) {
        let dir = baseDirectory ?? LicenseStore.defaultDirectory
        var fallback = dir
        do {
            _ = try AtomicFile.ensureDirectory(dir)
        } catch {
            fallback = FileManager.default.temporaryDirectory
                .appendingPathComponent("ClipManager-\(UUID().uuidString.prefix(8))", isDirectory: true)
            _ = try? AtomicFile.ensureDirectory(fallback)
        }
        self.init(
            baseDirectory: fallback,
            secret: secret,
            calendar: calendar,
            config: Self.loadOrCreateConfig(dir: fallback),
            license: AtomicFile.tryReadJSON(LicenseRecord.self, from: fallback.appendingPathComponent("license.json")),
            remoteCache: AtomicFile.tryReadJSON(RemoteLicenseCache.self, from: fallback.appendingPathComponent("license_remote.json"))
        )
    }

    private init(
        baseDirectory: URL,
        secret: String?,
        calendar: Calendar,
        config: InstallConfig,
        license: LicenseRecord?,
        remoteCache: RemoteLicenseCache?
    ) {
        self.baseDirectory = baseDirectory
        self.secret = secret
        self.calendar = calendar
        self.config = config
        self.license = license
        self.remoteCache = remoteCache
        self.decision = LicenseDecider.decide(license: license, remote: remoteCache?.status, now: Date(), calendar: calendar)
    }

    private static func loadOrCreateConfig(dir: URL) -> InstallConfig {
        let url = dir.appendingPathComponent("config.json")
        if let existing = AtomicFile.tryReadJSON(InstallConfig.self, from: url) {
            return existing
        }
        let fresh = InstallConfig(installId: UUID().uuidString.lowercased())
        try? AtomicFile.writeJSON(fresh, to: url)
        return fresh
    }

    // MARK: - Accessors

    public var installId: String { config.installId }
    public var relayURL: String { config.relayURL }
    public var telemetryEnabled: Bool { config.telemetryEnabled }
    public var remoteStatus: RemoteLicenseStatus? { remoteCache?.status }
    public var secretConfigured: Bool { secret != nil }

    public var relayBaseURL: URL? {
        URL(string: relayURL)
    }

    public var configURL: URL { baseDirectory.appendingPathComponent("config.json") }
    public var licenseURL: URL { baseDirectory.appendingPathComponent("license.json") }
    public var remoteURL: URL { baseDirectory.appendingPathComponent("license_remote.json") }

    // MARK: - Settings mutations

    public func setTelemetryEnabled(_ enabled: Bool) {
        guard config.telemetryEnabled != enabled else { return }
        config.telemetryEnabled = enabled
        saveConfig()
    }

    public func setRelayURL(_ raw: String) {
        var url = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !url.isEmpty && !url.lowercased().hasPrefix("http://") && !url.lowercased().hasPrefix("https://") {
            url = "http://" + url
        }
        guard !url.isEmpty, url != config.relayURL else { return }
        config.relayURL = url
        saveConfig()
    }

    // MARK: - Activation

    /// Verifies the serial offline (format + HMAC binding to this installId
    /// + expiry) and persists it. Throws `LicenseSerial.VerifyError`.
    public func activate(serial rawSerial: String, now: Date = Date()) throws {
        let cleaned = rawSerial.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let serial = LicenseSerial(string: cleaned) else {
            throw LicenseSerial.VerifyError.invalidFormat
        }
        try serial.verify(installId: installId, secret: secret, now: now)
        let record = LicenseRecord(
            serial: serial.normalizedString,
            plan: serial.plan,
            expiresAt: serial.expiry,
            activatedAt: now
        )
        try AtomicFile.writeJSON(record, to: licenseURL)
        license = record
        recomputeDecision(now: now)
    }

    // MARK: - Remote results

    /// Caches the relay's verdict on disk (so the decision works offline)
    /// and re-evaluates. Remote `revoked` wins over local validity.
    public func applyRemote(_ status: RemoteLicenseStatus, note: String?, at date: Date = Date()) {
        // `unknown` = relay unreachable / serial not found. It must not clobber a
        // previous verdict on disk (e.g. `revoked`) — that would silently
        // unblock a blocked installation.
        guard status != .unknown else { return }
        let cache = RemoteLicenseCache(status: status, note: note, checkedAt: date)
        remoteCache = cache
        try? AtomicFile.writeJSON(cache, to: remoteURL)
        recomputeDecision(now: date)
    }

    /// Re-evaluates with a fresh `now` (day boundaries, grace countdown).
    public func refresh(now: Date = Date()) {
        recomputeDecision(now: now)
    }

    // MARK: - Internals

    private func saveConfig() {
        try? AtomicFile.writeJSON(config, to: configURL)
    }

    private func recomputeDecision(now: Date) {
        let new = LicenseDecider.decide(
            license: license,
            remote: remoteCache?.status,
            now: now,
            calendar: calendar
        )
        if new != decision {
            decision = new
        }
    }
}
