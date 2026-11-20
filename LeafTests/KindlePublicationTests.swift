// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import Testing
@testable import Leaf

struct KindlePublicationTests {
    @Test(arguments: [BookFormat.mobi, .azw3])
    func rendersMarkupAndReadsOnlyLocalImages(format: BookFormat) throws {
        let book = try KindlePublication(data: KindleFixture.book(hybrid: format == .azw3))
        #expect(book.title == "Leaf Kindle Fixture")
        let chapter = try book.section(at: 0)
        let text = chapter.blocks.compactMap { block -> String? in
            guard case .text(let content, _) = block else { return nil }
            return String(content.characters)
        }.joined(separator: " ")
        #expect(text.contains(format == .azw3 ? "KF8 edition" : "MOBI edition"))
        #expect(text.contains("Second line"))
        #expect(!text.contains("Hidden script text"))
        #expect(chapter.anchors["target"] != nil)
        let targets = chapter.blocks.flatMap { block -> [EbookTarget] in
            guard case .text(let content, _) = block else { return [] }
            return content.runs.compactMap { $0.link.flatMap(EbookTarget.init(readerURL:)) }
        }
        #expect(targets == [EbookTarget(path: "part00000.html", fragment: "target")])
        let images = chapter.blocks.compactMap { block -> String? in
            guard case .image(let path, _) = block else { return nil }
            return path
        }
        #expect(images == ["resource00000.gif"])
        let image = try book.imageData(at: "resource00000.gif")
        #expect(EbookMarkup.rasterImage(data: image) != nil)
        #expect(throws: EbookError.invalidPackage) { try book.imageData(at: "file:///tmp/outside.gif") }
    }

    @Test func rejectsProtectedAndMalformedInputs() {
        #expect(throws: EbookError.protectedBook) {
            try KindlePublication(data: KindleFixture.book(protectedLegacy: true))
        }
        #expect(throws: EbookError.protectedBook) {
            try KindlePublication(data: KindleFixture.book(hybrid: true, protectedLegacy: true))
        }
        #expect(throws: EbookError.protectedBook) {
            try KindlePublication(data: KindleFixture.book(hybrid: true, protectedKF8: true))
        }
        #expect(throws: EbookError.unsupportedLayout) {
            try KindlePublication(data: KindleFixture.book(hybrid: true, fixedLayout: true))
        }
        var invalid = KindleFixture.book()
        invalid.replaceSubrange(86..<90, with: [0, 0, 0, 1])
        #expect(throws: EbookError.invalidPackage) { try KindlePublication(data: invalid) }
    }

    @MainActor
    @Test(arguments: [BookFormat.mobi, .azw3])
    func libraryKeepsKindlePositionAfterOriginalIsRemoved(format: BookFormat) async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = LibraryStorage(directory: root.appending(path: "Library"))
        let original = root.appending(path: "Fixture.\(format.rawValue)")
        try KindleFixture.book(hybrid: format == .azw3).write(to: original)

        let library = LibraryModel(storage: storage)
        let emptyRestore = await library.restore()
        #expect(!emptyRestore)
        #expect(await library.importBook(at: original))
        let session = try #require(library.session)
        #expect(session.book.format == format)
        let saved = EbookPosition(section: 0, block: 2)
        library.savePosition(saved, in: session)
        try FileManager.default.removeItem(at: original)

        let reopened = LibraryModel(storage: storage)
        #expect(await reopened.restore())
        let restored = try #require(reopened.session)
        if case .ebook(let reading) = restored.content {
            #expect(reading.position == saved)
            #expect(reading.section.blocks.count > 2)
        } else {
            Issue.record("Kindle book did not restore as an ebook")
        }
        #expect(reopened.books.first?.id == session.book.id)
    }
}

private enum KindleFixture {
    static func book(hybrid: Bool = false, protectedLegacy: Bool = false,
                     protectedKF8: Bool = false, fixedLayout: Bool = false) -> Data {
        let legacy = markup(edition: "MOBI", image: "recindex=\"00001\"")
        let kf8 = markup(edition: "KF8", image: "src=\"kindle:embed:0001?mime=image/gif\"")
        let gif = Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==")!
        let legacyHeader = header(version: 6, text: legacy, protected: protectedLegacy,
                                  metadata: hybrid ? extendedHeader(tag: 121, value: [0, 0, 0, 4]) : Data())
        var records = [legacyHeader, legacy, gif]
        if hybrid {
            let metadata = fixedLayout ? extendedHeader(tag: 122, value: Array("true".utf8)) : Data()
            let modernHeader = header(version: 8, text: kf8, protected: protectedKF8, metadata: metadata)
            records.append(contentsOf: [Data("BOUNDARY".utf8), modernHeader, kf8])
        }

        var database = Data(count: 78 + records.count * 8 + 2)
        database.replaceSubrange(0..<4, with: "Leaf".utf8)
        database.replaceSubrange(60..<68, with: "BOOKMOBI".utf8)
        set(UInt16(records.count), at: 76, in: &database)
        var offset = database.count
        for (index, record) in records.enumerated() {
            set(UInt32(offset), at: 78 + index * 8, in: &database)
            offset += record.count
        }
        for record in records { database.append(record) }
        return database
    }

    private static func markup(edition: String, image: String) -> Data {
        // Missing closing paragraph tags are common in older Mobipocket markup.
        Data("""
        <html><body><h1>\(edition) edition</h1>
        <p>First line<br>Second line
        <p><a href="#target">Jump</a> <a href="https://example.invalid/">External</a>
        <p id="target">Target paragraph.</p><img \(image) alt="Local illustration">
        <img src="https://example.invalid/remote.gif"><script>Hidden script text</script></body></html>
        """.utf8)
    }

    private static func header(version: UInt32, text: Data, protected: Bool, metadata: Data) -> Data {
        let title = Data("Leaf Kindle Fixture".utf8)
        var record = Data(count: 280)
        record.replaceSubrange(16..<20, with: "MOBI".utf8)
        // Optional record indices use the Mobipocket absent-record sentinel.
        for offset in [40, 44, 48, 52, 56, 60, 64, 68, 72, 76, 112, 120, 168, 192, 200, 208,
                       224, 244, 248, 252, 256, 260] {
            set(UInt32.max, at: offset, in: &record)
        }
        set(UInt16(1), at: 0, in: &record)
        set(UInt32(text.count), at: 4, in: &record)
        set(UInt16(1), at: 8, in: &record)
        set(UInt16(4_096), at: 10, in: &record)
        set(UInt16(protected ? 1 : 0), at: 12, in: &record)
        set(UInt32(264), at: 20, in: &record)
        set(UInt32(2), at: 24, in: &record)
        set(UInt32(65_001), at: 28, in: &record)
        set(UInt32(1_234), at: 32, in: &record)
        set(version, at: 36, in: &record)
        set(UInt32(record.count + metadata.count), at: 84, in: &record)
        set(UInt32(title.count), at: 88, in: &record)
        set(UInt32(9), at: 92, in: &record)
        set(version, at: 104, in: &record)
        set(UInt32(2), at: 108, in: &record)
        if !metadata.isEmpty { set(UInt32(0x40), at: 128, in: &record) }
        record.append(metadata)
        record.append(title)
        return record
    }

    private static func extendedHeader(tag: UInt32, value: [UInt8]) -> Data {
        var header = Data(count: 20 + value.count)
        header.replaceSubrange(0..<4, with: "EXTH".utf8)
        set(UInt32(header.count), at: 4, in: &header)
        set(UInt32(1), at: 8, in: &header)
        set(tag, at: 12, in: &header)
        set(UInt32(8 + value.count), at: 16, in: &header)
        header.replaceSubrange(20..<header.count, with: value)
        return header
    }

    private static func set<T: FixedWidthInteger>(_ value: T, at offset: Int, in data: inout Data) {
        withUnsafeBytes(of: value.bigEndian) { bytes in
            data.replaceSubrange(offset..<(offset + bytes.count), with: bytes)
        }
    }
}
