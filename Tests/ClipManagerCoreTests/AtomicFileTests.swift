import XCTest
import ClipManagerCore

private struct Person: Codable, Equatable {
    let name: String
    let joined: Date
}

final class AtomicFileTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AtomicFileTests-\(UUID().uuidString)")
        try AtomicFile.ensureDirectory(dir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
        dir = nil
    }

    func testWriteAndReadRoundtrip() throws {
        let url = dir.appendingPathComponent("sub/payload.json")
        let value = Person(name: "Zdeněk", joined: Date(timeIntervalSince1970: 1_700_000_000))
        try AtomicFile.writeJSON(value, to: url)

        let loaded = try AtomicFile.readJSON(Person.self, from: url)
        XCTAssertEqual(loaded, value)
    }

    func testWriteCreatesParentDirectories() throws {
        let url = dir.appendingPathComponent("a/b/c/deep.json")
        try AtomicFile.writeJSON(["k": "v"], to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testOverwriteReplacesContent() throws {
        let url = dir.appendingPathComponent("data.json")
        try AtomicFile.writeJSON(["version": 1], to: url)
        try AtomicFile.writeJSON(["version": 2], to: url)

        let loaded = try AtomicFile.readJSON([String: Int].self, from: url)
        XCTAssertEqual(loaded["version"], 2)
    }

    func testNoTmpFileLeftBehind() throws {
        let url = dir.appendingPathComponent("data.json")
        try AtomicFile.writeJSON(["v": 1], to: url)
        try AtomicFile.writeJSON(["v": 2], to: url)

        let tmp = url.deletingLastPathComponent().appendingPathComponent("data.json.tmp")
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmp.path))
    }

    func testStaleTmpFileIsCleaned() throws {
        let url = dir.appendingPathComponent("data.json")
        let tmp = url.deletingLastPathComponent().appendingPathComponent("data.json.tmp")
        try Data("stale".utf8).write(to: tmp)

        try AtomicFile.writeJSON(["v": 1], to: url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmp.path))
    }

    func testTryReadReturnsNilForMissingFile() {
        let missing = dir.appendingPathComponent("nope.json")
        XCTAssertNil(AtomicFile.tryReadJSON(Person.self, from: missing))
    }

    func testTryReadReturnsNilForCorruptFile() throws {
        let url = dir.appendingPathComponent("corrupt.json")
        try Data("{ not json".utf8).write(to: url)
        XCTAssertNil(AtomicFile.tryReadJSON(Person.self, from: url))
    }

    func testDatesUseIso8601OnDisk() throws {
        let url = dir.appendingPathComponent("dated.json")
        let value = Person(name: "X", joined: Date(timeIntervalSince1970: 1_700_000_000))
        try AtomicFile.writeJSON(value, to: url)

        let raw = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(raw.contains("2023-11-14T"), "expected ISO-8601 date in \(raw)")
    }
}
