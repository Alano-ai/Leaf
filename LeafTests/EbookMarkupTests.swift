// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import Testing
@testable import Leaf

struct EbookMarkupTests {
    @Test func resolvesOnlyRelativeBookTargets() throws {
        let target = try #require(EbookTarget.resolve("../ch/%E5%B1%B1%E6%B5%B7.xhtml#%E8%8A%82", in: "OPS/nav/toc.xhtml"))
        #expect(target == EbookTarget(path: "OPS/ch/山海.xhtml", fragment: "节"))
        #expect(try EbookTarget(readerURL: #require(target.readerURL)) == target)

        for reference in ["https://example.invalid/x", "file:///tmp/book", "//example.invalid/x",
                          "../../outside", "/root/file", "assets%2Fpicture", "assets%5Cpicture"] {
            #expect(EbookTarget.resolve(reference, in: "OPS/book.xhtml") == nil)
        }
    }

    @Test func formatsLocalLinksAndRasterCoverWithoutRenderingActiveElements() throws {
        let source = """
        <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:xlink="http://www.w3.org/1999/xlink">
        <body><h1 id="chapter">山海</h1><p>A&nbsp;<em>line</em> and <a href="#chapter">a link</a>.
        <a href="https://example.invalid">External label</a></p>
        <svg><title>Local cover</title><image xlink:href="../images/cover.jpg"/></svg>
        <img src="https://example.invalid/cover.jpg"/>
        <script>ACTIVE_MARKER</script><iframe>FRAME_MARKER</iframe></body></html>
        """
        let path = "OPS/chapters/chapter.xhtml"
        let cover = "OPS/images/cover.jpg"
        let body = try #require(BookXML.parse(Data(source.utf8)).child("body"))
        let section = EbookMarkup.section(body: body, path: path, sections: [path], images: [cover])
        #expect(section.anchors["chapter"] == 0)
        let text = section.blocks.compactMap { block -> AttributedString? in
            if case .text(let value, _) = block { return value }
            return nil
        }
        let content = text.map { String($0.characters) }.joined()
        #expect(content.contains("A\u{00a0}line"))
        #expect(!content.contains("ACTIVE_MARKER"))
        #expect(!content.contains("FRAME_MARKER"))
        let links = text.flatMap { $0.runs.compactMap(\.link) }
        #expect(links.compactMap(EbookTarget.init(readerURL:)) == [EbookTarget(path: path, fragment: "chapter")])
        #expect(section.blocks.count == 3)
        if case .image(let path, let alternative) = section.blocks.last {
            #expect(path == cover)
            #expect(alternative == "Local cover")
        } else {
            Issue.record("Expected the local raster cover")
        }
    }

    @Test func rejectsUnknownDoctypeAndBoundsLongTextBlocks() throws {
        let externalDTD = """
        <!DOCTYPE html SYSTEM "https://example.invalid/book.dtd"><html><body>Text</body></html>
        """
        #expect(throws: EbookError.invalidMarkup) { try BookXML.parse(Data(externalDTD.utf8)) }
        let content = String(repeating: "章", count: 5_000)
        let body = try BookXML.parse(Data("<body><p>\(content)</p></body>".utf8))
        let section = EbookMarkup.section(body: body, path: "part.xhtml", sections: ["part.xhtml"], images: [])
        let chunks = section.blocks.compactMap { block -> String? in
            if case .text(let text, _) = block { return String(text.characters) }
            return nil
        }
        #expect(chunks.map(\.count) == [2_048, 2_048, 904])
        #expect(chunks.joined() == content)
    }
}
