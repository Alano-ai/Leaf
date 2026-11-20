// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import LeafConversion
import Testing
import ZIPFoundation
@testable import Leaf

struct EPUBPublicationTests {
    @Test(arguments: [LeafConversion.BookFormat.azw3, .mobi])
    func kindleConversionPreservesInlineImages(target: LeafConversion.BookFormat) async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appending(path: "Illustrated.epub")
        let output = folder.appending(path: "Illustrated.\(target.rawValue)")
        try archive(firstChapter: """
            <html xmlns="http://www.w3.org/1999/xhtml"><body>
              <p>图前的正文</p><img src="../images/cove.png" alt="海湾 &quot;A&quot;"/>
              <p>图后的正文</p><img src="../images/cove.png" alt="同一张图"/>
            </body></html>
            """).write(to: input)
        try await BookConversion.convert(source: input, destination: output, decodeEbook: ConversionSource.decode)
        let reopened = try KindlePublication(data: Data(contentsOf: output))
        try await checkIllustrations(in: reopened)

        let epub = folder.appending(path: "Round trip.epub")
        try await BookConversion.convert(source: output, destination: epub, decodeEbook: ConversionSource.decode)
        try await checkIllustrations(in: EPUBPublication(data: Data(contentsOf: epub)))
    }

    private func checkIllustrations(in book: any EbookPublication) async throws {
        let section = try await book.section(at: 0)
        var content: [String] = []
        var paths: [String] = []
        for block in section.blocks {
            switch block {
            case .text(let text, _):
                content.append(String(text.characters))
            case .image(let path, let alternative):
                content.append(alternative)
                paths.append(path)
            }
        }
        let first = try #require(content.firstIndex(of: "图前的正文"))
        #expect(content.dropFirst(first).prefix(4) == ["图前的正文", "海湾 \"A\"", "图后的正文", "同一张图"])
        #expect(paths.count == 2)
        #expect(Set(paths).count == 1)
        let path = try #require(paths.first)
        #expect(try await book.imageData(at: path) == Self.image)
    }

    @Test func opensEPUB3WithLocalImageAndChapterAnchor() async throws {
        let data = try archive()
        let book = try EPUBPublication(data: data)
        #expect(book.title == "Leaf テスト")
        #expect(book.sectionPaths == ["OPS/chapters/first.xhtml", "OPS/chapters/山海.xhtml"])
        #expect(book.contents.map(\.label) == ["First chapter", "山海"])
        #expect(book.contents.last?.target == EbookTarget(path: "OPS/chapters/山海.xhtml", fragment: "destination"))

        let first = try await book.section(at: 0)
        #expect(first.blocks.contains {
            if case .image(let path, _) = $0 { return path == "OPS/images/cove.png" }
            return false
        })
        let destination = try await book.section(at: 1)
        #expect(destination.anchors["destination"] == 0)
        #expect(try await book.imageData(at: "OPS/images/cove.png") == Self.image)
        await #expect(throws: EbookError.invalidPackage) {
            try await book.imageData(at: "OPS/book.opf")
        }
    }

    @Test func opensEPUB2ContentsWithEncodedLocalTarget() throws {
        let book = try EPUBPublication(data: archive(useNCX: true))
        #expect(book.contents.map(\.label) == ["First chapter", "山海"])
        #expect(book.contents.last?.target == EbookTarget(path: "OPS/chapters/山海.xhtml", fragment: "destination"))
    }

    @Test func followsLocalXHTMLFallbackForForeignSpineResources() async throws {
        let book = try EPUBPublication(data: archive(foreignSpineFallback: "first"))
        #expect(book.sectionPaths.first == "OPS/chapters/first.xhtml")
        #expect(book.contents.first?.label == "First chapter")
        #expect(book.contents.first?.target.path == "OPS/chapters/first.xhtml")
        let first = try await book.section(at: 0)
        #expect(!first.blocks.isEmpty)

        let cycle = try archive(foreignSpineFallback: "foreign")
        #expect(throws: EbookError.invalidPackage) { try EPUBPublication(data: cycle) }
    }

    @Test func rejectsProtectedAndFixedLayoutBooks() throws {
        let protected = try archive(additional: [("META-INF/encryption.xml", Data("<encryption/>".utf8))])
        #expect(throws: EbookError.protectedBook) { try EPUBPublication(data: protected) }

        let fixedLayout = try archive(layout: "<meta property=\"rendition:layout\">pre-paginated</meta>")
        #expect(throws: EbookError.unsupportedLayout) { try EPUBPublication(data: fixedLayout) }

        let vendorLayout = Data("""
            <display_options><platform name="*"><option name="fixed-layout">true</option></platform></display_options>
            """.utf8)
        let appleEPUB2 = try archive(useNCX: true, additional: [
            ("META-INF/com.apple.ibooks.display-options.xml", vendorLayout),
        ])
        #expect(throws: EbookError.unsupportedLayout) { try EPUBPublication(data: appleEPUB2) }
    }

    @Test func rejectsOversizedChapterBeforeParsing() async throws {
        let oversized = String(repeating: "x", count: 4_000_001)
        let book = try EPUBPublication(data: archive(firstChapter: oversized))
        await #expect(throws: EbookError.limitExceeded) {
            try await book.section(at: 0)
        }
    }

    @Test func rejectsMalformedChaptersAndArchive() async throws {
        let book = try EPUBPublication(data: archive(firstChapter: "<html><body><p>Incomplete"))
        await #expect(throws: EbookError.invalidMarkup) {
            try await book.section(at: 0)
        }
        #expect(throws: EbookError.invalidArchive) {
            try EPUBPublication(data: Data("not a ZIP archive".utf8))
        }
    }

    @MainActor
    @Test func importingAndReopeningRestoresEPUBChapterAndBlock() async throws {
        let temporary = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let original = temporary.appending(path: "Sample.epub")
        let storage = LibraryStorage(directory: temporary.appending(path: "Library"))
        let data = try archive()
        try data.write(to: original)

        let library = LibraryModel(storage: storage)
        _ = await library.restore()
        #expect(await library.importBook(at: original))
        let session = try #require(library.session)
        let position = EbookPosition(section: 1, block: 1)
        library.savePosition(position, in: session)
        #expect(try Data(contentsOf: original) == data)
        #expect(try Data(contentsOf: storage.bookURL(session.book)) == data)
        try FileManager.default.removeItem(at: original)

        let reopened = LibraryModel(storage: storage)
        #expect(await reopened.restore())
        let restored = try #require(reopened.session)
        guard case .ebook(let reading) = restored.content else {
            Issue.record("An EPUB should restore an ebook reading session.")
            return
        }
        #expect(restored.book.format == .epub)
        #expect(reading.position == position)
        #expect(reading.section.anchors["destination"] == 0)
    }

    private static let image = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j7ZkAAAAASUVORK5CYII="
    )!

    private func archive(useNCX: Bool = false, layout: String = "",
                         firstChapter: String = """
                            <html xmlns="http://www.w3.org/1999/xhtml">
                            <body><h1>First chapter</h1><img src="../images/cove.png" alt="Cove"/></body></html>
                            """,
                         additional: [(String, Data)] = [], foreignSpineFallback: String? = nil) throws -> Data {
        let archive = try Archive(accessMode: .create, pathEncoding: nil)
        let tocItem = useNCX
            ? "<item id=\"toc\" href=\"toc.ncx\" media-type=\"application/x-dtbncx+xml\"/>"
            : "<item id=\"toc\" href=\"nav.xhtml\" media-type=\"application/xhtml+xml\" properties=\"nav\"/>"
        let tocAttribute = useNCX ? " toc=\"toc\"" : ""
        let foreignItem = foreignSpineFallback.map { """
            <item id="foreign" href="foreign.xml" media-type="application/xml" fallback="\($0)"/>
            """ } ?? ""
        let firstSpineID = foreignSpineFallback == nil ? "first" : "foreign"
        let navigation = foreignSpineFallback == nil ? Self.navigation :
            Self.navigation.replacingOccurrences(of: "chapters/first.xhtml", with: "foreign.xml")
        try add("mimetype", data: Data("application/epub+zip".utf8), to: archive, compress: false)
        let markup: [(String, String)] = [
            ("META-INF/container.xml", """
                <container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">
                  <rootfiles><rootfile full-path="OPS/book.opf" media-type="application/oebps-package+xml"/></rootfiles>
                </container>
                """),
            ("OPS/book.opf", """
                <package xmlns="http://www.idpf.org/2007/opf" version="\(useNCX ? "2.0" : "3.0")">
                  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
                    <dc:title>Leaf テスト</dc:title>\(layout)
                  </metadata>
                  <manifest>
                    \(tocItem)
                    \(foreignItem)
                    <item id="first" href="chapters/first.xhtml" media-type="application/xhtml+xml"/>
                    <item id="last" href="chapters/%E5%B1%B1%E6%B5%B7.xhtml" media-type="application/xhtml+xml"/>
                    <item id="image" href="images/cove.png" media-type="image/png"/>
                  </manifest>
                  <spine\(tocAttribute)><itemref idref="\(firstSpineID)"/><itemref idref="last"/></spine>
                </package>
                """),
            ("OPS/chapters/first.xhtml", firstChapter),
            ("OPS/chapters/山海.xhtml", """
                <html xmlns="http://www.w3.org/1999/xhtml"><body>
                  <h1 id="destination">山海之间</h1><p>Chapter text.</p>
                </body></html>
                """),
            (useNCX ? "OPS/toc.ncx" : "OPS/nav.xhtml", useNCX ? Self.ncx : navigation),
        ]
        for (path, text) in markup {
            try add(path, data: Data(text.utf8), to: archive)
        }
        try add("OPS/images/cove.png", data: Self.image, to: archive, compress: false)
        if foreignSpineFallback != nil {
            try add("OPS/foreign.xml", data: Data("<book/>".utf8), to: archive)
        }
        for (path, data) in additional {
            try add(path, data: data, to: archive)
        }
        return try #require(archive.data)
    }

    private static let navigation = """
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><body>
          <nav epub:type="toc"><ol>
            <li><a href="chapters/first.xhtml">First chapter</a></li>
            <li><a href="chapters/%E5%B1%B1%E6%B5%B7.xhtml#destination">山海</a></li>
            <li><a href="https://example.invalid/">External label</a></li>
          </ol></nav>
        </body></html>
        """

    private static let ncx = """
        <!DOCTYPE ncx PUBLIC "-//NISO//DTD ncx 2005-1//EN" "http://www.daisy.org/z3986/2005/ncx-2005-1.dtd">
        <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
          <navMap>
            <navPoint id="first"><navLabel><text>First chapter</text></navLabel><content src="chapters/first.xhtml"/></navPoint>
            <navPoint id="last"><navLabel><text>山海</text></navLabel><content src="chapters/%E5%B1%B1%E6%B5%B7.xhtml#destination"/></navPoint>
          </navMap>
        </ncx>
        """

    private func add(_ path: String, data: Data, to archive: Archive, compress: Bool = true) throws {
        try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count),
                             compressionMethod: compress ? .deflate : .none) { offset, size in
            data.subdata(in: Int(offset)..<(Int(offset) + size))
        }
    }
}
