// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// Writes reflowable, unencrypted PalmDB books with UTF-8 text records.
/// Record layouts follow Calibre's published MOBI format notes.
enum KindleOutput {
    private static let textRecordSize = 4_096
    private static let absent = UInt32.max

    static func write(_ book: ConversionBook, format: BookFormat, to output: URL) throws {
        let kf8 = format == .azw3
        let headerLength = kf8 ? 264 : 232
        let version = UInt32(kf8 ? 8 : 6)
        let title = Data(book.title.utf8)
        let document = try makeDocument(book, kf8: kf8)
        let markup = document.text

        var records: [Data] = [Data()]
        var start = 0
        while start < markup.count {
            try Task.checkCancellation()
            var end = min(start + textRecordSize, markup.count)
            while end < markup.count, markup[end] & 0xc0 == 0x80 { end -= 1 }
            records.append(Data(markup[start..<end]))
            start = end
        }
        let textCount = UInt16(records.count - 1)
        let firstNonText = UInt32(records.count)
        var fragmentIndex = absent
        var skeletonIndex = absent
        if kf8 {
            fragmentIndex = UInt32(records.count)
            var names = Data()
            let bodySelector = "P-//*[@aid='0']"
            names.appendKindleInteger(bodySelector.utf8.count)
            names.append(contentsOf: bodySelector.utf8)
            let fragments = document.chapters.enumerated().map { index, chapter in
                KindleIndex.entry(String(format: "%010d", chapter.insertion), controls: 0x0f,
                                  values: [0, index, index, 0, chapter.fragmentLength])
            }
            records += KindleIndex.records(tags: [.init(2, 1, 1), .init(3, 1, 2), .init(4, 1, 4), .init(6, 2, 8)],
                                           entries: fragments, strings: names)
            skeletonIndex = UInt32(records.count)
            let skeletons = document.chapters.enumerated().map { index, chapter in
                KindleIndex.entry(String(format: "SKEL%010d", index), controls: 0x0a,
                                  values: [1, 1, chapter.start, chapter.skeletonLength, chapter.start, chapter.skeletonLength])
            }
            records += KindleIndex.records(tags: [.init(1, 1, 3), .init(6, 2, 12)], entries: skeletons)
        }
        var contentsIndex = absent
        let contents = contentsRecords(document.chapters, kf8: kf8, bookLength: markup.count)
        if !contents.isEmpty {
            contentsIndex = UInt32(records.count)
            records += contents
        }
        let firstImage = book.cover == nil ? absent : UInt32(records.count)
        if let cover = book.cover { records.append(cover) }
        var flowIndex = absent
        if kf8 {
            flowIndex = UInt32(records.count)
            var flow = Data("FDST".utf8)
            for word in [UInt32(12), 1, 0, UInt32(markup.count)] { flow.appendBE(word) }
            records.append(flow)
        }
        records.append(Data([0xe9, 0x8e, 0x0d, 0x0a]))

        var fields: [(UInt32, Data)] = [(503, title), (501, Data("EBOK".utf8))]
        if book.cover != nil {
            var coverOffset = Data()
            coverOffset.appendBE(UInt32(0))
            fields.append((201, coverOffset))
        }
        var metadata = Data("EXTH".utf8)
        metadata.appendBE(UInt32(12 + fields.reduce(0) { $0 + 8 + $1.1.count }))
        metadata.appendBE(UInt32(fields.count))
        for (identifier, value) in fields {
            metadata.appendBE(identifier)
            metadata.appendBE(UInt32(8 + value.count))
            metadata.append(value)
        }
        while metadata.count % 4 != 0 { metadata.append(0) }

        let palmHeaderLength = 16
        var header = Data(repeating: 0, count: palmHeaderLength + headerLength)
        header.setBE(UInt16(1), at: 0) // Uncompressed PalmDOC records.
        header.setBE(UInt32(markup.count), at: 4)
        header.setBE(textCount, at: 8)
        header.setBE(UInt16(textRecordSize), at: 10)
        header.replaceSubrange(16..<20, with: "MOBI".utf8)
        header.setBE(UInt32(headerLength), at: 20)
        header.setBE(UInt32(2), at: 24) // Reflowable book.
        header.setBE(UInt32(65_001), at: 28)
        header.setBE(UInt32.random(in: 1..<UInt32.max), at: 32)
        header.setBE(version, at: 36)
        for field in stride(from: 40, through: 76, by: 4) { header.setBE(absent, at: field) }
        header.setBE(firstNonText, at: 80)
        header.setBE(UInt32(header.count + metadata.count), at: 84)
        header.setBE(UInt32(title.count), at: 88)
        header.setBE(version, at: 104)
        header.setBE(firstImage, at: 108)
        header.setBE(UInt32(0x50), at: 128) // EXTH metadata follows the header.
        header.setBE(absent, at: 164)
        header.setBE(absent, at: 168)
        if kf8 {
            header.setBE(flowIndex, at: 192)
            header.setBE(UInt32(1), at: 196)
        } else {
            header.setBE(UInt16(1), at: 192)
            header.setBE(textCount, at: 194)
        }
        for field in [200, 208, 224, 256, 260] where field + 4 <= header.count {
            header.setBE(absent, at: field)
        }
        header.setBE(contentsIndex, at: 244)
        if kf8 {
            header.setBE(fragmentIndex, at: 248)
            header.setBE(skeletonIndex, at: 252)
        }
        header.append(metadata)
        header.append(title)
        records[0] = header

        var pdb = Data(repeating: 0, count: 78)
        let name = Array(book.title.utf8.prefix(31).map { $0 < 0x80 && $0 > 0x1f ? $0 : UInt8(95) })
        pdb.replaceSubrange(0..<name.count, with: name)
        let now = UInt32(truncatingIfNeeded: Int(Date().timeIntervalSince1970) + 2_082_844_800)
        pdb.setBE(now, at: 36)
        pdb.setBE(now, at: 40)
        pdb.replaceSubrange(60..<68, with: "BOOKMOBI".utf8)
        pdb.setBE(UInt32(2 * records.count + 1), at: 68)
        pdb.setBE(UInt16(records.count), at: 76)
        var offset = pdb.count + 8 * records.count + 2
        for (index, record) in records.enumerated() {
            pdb.appendBE(UInt32(offset))
            pdb.appendBE(UInt32(2 * index))
            offset += record.count
        }
        pdb.appendBE(UInt16(0))
        guard offset <= ConversionFiles.limit else { throw TXTToEPUB.ConversionError.outputTooLarge }
        try pdb.write(to: output)
        let file = try FileHandle(forWritingTo: output)
        defer { try? file.close() }
        try file.seekToEnd()
        for record in records {
            try Task.checkCancellation()
            try file.write(contentsOf: record)
        }
    }

    private struct ChapterLocation {
        let title: String?
        let start: Int
        let insertion: Int
        let skeletonLength: Int
        let fragmentLength: Int
    }

    private static func makeDocument(_ book: ConversionBook, kf8: Bool) throws -> (text: Data, chapters: [ChapterLocation]) {
        let opening = "<html xmlns=\"http://www.w3.org/1999/xhtml\"><head><meta http-equiv=\"Content-Type\" content=\"text/html; charset=utf-8\"/><title>\(book.title.escapedBookMarkup)</title></head>"
        let closing = "</body></html>"
        var text = kf8 ? Data() : Data((opening + "<body>").utf8)
        var chapters: [ChapterLocation] = []
        for (index, chapter) in book.chapters.enumerated() {
            try Task.checkCancellation()
            let skeletonStart = text.count
            if kf8 { text.append(contentsOf: (opening + "<body aid=\"0\">").utf8) }
            let insertion = text.count
            if kf8 { text.append(contentsOf: closing.utf8) }
            let skeletonLength = text.count - skeletonStart
            let fragmentStart = text.count
            if index == 0, book.cover != nil {
                let source = kf8 ? "src=\"kindle:embed:0001\"" : "recindex=\"00001\""
                text.append(contentsOf: "<p><img \(source) alt=\"\"/></p>".utf8)
            }
            let chapterStart = kf8 ? skeletonStart : text.count
            if let title = chapter.title {
                text.append(contentsOf: "<h1>\(title.escapedBookMarkup)</h1>".utf8)
            }
            for line in chapter.text.split(separator: "\n", omittingEmptySubsequences: false) {
                let content = line.isEmpty ? "<br/>" : line.escapedBookMarkup
                text.append(contentsOf: "<p>\(content)</p>".utf8)
            }
            guard text.count <= ConversionFiles.limit else { throw TXTToEPUB.ConversionError.outputTooLarge }
            chapters.append(ChapterLocation(title: chapter.title, start: chapterStart, insertion: insertion,
                                            skeletonLength: skeletonLength, fragmentLength: text.count - fragmentStart))
        }
        if !kf8 { text.append(contentsOf: closing.utf8) }
        return (text, chapters)
    }

    private static func contentsRecords(_ chapters: [ChapterLocation], kf8: Bool, bookLength: Int) -> [Data] {
        var entries: [Data] = []
        var names = Data()
        for (index, chapter) in chapters.enumerated() {
            guard let title = chapter.title, !title.isEmpty else { continue }
            let name = String(title.unicodeScalars.prefix(512)).utf8
            // Both readers support a single 16-bit string table. Further titles remain in the chapter text.
            if names.count + name.count + 4 > Int(UInt16.max) { break }
            let next = index + 1
            let end = next < chapters.count ? chapters[next].start : bookLength
            var values = [chapter.start, end - chapter.start, names.count, 0]
            if kf8 { values += [index, 0] }
            entries.append(KindleIndex.entry(String(format: "%04x", index), controls: kf8 ? 0x1f : 0x0f, values: values))
            names.appendKindleInteger(name.count)
            names.append(contentsOf: name)
        }
        guard !entries.isEmpty else { return [] }
        var tags: [KindleIndex.Tag] = [.init(1, 1, 1), .init(2, 1, 2), .init(3, 1, 4), .init(4, 1, 8)]
        if kf8 { tags.append(.init(6, 2, 16)) }
        return KindleIndex.records(tags: tags, entries: entries, strings: names)
    }
}
