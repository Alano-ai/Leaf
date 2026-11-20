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
        if let cover = book.cover {
            try add(cover, to: archive, at: "EPUB/cover.jpg", date: date, checkpoint: checkpoint)
        }
        for chapter in book.chapters {
            let scalars = chapter.text.unicodeScalars
            var start = scalars.startIndex
            while start < scalars.endIndex {
                try checkpoint()
                let end = nextBoundary(in: scalars, from: start)
                let content = try preformattedContent(scalars[start..<end], checkpoint: checkpoint)
                let sectionNumber = navigationLinks.count + 1
                let label = (start == scalars.startIndex ? chapter.title : nil)
                    ?? String(localized: "Section \(sectionNumber)", bundle: .module)
                let sectionTitle = try escape(label.unicodeScalars)
                navigationLinks.append("<li><a href=\"section-\(sectionNumber).xhtml\">\(sectionTitle)</a></li>")
                let cover = sectionNumber == 1 && book.cover != nil ? "<p><img src=\"cover.jpg\" alt=\"\"/></p>" : ""
                try add(
                    xhtml(title: sectionTitle, body: "<main>\(cover)<h1>\(sectionTitle)</h1><pre>\(content)</pre></main>"),
                    to: archive, at: "EPUB/section-\(sectionNumber).xhtml", date: date, checkpoint: checkpoint
                )
                start = end
            }
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
        let cover = book.cover == nil ? "" :
            "<item id=\"cover\" href=\"cover.jpg\" media-type=\"image/jpeg\" properties=\"cover-image\"/>"
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
                \(cover)
                \(manifest)
              </manifest>
              <spine>\(spine)</spine>
            </package>
            """,
            to: archive, at: "EPUB/package.opf", date: date, checkpoint: checkpoint
        )
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

    private static func nextBoundary(in text: String.UnicodeScalarView, from start: String.Index) -> String.Index {
        let end = text.index(start, offsetBy: 48_000, limitedBy: text.endIndex) ?? text.endIndex
        guard end < text.endIndex else { return end }
        let middle = text.index(start, offsetBy: 24_000)
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
