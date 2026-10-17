import Foundation

/// Atomic local file persistence (tmp + rename) for config / license / cache
/// files. Every write goes to `<name>.tmp` in the same directory, is
/// synchronized, then atomically replaces the target via rename.
public enum AtomicFile {

    public static let jsonEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    public static let jsonDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Creates the directory (and parents) if needed and returns it.
    public static func ensureDirectory(_ url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    public static func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        try ensureDirectory(url.deletingLastPathComponent())
        let data = try jsonEncoder.encode(value)
        try writeData(data, to: url)
    }

    public static func writeData(_ data: Data, to url: URL) throws {
        try ensureDirectory(url.deletingLastPathComponent())
        let tmp = url.deletingLastPathComponent()
            .appendingPathComponent(url.lastPathComponent + ".tmp")

        if FileManager.default.fileExists(atPath: tmp.path) {
            try FileManager.default.removeItem(at: tmp)
        }
        try data.write(to: tmp)

        guard let handle = FileHandle(forWritingAtPath: tmp.path) else {
            throw CocoaError(.fileWriteUnknown)
        }
        defer { try? handle.close() }
        try handle.synchronize()

        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } else {
            try FileManager.default.moveItem(at: tmp, to: url)
        }
    }

    public static func readJSON<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let data = try Data(contentsOf: url)
        return try jsonDecoder.decode(type, from: data)
    }

    /// Best-effort read: returns nil when the file is missing or unreadable.
    public static func tryReadJSON<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? readJSON(type, from: url)
    }
}
