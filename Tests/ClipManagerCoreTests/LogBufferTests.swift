import XCTest
import ClipManagerCore

final class LogBufferTests: XCTestCase {

    func testAppendAndTail() {
        let buffer = LogBuffer(capacity: 10)
        buffer.append("a")
        buffer.append("b")
        buffer.append("c")
        XCTAssertEqual(buffer.tail(), "a\nb\nc")
        XCTAssertEqual(buffer.tail(2), "b\nc")
        XCTAssertEqual(buffer.lineCount, 3)
    }

    func testOverflowDropsOldestLines() {
        let buffer = LogBuffer(capacity: 3)
        for line in ["1", "2", "3", "4", "5"] {
            buffer.append(line)
        }
        XCTAssertEqual(buffer.lineCount, 3)
        XCTAssertEqual(buffer.tail(), "3\n4\n5")
    }

    func testTailClampsToAvailableLines() {
        let buffer = LogBuffer(capacity: 10)
        buffer.append("only")
        XCTAssertEqual(buffer.tail(100), "only")
    }

    func testTailRespectsExplicitCount() {
        let buffer = LogBuffer(capacity: 100)
        for i in 1...10 { buffer.append("line\(i)") }
        XCTAssertEqual(buffer.tail(5), "line6\nline7\nline8\nline9\nline10")
    }
}
