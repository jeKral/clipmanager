import Foundation
import CryptoKit

// MARK: - Heartbeat payload

/// Anonymous telemetry heartbeat. Contains ONLY: app name, version, OS, OS
/// version, architecture, an ANONYMIZED installId (first 12 hex chars of
/// SHA-256) and a timestamp. No names, emails, paths or other user data.
public struct HeartbeatPayload: Codable, Equatable, Sendable {
    public let app: String
    public let version: String
    public let os: String
    public let osVersion: String
    public let arch: String
    /// Anonymized installId — first 12 hex chars of SHA-256(installId).
    public let installId: String
    /// ISO-8601 UTC timestamp.
    public let ts: String

    public init(app: String, version: String, os: String, osVersion: String, arch: String, installId: String, ts: String) {
        self.app = app
        self.version = version
        self.os = os
        self.osVersion = osVersion
        self.arch = arch
        self.installId = installId
        self.ts = ts
    }
}

// MARK: - Bug report payload

/// Error report. The installId here is the ANONYMIZED form as well — the
/// raw installId leaves the machine only via the license endpoint.
public struct BugReport: Codable, Equatable, Sendable {
    public let installId: String
    public let app: String
    public let version: String
    public let os: String
    public let osVersion: String
    public let arch: String
    public let message: String
    public let log: String
    public let ts: String

    public init(installId: String, app: String, version: String, os: String, osVersion: String, arch: String, message: String, log: String, ts: String) {
        self.installId = installId
        self.app = app
        self.version = version
        self.os = os
        self.osVersion = osVersion
        self.arch = arch
        self.message = message
        self.log = log
        self.ts = ts
    }
}

// MARK: - Telemetry

public enum Telemetry {

    public static let appName = "ClipManager"

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    public static func iso8601(_ date: Date) -> String {
        isoFormatter.string(from: date)
    }

    /// Anonymization: first 12 hex chars of SHA-256 of the raw installId.
    public static func anonymizedInstallId(_ raw: String) -> String {
        let digest = SHA256.hash(data: Data(raw.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(12))
    }

    public static func currentOSVersion() -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion)"
    }

    public static func currentArch() -> String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    public static func appVersion() -> String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0.0"
    }

    public static func currentHeartbeat(installId: String, version: String? = nil, now: Date = Date()) -> HeartbeatPayload {
        HeartbeatPayload(
            app: appName,
            version: version ?? appVersion(),
            os: "macOS",
            osVersion: currentOSVersion(),
            arch: currentArch(),
            installId: anonymizedInstallId(installId),
            ts: iso8601(now)
        )
    }

    public static func currentBugReport(
        installId: String,
        message: String,
        log: String,
        version: String? = nil,
        now: Date = Date()
    ) -> BugReport {
        BugReport(
            installId: anonymizedInstallId(installId),
            app: appName,
            version: version ?? appVersion(),
            os: "macOS",
            osVersion: currentOSVersion(),
            arch: currentArch(),
            message: message,
            log: log,
            ts: iso8601(now)
        )
    }
}
