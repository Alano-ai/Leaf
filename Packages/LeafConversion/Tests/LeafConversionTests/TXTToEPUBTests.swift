// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import Testing
import ZIPFoundation
@testable import LeafConversion

struct TXTToEPUBTests {
    @Test func writesOCFMimetypeFirstAndEscapesTheTitleAndBody() throws {
        let files = try ConversionFiles("山海 & <叶>")
        defer { files.remove() }
        let text = "  Indented <script>& “山海”\r\n\r\nLine three\rEnd."
        let original = Data([0xef, 0xbb, 0xbf]) + Data(text.utf8)
        try original.write(to: files.source)
        try Data("Previous output".utf8).write(to: files.destination)
        try files.convert()

        let output = try Data(contentsOf: files.destination)
        let opened = try Archive.leafRead(data: output, maximumCount: 20)
        let first = try #require(opened.entries.first)
        #expect(first.path == "mimetype")
        #expect(!first.isCompressed)
        #expect(output.prefix(4) == Data([0x50, 0x4b, 0x03, 0x04]))
        #expect(output[8] == 0 && output[9] == 0 && output[28] == 0 && output[29] == 0)
        #expect(try files.entry("mimetype", in: opened.archive) == "application/epub+zip")
        let package = try files.entry("EPUB/package.opf", in: opened.archive)
        #expect(package.contains("<dc:title>山海 &amp; &lt;叶&gt;</dc:title>"))
        #expect(package.contains("property=\"dcterms:modified\""))
        #expect(package.contains("properties=\"nav\""))
        #expect(try files.entry("META-INF/container.xml", in: opened.archive).contains("EPUB/package.opf"))
        #expect(try files.preformattedText("EPUB/section-1.xhtml", in: opened.archive)
                == "  Indented <script>& “山海”\n\nLine three\nEnd.")
        #expect(try Data(contentsOf: files.source) == original)
        try files.expectNoTemporaryFiles()
    }

    @Test(arguments: [
        "山海".data(using: .utf16)!,
        Data([0xc9, 0xbd, 0xba, 0xa3]),
    ])
    func decodesBOMMarkedUTF16AndGB18030(source: Data) throws {
        let files = try ConversionFiles()
        defer { files.remove() }
        try source.write(to: files.source)
        try files.convert()
        let archive = try Archive(url: files.destination, accessMode: .read, pathEncoding: nil)
        #expect(try files.preformattedText("EPUB/section-1.xhtml", in: archive) == "山海")
    }

    @Test func splitsLargeTextIntoOrderedSectionsWithoutLosingContent() throws {
        let files = try ConversionFiles()
        defer { files.remove() }
        let text = String(repeating: "  A line of Chinese and Latin text. 山海之间\n", count: 5_000)
            + String(repeating: "尾", count: 50_000)
        try Data(text.utf8).write(to: files.source)
        try files.convert()
        let archive = try Archive(url: files.destination, accessMode: .read, pathEncoding: nil)
        let count = archive.filter { $0.path.hasPrefix("EPUB/section-") }.count
        #expect(count > 4)
        let restored = try (1...count).map { try files.preformattedText("EPUB/section-\($0).xhtml", in: archive) }.joined()
        #expect(restored == text)
        let contents = try files.entry("EPUB/nav.xhtml", in: archive)
        let package = try files.entry("EPUB/package.opf", in: archive)
        for index in 1...count {
            #expect(contents.contains("href=\"section-\(index).xhtml\""))
            #expect(package.contains("idref=\"s\(index)\""))
        }
    }

    @Test func cancellationAfterStagingPreservesAnExistingDestination() async throws {
        let files = try ConversionFiles()
        defer { files.remove() }
        let original = Data(String(repeating: "Text to convert.\n", count: 10_000).utf8)
        let existing = Data("Previous output".utf8)
        try original.write(to: files.source)
        try existing.write(to: files.destination)
        let reachedStaging = try await Task {
            var reachedStaging = false
            do {
                try TXTToEPUB.convert(source: files.source, destination: files.destination,
                                      temporaryDirectory: files.temporary) {
                    let entries = try FileManager.default.contentsOfDirectory(at: files.temporary, includingPropertiesForKeys: nil)
                    if let staging = entries.first?.appending(path: "Book.epub"),
                       (try? staging.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) ?? 0 > 22 {
                        reachedStaging = true
                        withUnsafeCurrentTask { $0?.cancel() }
                    }
                    try Task.checkCancellation()
                }
                Issue.record("Expected cancellation before publication")
            } catch is CancellationError {
                return reachedStaging
            }
            return false
        }.value
        #expect(reachedStaging)
        #expect(try Data(contentsOf: files.destination) == existing)
        #expect(try Data(contentsOf: files.source) == original)
        try files.expectNoTemporaryFiles()
    }

    @Test func rejectsHardLinkedDestinationAndPreservesSource() throws {
        let files = try ConversionFiles()
        defer { files.remove() }
        let original = Data("Source stays intact.".utf8)
        try original.write(to: files.source)
        try FileManager.default.linkItem(at: files.source, to: files.destination)
        #expect(throws: TXTToEPUB.ConversionError.sameFile) { try files.convert() }
        #expect(try Data(contentsOf: files.source) == original)
        #expect(try Data(contentsOf: files.destination) == original)
        try files.expectNoTemporaryFiles()
    }

    @Test func rejectsInvalidTextAndCleansUpAfterWritingFailure() throws {
        let files = try ConversionFiles()
        defer { files.remove() }
        try Data([0, 0, 0x81]).write(to: files.source)
        #expect(throws: TXTToEPUB.ConversionError.invalidText) { try files.convert() }
        #expect(!FileManager.default.fileExists(atPath: files.destination.path(percentEncoded: false)))
        try Data("Text before an invalid control character\u{01}.".utf8).write(to: files.source)
        #expect(throws: TXTToEPUB.ConversionError.invalidXMLCharacter) { try files.convert() }
        try files.expectNoTemporaryFiles()

        try Data("Valid text, unavailable output directory.".utf8).write(to: files.source)
        let unavailable = files.destination.deletingLastPathComponent().appending(path: "Deleted/Book.epub")
        #expect(throws: (any Error).self) {
            try TXTToEPUB.convert(source: files.source, destination: unavailable,
                                  temporaryDirectory: files.temporary, checkpoint: {})
        }
        #expect(!FileManager.default.fileExists(atPath: unavailable.path(percentEncoded: false)))
        try files.expectNoTemporaryFiles()
    }

    private struct ConversionFiles: Sendable {
        private let directory: URL
        let temporary: URL
        let source: URL
        let destination: URL

        init(_ name: String = "Test") throws {
            directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            temporary = directory.appending(path: "Staging")
            source = directory.appending(path: "\(name).txt")
            destination = directory.appending(path: "成品 Book.epub")
            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        }

        func remove() { try? FileManager.default.removeItem(at: directory) }

        func convert() throws {
            try TXTToEPUB.convert(source: source, destination: destination,
                                  temporaryDirectory: temporary, checkpoint: Task.checkCancellation)
        }

        func expectNoTemporaryFiles() throws {
            #expect(try FileManager.default.contentsOfDirectory(at: temporary, includingPropertiesForKeys: nil).isEmpty)
        }

        func entry(_ path: String, in archive: Archive) throws -> String {
            var bytes = Data()
            let entry = try #require(archive[path])
            let checksum = try archive.extract(entry) { bytes.append($0) }
            #expect(checksum == entry.checksum)
            return try #require(String(data: bytes, encoding: .utf8))
        }

        func preformattedText(_ path: String, in archive: Archive) throws -> String {
            let parser = XMLParser(data: Data(try entry(path, in: archive).utf8))
            let delegate = PreformattedText()
            parser.delegate = delegate
            #expect(parser.parse())
            return delegate.content
        }
    }

    private final class PreformattedText: NSObject, XMLParserDelegate {
        var capturing = false
        var content = ""

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String]) {
            if elementName == "pre" { capturing = true }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                    qualifiedName: String?) {
            if elementName == "pre" { capturing = false }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if capturing { content += string }
        }
    }
}
