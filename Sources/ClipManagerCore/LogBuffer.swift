import Foundation

/// Thread-safe ring buffer of recent log lines, used for bug reports.
public final class LogBuffer: @unchecked Sendable {

    public static let shared = LogBuffer()

    public let capacity: Int
    private var lines: [String] = []
    private let lock = NSLock()

    public init(capacity: Int = 200) {
        self.capacity = max(1, capacity)
    }

    public func append(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        lines.append(line)
        if lines.count > capacity {
            lines.removeFirst(lines.count - capacity)
        }
    }

    /// Last `count` lines joined with newlines (oldest first).
    public func tail(_ count: Int = 200) -> String {
        lock.lock()
        defer { lock.unlock() }
        return lines.suffix(max(0, count)).joined(separator: "\n")
    }

    public var lineCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return lines.count
    }
}

/// Tiny logging facade: prints to the console and feeds the ring buffer.
public enum Log {

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return f
    }()

    static func write(_ level: String, _ message: String) {
        let line = "[\(formatter.string(from: Date()))] \(level) \(message)"
        LogBuffer.shared.append(line)
        switch level {
        case "ERROR":
            FileHandle.standardError.write(Data((line + "\n").utf8))
        default:
            print(line)
        }
    }

    public static func info(_ message: String) { write("INFO", message) }
    public static func debug(_ message: String) { write("DEBUG", message) }
    public static func error(_ message: String) { write("ERROR", message) }
}
