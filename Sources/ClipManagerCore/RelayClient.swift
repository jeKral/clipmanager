import Foundation

/// Minimal async HTTP client for the relay service.
///
/// Endpoints:
/// - `POST /api/v1/telemetry`  — anonymous heartbeat
/// - `GET  /api/v1/license?installId=&serial=` — remote license check
/// - `POST /api/v1/bug`        — error report
public final class RelayClient {

    public struct LicenseResponse: Equatable, Sendable {
        public let status: RemoteLicenseStatus
        public let note: String?
    }

    private let session: URLSession
    private let baseURL: URL
    private let timeout: TimeInterval

    public init(baseURL: URL, session: URLSession = .shared, timeout: TimeInterval = 15) {
        self.baseURL = baseURL
        self.session = session
        self.timeout = timeout
    }

    public enum RelayError: Error, LocalizedError {
        case badURL
        case badResponse
        case server(code: Int)

        public var errorDescription: String? {
            switch self {
            case .badURL: return "Neplatná adresa relay sluzby."
            case .badResponse: return "Relay vrátil neplatnou odpověď."
            case .server(let code): return "Relay vrátil chybu \(code)."
            }
        }
    }

    private struct LicenseEnvelope: Decodable {
        let status: String
        let note: String?
    }

    private struct BugEnvelope: Decodable {
        let ok: Bool?
        let issueUrl: String?
    }

    // MARK: - Telemetry

    public func sendHeartbeat(_ payload: HeartbeatPayload) async throws {
        _ = try await post(path: "/api/v1/telemetry", body: payload)
    }

    // MARK: - License check

    public func checkLicense(installId: String, serial: String) async throws -> LicenseResponse {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/api/v1/license"
        components?.queryItems = [
            URLQueryItem(name: "installId", value: installId),
            URLQueryItem(name: "serial", value: serial),
        ]
        guard let url = components?.url else { throw RelayError.badURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = timeout

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw RelayError.badResponse }
            guard (200..<300).contains(http.statusCode) else {
                if http.statusCode == 404 {
                    return LicenseResponse(status: .unknown, note: nil)
                }
                throw RelayError.server(code: http.statusCode)
            }
            guard let envelope = try? JSONDecoder().decode(LicenseEnvelope.self, from: data) else {
                throw RelayError.badResponse
            }
            let status = RemoteLicenseStatus(rawValue: envelope.status) ?? .unknown
            return LicenseResponse(status: status, note: envelope.note)
        } catch let error as URLError {
            // Relay unreachable → local state stands.
            Log.debug("license check failed: \(error.localizedDescription)")
            return LicenseResponse(status: .unknown, note: nil)
        }
    }

    // MARK: - Bug report

    /// Returns the GitHub issue URL when the relay created one, nil otherwise.
    public func sendBugReport(_ report: BugReport) async throws -> URL? {
        let data = try await post(path: "/api/v1/bug", body: report)
        guard let envelope = try? JSONDecoder().decode(BugEnvelope.self, from: data),
              let issue = envelope.issueUrl, !issue.isEmpty else { return nil }
        return URL(string: issue)
    }

    // MARK: - Internals

    private func url(path: String) throws -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = path
        guard let url = components?.url else { throw RelayError.badURL }
        return url
    }

    private func post<T: Encodable>(path: String, body: T) async throws -> Data {
        let request = try makePostRequest(path: path, body: body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw RelayError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw RelayError.server(code: http.statusCode)
        }
        return data
    }

    private func makePostRequest<T: Encodable>(path: String, body: T) throws -> URLRequest {
        var request = URLRequest(url: try url(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }
}
