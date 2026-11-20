// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import ZIPFoundation

enum EPUBPackage {
    private static let xml = #"<?xml version="1.0" encoding="UTF-8"?>"#
    private static let style = "pre { font: inherit; white-space: pre-wrap; overflow-wrap: anywhere; }"

    static func write(_ book: ConversionBook, to url: URL, checkpoint: () throws -> Void) throws {
        let archive = try Archive(url: url, accessMode: .create, pathEncoding: nil)
        let date = Date()
        try add("application/epub+zip", to: archive, at: "mimetype", date: date, method: .none, checkpoint: checkpoint)
        try add(
            """
            \(xml)
            <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
              <rootfiles><rootfile full-path="EPUB/package.opf" media-type="application/oebps-package+xml"/></rootfiles>
            </container>
            """,
            to: archive, at: "META-INF/container.xml", date: date, checkpoint: checkpoint
        )
        try add(style, to: archive, at: "EPUB/reading.css", date: date, checkpoint: checkpoint)

        let title = try escape(book.title.unicodeScalars)
        var navigationLinks: [String] = []
        var imageItems: [String] = []
        for (index, asset) in book.illustrations.enumerated() {
            let filename = imageName(index, in: book)
            try add(asset.data, to: archive, at: "EPUB/\(filename)", date: date, method: .none, checkpoint: checkpoint)
            let properties = index == book.coverIndex ? " properties=\"cover-image\"" : ""
            imageItems.append("<item id=\"image-\(index + 1)\" href=\"\(filename)\" media-type=\"\(asset.format.mediaType)\"\(properties)/>")
        }
        let separateCover = book.coverOutsideChapters
        for (index, chapter) in book.chapters.enumerated() {
            var sectionTitle = chapter.title
            var content = ""
            var remaining = 48_000
            if index == 0, let separateCover {
                content = try image(separateCover, in: book, alternative: "")
                remaining -= content.utf8.count
            }
            func flush() throws {
                guard !content.isEmpty else { return }
                let number = navigationLinks.count + 1
                let label = sectionTitle ?? String(localized: "Section \(number)", bundle: .module)
                let heading = try escape(label.unicodeScalars)
                navigationLinks.append("<li><a href=\"section-\(number).xhtml\">\(heading)</a></li>")
                try add(xhtml(title: heading, body: "<main><h1>\(heading)</h1>\(content)</main>"),
                        to: archive, at: "EPUB/section-\(number).xhtml", date: date, checkpoint: checkpoint)
                sectionTitle = nil
                content = ""
                remaining = 48_000
            }
            for block in chapter.blocks {
                try checkpoint()
                switch block {
                case .image(let index, let alternative):
                    let markup = try image(index, in: book, alternative: alternative)
                    if remaining < markup.utf8.count { try flush() }
                    content += markup
                    remaining -= markup.utf8.count
                case .text(let text):
                    let scalars = text.unicodeScalars
                    var start = scalars.startIndex
                    while start < scalars.endIndex {
                        if remaining == 0 { try flush() }
                        let end = nextBoundary(in: scalars, from: start, limit: remaining)
                        content += "<pre>\(try preformattedContent(scalars[start..<end], checkpoint: checkpoint))</pre>"
                        remaining -= scalars.distance(from: start, to: end)
                        start = end
                        if start != scalars.endIndex { try flush() }
                    }
                }
            }
            try flush()
        }

        guard !navigationLinks.isEmpty else { throw BookConversion.Issue.unreadableBook }
        let sections = 1...navigationLinks.count
        let heading = try escape(String(localized: "Contents", bundle: .module).unicodeScalars)
        let links = navigationLinks.joined(separator: "\n")
        try add(
            xhtml(title: heading, body: "<nav epub:type=\"toc\" id=\"toc\"><h1>\(heading)</h1><ol>\(links)</ol></nav>"),
            to: archive, at: "EPUB/nav.xhtml", date: date, checkpoint: checkpoint
        )
        let manifest = sections.map {
            "<item id=\"s\($0)\" href=\"section-\($0).xhtml\" media-type=\"application/xhtml+xml\"/>"
        }.joined(separator: "\n")
        let spine = sections.map { "<itemref idref=\"s\($0)\"/>" }.joined(separator: "\n")
        let images = imageItems.joined(separator: "\n")
        let modified = date.formatted(.iso8601)
        try add(
            """
            \(xml)
            <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="book-id">
              <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
                <dc:identifier id="book-id">urn:uuid:\(UUID().uuidString.lowercased())</dc:identifier>
                <dc:title>\(title)</dc:title>
                <dc:language>und</dc:language>
                <meta property="dcterms:modified">\(modified)</meta>
              </metadata>
              <manifest>
                <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
                <item id="css" href="reading.css" media-type="text/css"/>
                \(images)
                \(manifest)
              </manifest>
              <spine>\(spine)</spine>
            </package>
            """,
            to: archive, at: "EPUB/package.opf", date: date, checkpoint: checkpoint
        )
    }

    private static func imageName(_ index: Int, in book: ConversionBook) -> String {
        "image-\(index + 1).\(book.illustrations[index].format.rawValue)"
    }

    private static func image(_ index: Int, in book: ConversionBook, alternative: String) throws -> String {
        let label = try escape(alternative.unicodeScalars.prefix(512)).replacingOccurrences(of: "\"", with: "&quot;")
        return "<p><img src=\"\(imageName(index, in: book))\" alt=\"\(label)\"/></p>"
    }

    private static func xhtml(title: String, body: String) -> String {
        """
        \(xml)
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="und" lang="und">
          <head><title>\(title)</title><link rel="stylesheet" href="reading.css"/></head>
          <body>\(body)</body>
        </html>
        """
    }

    private static func nextBoundary(in text: String.UnicodeScalarView, from start: String.Index, limit: Int) -> String.Index {
        let end = text.index(start, offsetBy: limit, limitedBy: text.endIndex) ?? text.endIndex
        guard end < text.endIndex else { return end }
        let middle = text.index(start, offsetBy: limit / 2)
        return text[middle..<end].lastIndex(of: "\n").map { text.index(after: $0) } ?? end
    }

    private static func preformattedContent(_ scalars: String.UnicodeScalarView.SubSequence,
                                            checkpoint: () throws -> Void) throws -> String {
        // Keep a continuous preformatted block while giving EPUB paginators smaller text nodes to lay out.
        var content = ""
        var start = scalars.startIndex
        while start < scalars.endIndex {
            try checkpoint()
            let end = scalars.index(start, offsetBy: 512, limitedBy: scalars.endIndex) ?? scalars.endIndex
            content += "<span>\(try escape(scalars[start..<end]))</span>"
            start = end
        }
        return content
    }

    private static func escape(_ source: some Sequence<Unicode.Scalar>) throws -> String {
        var escaped = String()
        for scalar in source {
            switch scalar.value {
            case 38: escaped += "&amp;"
            case 60: escaped += "&lt;"
            case 62: escaped += "&gt;"
            case 9, 10, 13, 0x20...0xd7ff, 0xe000...0xfffd, 0x10000...0x10ffff:
                escaped.unicodeScalars.append(scalar)
            default:
                throw TXTToEPUB.ConversionError.invalidXMLCharacter
            }
        }
        return escaped
    }

    private static func add(_ text: String, to archive: Archive, at path: String, date: Date,
                            method: CompressionMethod = .deflate, checkpoint: () throws -> Void) throws {
        try add(Data(text.utf8), to: archive, at: path, date: date, method: method, checkpoint: checkpoint)
    }

    private static func add(_ bytes: Data, to archive: Archive, at path: String, date: Date,
                            method: CompressionMethod = .deflate, checkpoint: () throws -> Void) throws {
        try checkpoint()
        try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(bytes.count),
                             modificationDate: date, compressionMethod: method) { offset, count in
            try checkpoint()
            let start = Int(offset)
            return bytes.subdata(in: start..<(start + count))
        }
    }
}
