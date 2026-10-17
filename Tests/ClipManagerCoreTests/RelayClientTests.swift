import XCTest
import ClipManagerCore

/// In-process HTTP stub for RelayClient tests.
private final class StubURLProtocol: URLProtocol {

    struct Response {
        let status: Int
        let body: Data
    }

    private static let lock = NSLock()
    private static var _handler: ((URLRequest) -> Response?)?
    private static var _requests: [URLRequest] = []

    /// Return nil to simulate a network failure.
    static var handler: ((URLRequest) -> Response?)? {
        get { lock.lock(); defer { lock.unlock() }; return _handler }
        set { lock.lock(); defer { lock.unlock() }; _handler = newValue }
    }

    static var requests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }; return _requests
    }

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        _handler = nil
        _requests = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // This SDK delivers POST bodies via `httpBodyStream`, not `httpBody` —
        // read the stream back into `httpBody` so tests can inspect it.
        var request = self.request
        if request.httpBody == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data()
            let bufferSize = 65_536
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { buffer.deallocate() }
            while stream.hasBytesAvailable {
                let count = stream.read(buffer, maxLength: bufferSize)
                guard count > 0 else { break }
                data.append(buffer, count: count)
            }
            request.httpBody = data
        }

        StubURLProtocol.lock.lock()
        StubURLProtocol._requests.append(request)
        let handler = StubURLProtocol._handler
        StubURLProtocol.lock.unlock()

        guard let handler, let response = handler(request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }

        let http = HTTPURLResponse(
            url: request.url!,
            statusCode: response.status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class RelayClientTests: XCTestCase {

    private var client: RelayClient!

    override func setUpWithError() throws {
        StubURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        client = RelayClient(baseURL: URL(string: "http://relay.test")!, session: session)
    }

    private func json(_ object: some Encodable) -> Data {
        try! JSONEncoder().encode(object)
    }

    // MARK: - Heartbeat

    func testHeartbeatPostsToTelemetryEndpoint() async throws {
        StubURLProtocol.handler = { _ in .init(status: 200, body: Data("{}".utf8)) }

        let payload = Telemetry.currentHeartbeat(installId: Fixtures.installId, version: "1.0.0")
        try await client.sendHeartbeat(payload)

        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/v1/telemetry")

        let body = try XCTUnwrap(request.httpBody)
        let text = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(text.contains("\"app\":\"ClipManager\""))
        XCTAssertTrue(text.contains(Telemetry.anonymizedInstallId(Fixtures.installId)))
        XCTAssertFalse(text.contains(Fixtures.installId))
    }

    func testHeartbeatThrowsOnServerError() async {
        StubURLProtocol.handler = { _ in .init(status: 500, body: Data("{}".utf8)) }
        let payload = Telemetry.currentHeartbeat(installId: Fixtures.installId)

        do {
            try await client.sendHeartbeat(payload)
            XCTFail("expected a throw")
        } catch let error as RelayClient.RelayError {
            guard case .server(let code) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(code, 500)
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    // MARK: - License check

    func testLicenseCheckOk() async throws {
        StubURLProtocol.handler = { _ in .init(status: 200, body: self.json(["status": "ok"])) }

        let result = try await client.checkLicense(installId: Fixtures.installId, serial: "CLIP-SOLO-20991231-AAAAAAAAAAAAAAAAAAAA-aaaaaaaa")
        XCTAssertEqual(result.status, .ok)

        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.url?.path, "/api/v1/license")
        let components = try XCTUnwrap(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
        let query = components.queryItems ?? []
        XCTAssertEqual(query.first(where: { $0.name == "installId" })?.value, Fixtures.installId)
        XCTAssertEqual(query.first(where: { $0.name == "serial" })?.value, "CLIP-SOLO-20991231-AAAAAAAAAAAAAAAAAAAA-aaaaaaaa")
    }

    func testLicenseCheckRevoked() async throws {
        StubURLProtocol.handler = { _ in .init(status: 200, body: self.json(["status": "revoked", "note": "disputed"])) }
        let result = try await client.checkLicense(installId: Fixtures.installId, serial: "x")
        XCTAssertEqual(result.status, .revoked)
        XCTAssertEqual(result.note, "disputed")
    }

    func testLicenseCheck404IsUnknown() async throws {
        StubURLProtocol.handler = { _ in .init(status: 404, body: Data("{}".utf8)) }
        let result = try await client.checkLicense(installId: Fixtures.installId, serial: "x")
        XCTAssertEqual(result.status, .unknown)
    }

    func testLicenseCheckNetworkFailureIsUnknown() async throws {
        StubURLProtocol.handler = { _ in nil } // URLError
        let result = try await client.checkLicense(installId: Fixtures.installId, serial: "x")
        XCTAssertEqual(result.status, .unknown)
    }

    func testLicenseCheckServerErrorThrows() async {
        StubURLProtocol.handler = { _ in .init(status: 503, body: Data("{}".utf8)) }
        do {
            _ = try await client.checkLicense(installId: Fixtures.installId, serial: "x")
            XCTFail("expected a throw")
        } catch let error as RelayClient.RelayError {
            guard case .server(let code) = error else { return XCTFail("unexpected: \(error)") }
            XCTAssertEqual(code, 503)
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    // MARK: - Bug report

    struct BugResponseBody: Encodable {
        let ok: Bool
        let issueUrl: String?
    }

    func testBugReportReturnsIssueUrl() async throws {
        StubURLProtocol.handler = { _ in .init(
            status: 200,
            body: self.json(BugResponseBody(ok: true, issueUrl: "https://github.com/h0nyik/clipmanager/issues/42"))
        ) }

        let report = Telemetry.currentBugReport(installId: Fixtures.installId, message: "boom", log: "x")
        let url = try await client.sendBugReport(report)

        XCTAssertEqual(url?.absoluteString, "https://github.com/h0nyik/clipmanager/issues/42")
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.url?.path, "/api/v1/bug")
    }

    func testBugReportWithoutIssueReturnsNil() async throws {
        StubURLProtocol.handler = { _ in .init(status: 200, body: self.json(["ok": true])) }
        let report = Telemetry.currentBugReport(installId: Fixtures.installId, message: "boom", log: "x")
        let url = try await client.sendBugReport(report)
        XCTAssertNil(url)
    }
}
