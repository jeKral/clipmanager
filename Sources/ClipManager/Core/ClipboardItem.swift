import AppKit
import CryptoKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - ClipboardItem

struct ClipboardItem: Identifiable, Codable, Equatable {
    let id: UUID
    let timestamp: Date
    var isPinned: Bool

    /// All pasteboard types present when this item was copied
    var pasteboardTypes: [String]

    /// Inline data for small items (key: UTI, value: base64)
    var inlineData: [String: String]

    /// Filenames of large binary data in the item's data directory (key: UTI, value: filename)
    var fileData: [String: String]

    /// Cached display text for text-like content
    var displayText: String?

    /// Category for icon / color / grouping
    var category: Category

    /// Deterministic SHA-256 over the item's payload (inline + file data).
    /// Used for reliable deduplication — the old compare read
    /// `inlineData.values.first` (nondeterministic order) and skipped large
    /// file-based data entirely, so identical images were stored twice.
    var contentHash: String?

    // MARK: - Category

    enum Category: String, Codable {
        case plainText
        case richText
        case html
        case image
        case fileURL
        case color
        case other

        var icon: String {
            switch self {
            case .plainText:  return "doc.text"
            case .richText:   return "doc.richtext"
            case .html:       return "chevron.left.forwardslash.chevron.right"
            case .image:      return "photo"
            case .fileURL:    return "folder"
            case .color:      return "paintpalette"
            case .other:      return "doc"
            }
        }

        var color: Color {
            switch self {
            case .plainText:  return .blue
            case .richText:   return .indigo
            case .html:       return .orange
            case .image:      return .green
            case .fileURL:    return .yellow
            case .color:      return .pink
            case .other:      return Color(.systemGray)
            }
        }
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        isPinned: Bool = false,
        pasteboardTypes: [String],
        inlineData: [String: String],
        fileData: [String: String],
        displayText: String?,
        category: Category,
        contentHash: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.isPinned = isPinned
        self.pasteboardTypes = pasteboardTypes
        self.inlineData = inlineData
        self.fileData = fileData
        self.displayText = displayText
        self.category = category
        self.contentHash = contentHash
    }

    // MARK: - Helpers

    var humanReadableSize: String {
        let totalBytes = inlineData.values.reduce(0) { $0 + $1.count }
        return ByteCountFormatter.string(fromByteCount: Int64(totalBytes * 3 / 4), countStyle: .file)
    }

    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - ClipboardItemFactory

enum ClipboardItemFactory {

    /// Reads all data from the current NSPasteboard and creates a ClipboardItem.
    /// Returns nil if pasteboard is empty.
    static func fromCurrentPasteboard(storageDirectory: URL) -> ClipboardItem? {
        let pasteboard = NSPasteboard.general
        guard let pasteboardItems = pasteboard.pasteboardItems, !pasteboardItems.isEmpty else {
            return nil
        }

        // Collect all types from all items
        var allTypes: [String] = []
        var inlineData: [String: String] = [:]
        var fileData: [String: String] = [:]
        var displayText: String?
        var category: ClipboardItem.Category = .other
        var imageFilename: String?

        let itemID = UUID()
        let itemDir = storageDirectory.appendingPathComponent(itemID.uuidString, isDirectory: true)

        for pbItem in pasteboardItems {
            for typeRawValue in pbItem.types {
                let typeString = typeRawValue.rawValue
                guard !allTypes.contains(typeString) else { continue }
                allTypes.append(typeString)

                guard let data = pbItem.data(forType: typeRawValue) else { continue }

                if data.count > 256_000 {
                    // Large data → write to file
                    let safeFilename = typeString
                        .replacingOccurrences(of: "/", with: "_")
                        .replacingOccurrences(of: ".", with: "_")
                    try? FileManager.default.createDirectory(at: itemDir, withIntermediateDirectories: true)
                    let fileURL = itemDir.appendingPathComponent(safeFilename)
                    try? data.write(to: fileURL)
                    fileData[typeString] = safeFilename
                } else {
                    inlineData[typeString] = data.base64EncodedString()
                }

                // Determine category and display text (use best available)
                categorize(
                    type: typeRawValue,
                    data: data,
                    category: &category,
                    displayText: &displayText,
                    imageFilename: &imageFilename,
                    itemDir: itemDir
                )
            }
        }

        guard !allTypes.isEmpty else { return nil }

        // Deterministic content hash: concatenate payload bytes for every type
        // in sorted order (inline decoded, or read from the item's data dir).
        // Covers both inline and large file-based data, so images dedup reliably.
        var contentPayload = Data()
        for typeString in allTypes.sorted() {
            if let b64 = inlineData[typeString], let d = Data(base64Encoded: b64) {
                contentPayload.append(d)
            } else if let filename = fileData[typeString] {
                let fileURL = itemDir.appendingPathComponent(filename)
                if let d = try? Data(contentsOf: fileURL) {
                    contentPayload.append(d)
                }
            }
        }
        let digest = SHA256.hash(data: contentPayload)
        let contentHash = digest.map { String(format: "%02x", $0) }.joined()

        return ClipboardItem(
            id: itemID,
            timestamp: Date(),
            isPinned: false,
            pasteboardTypes: allTypes,
            inlineData: inlineData,
            fileData: fileData,
            displayText: displayText,
            category: category,
            contentHash: contentHash
        )
    }

    // swiftlint:disable:next function_parameter_count
    private static func categorize(
        type: NSPasteboard.PasteboardType,
        data: Data,
        category: inout ClipboardItem.Category,
        displayText: inout String?,
        imageFilename: inout String?,
        itemDir: URL
    ) {
        let uti = UTType(type.rawValue)

        if uti?.conforms(to: .utf8PlainText) == true || type == .string {
            if category == .other {
                category = .plainText
            }
            if displayText == nil, let text = String(data: data, encoding: .utf8) {
                displayText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } else if type == .rtf || uti?.conforms(to: .rtf) == true {
            if category == .other || category == .plainText {
                category = .richText
            }
            if displayText == nil {
                displayText = plainTextFromRTF(data)
            }
        } else if type == .html || uti?.conforms(to: .html) == true {
            if category == .other || category == .plainText {
                category = .html
            }
            if displayText == nil, let text = String(data: data, encoding: .utf8) {
                displayText = plainTextFromHTML(text)
            }
        } else if uti?.conforms(to: .image) == true || type == .tiff || type == .png {
            category = .image
        } else if type == .fileURL || uti?.conforms(to: .fileURL) == true {
            if category == .other {
                category = .fileURL
            }
            if displayText == nil, let urlStr = String(data: data, encoding: .utf8) {
                displayText = URL(string: urlStr)?.lastPathComponent
            }
        } else if type.rawValue.contains("NSColor") || uti?.conforms(to: .data) == true && type.rawValue.lowercased().contains("color") {
            category = .color
            if displayText == nil, let color = colorFromData(data), let hex = colorHex(from: color) {
                displayText = hex
            }
        }
    }

    /// Decode a color pasteboard payload (a keyed archive of `NSColor`).
    private static func colorFromData(_ data: Data) -> NSColor? {
        (try? NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSColor.self], from: data)) as? NSColor
    }

    /// Convert a clipboard `NSColor` into a `#RRGGBB` string.
    private static func colorHex(from color: NSColor) -> String? {
        guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
        let r = Int((rgb.redComponent * 255).rounded())
        let g = Int((rgb.greenComponent * 255).rounded())
        let b = Int((rgb.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    private static func plainTextFromRTF(_ data: Data) -> String? {
        guard let attrStr = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) else {
            return nil
        }
        return attrStr.string.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func plainTextFromHTML(_ html: String) -> String? {
        guard let data = html.data(using: .utf8),
              let attrStr = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue as AnyObject], documentAttributes: nil) else {
            return nil
        }
        return attrStr.string.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - NSImage convenience

extension ClipboardItem {

    /// Returns thumbnail NSImage if this item contains image data.
    func thumbnailImage(storageDirectory: URL) -> NSImage? {
        guard category == .image else { return nil }

        let imageTypes: [String] = [
            NSPasteboard.PasteboardType.tiff.rawValue,
            NSPasteboard.PasteboardType.png.rawValue,
            UTType.tiff.identifier,
            UTType.png.identifier,
            UTType.jpeg.identifier,
            UTType.bmp.identifier,
        ]

        for typeStr in imageTypes {
            if let b64 = inlineData[typeStr], let data = Data(base64Encoded: b64) {
                return NSImage(data: data)
            }
            if let filename = fileData[typeStr] {
                let url = storageDirectory.appendingPathComponent(id.uuidString).appendingPathComponent(filename)
                return NSImage(contentsOf: url)
            }
        }
        return nil
    }
}
