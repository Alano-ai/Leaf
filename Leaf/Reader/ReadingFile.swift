// SPDX-License-Identifier: GPL-3.0-only

import CoreFoundation
import Foundation

enum ReadingError: LocalizedError, Equatable {
    case unsupportedFormat
    case missingBook
    case invalidPDF
    case protectedPDF
    case invalidText
    case tooLarge
    case invalidCatalog

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: String(localized: "Choose a PDF or TXT file.")
        case .missingBook: String(localized: "This book is missing from Leaf’s library. Import the original file again.")
        case .invalidPDF: String(localized: "This PDF does not contain any readable pages.")
        case .protectedPDF: String(localized: "Leaf cannot open password-protected or encrypted PDFs.")
        case .invalidText: String(localized: "This file does not contain readable UTF-8, UTF-16, or GB18030 text.")
        case .tooLarge: String(localized: "Leaf can import books up to 64 MB.")
        case .invalidCatalog: String(localized: "The library catalog contains invalid entries.")
        }
    }
}

struct PlainText: Sendable {
    let content: String
    let blocks: [Range<String.Index>]

    init(data: Data) throws {
        let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        ))
        let hasUTF16BOM = data.starts(with: [0xff, 0xfe]) || data.starts(with: [0xfe, 0xff])
        let encodings: [String.Encoding] = hasUTF16BOM ? [.utf16] : [.utf8, gb18030]
        guard let decoded = encodings.lazy.compactMap({ String(data: data, encoding: $0) }).first,
              !decoded.contains("\0") else { throw ReadingError.invalidText }
        let text = decoded.first == "\u{feff}" ? String(decoded.dropFirst()) : decoded
        guard text.contains(where: { !$0.isWhitespace }) else { throw ReadingError.invalidText }
        content = text

        // Short blocks preserve line breaks, bound individual Text layouts, and provide stable scroll targets.
        var ranges: [Range<String.Index>] = []
        var start = text.startIndex
        var length = 0
        for index in text.indices {
            length += 1
            if length >= 800 || (length >= 160 && text[index].isNewline) {
                let end = text.index(after: index)
                ranges.append(start..<end)
                start = end
                length = 0
            }
        }
        if start < text.endIndex { ranges.append(start..<text.endIndex) }
        blocks = ranges
    }

    subscript(index: Int) -> Substring { content[blocks[index]] }
}

struct ReadingFile: Sendable {
    static let sizeLimit = 64_000_000

    let data: Data
    let text: PlainText?

    init(url: URL, format: BookFormat) throws {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw ReadingError.unsupportedFormat }
        if let size = values.fileSize, size > Self.sizeLimit { throw ReadingError.tooLarge }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        data = try handle.read(upToCount: Self.sizeLimit + 1) ?? Data()
        guard data.count <= Self.sizeLimit else { throw ReadingError.tooLarge }
        text = format == .txt ? try PlainText(data: data) : nil
    }

    static func forImport(_ url: URL) throws -> (book: LibraryBook, file: Self) {
        guard let format = BookFormat(rawValue: url.pathExtension.lowercased()) else {
            throw ReadingError.unsupportedFormat
        }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let source = try Self(url: url, format: format)
        let title = url.deletingPathExtension().lastPathComponent
        let id = LibraryBook.identifier(for: source.data, format: format)
        return (LibraryBook(id: id, title: title, format: format), source)
    }
}
