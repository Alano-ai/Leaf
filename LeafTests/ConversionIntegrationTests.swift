// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import LeafConversion
import PDFKit
import Testing
@testable import Leaf

@MainActor
struct ConversionIntegrationTests {
    @Test func convertedBookImportsIntoLeafWithAReadableTableOfContents() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appending(path: "中文 & English.txt")
        let destination = directory.appending(path: "Converted.epub")
        let original = Data((String(repeating: "山海之间 & <text>\n", count: 4_000) + "\n尾声").utf8)
        try original.write(to: source)
        try TXTToEPUB.convert(source: source, destination: destination)

        let library = LibraryModel(storage: LibraryStorage(directory: directory.appending(path: "Library")))
        _ = await library.restore()
        #expect(await library.importBook(at: destination))
        let session = try #require(library.session)
        #expect(session.book.title == "中文 & English")
        #expect(session.book.format == .epub)
        guard case .ebook(let reading) = session.content else {
            Issue.record("Expected a reflowable EPUB session")
            return
        }
        #expect(reading.publication.contents.count > 1)
        #expect(reading.publication.contents.first?.label == String(localized: "Section \(1)"))
        let final = try await reading.publication.section(at: reading.publication.sectionPaths.count - 1)
        let text = final.blocks.compactMap { block -> String? in
            if case .text(let text, _) = block { String(text.characters) } else { nil }
        }.joined()
        #expect(text.contains("尾声"))
        #expect(try Data(contentsOf: source) == original)
    }

    @Test func allTwentyDirectionsReopenWithChineseText() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appending(path: "山海.txt")
        let marker = "山海之间"
        try Data("\(marker)\n\nA book with Chinese and English text.\n".utf8).write(to: input)
        for target in LeafConversion.BookFormat.allCases where target != .txt {
            let output = folder.appending(path: "山海.\(target.rawValue)")
            try await BookConversion.convert(source: input, destination: output, decodeEbook: ConversionSource.decode)
        }
        for source in LeafConversion.BookFormat.allCases {
            let file = folder.appending(path: "山海.\(source.rawValue)")
            let before = try Data(contentsOf: file)
            for target in LeafConversion.BookFormat.allCases where target != source {
                let output = folder.appending(path: "\(source.rawValue)-to-\(target.rawValue).\(target.rawValue)")
                do {
                    try await BookConversion.convert(source: file, destination: output, decodeEbook: ConversionSource.decode)
                    let reopened = try ReadingFile(url: output, format: target)
                    let text: String
                    switch reopened.content {
                    case .text(let document): text = document.content
                    case .pdf: text = PDFDocument(data: reopened.data)?.string ?? ""
                    case .ebook(let publication):
                        let section = try await publication.section(at: 0)
                        text = section.blocks.compactMap { block in
                            if case .text(let text, _) = block { String(text.characters) } else { nil }
                        }.joined()
                    }
                    #expect(text.contains(marker), "\(source.label) → \(target.label)")
                } catch {
                    Issue.record("\(source.label) → \(target.label) failed: \(error)")
                }
            }
            #expect(try Data(contentsOf: file) == before)
        }
    }

    @Test(arguments: [LeafConversion.BookFormat.mobi, .azw3])
    func kindleOutputKeepsChapterTitlesAndLinks(target: LeafConversion.BookFormat) async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appending(path: "Fixture.epub")
        let output = folder.appending(path: "Fixture.\(target.rawValue)")
        try Data().write(to: source)
        try await BookConversion.convert(source: source, destination: output) { _, _ in
            ConversionBook(title: "山海", chapters: [
                .init(title: "第一章", text: "海中有岛。"),
                .init(title: "第二章", text: "岛上有树。")
            ])
        }
        let file = try ReadingFile(url: output, format: target)
        guard case .ebook(let publication) = file.content else {
            Issue.record("Expected a Kindle publication")
            return
        }
        #expect(publication.contents.map(\.label) == ["第一章", "第二章"])
        let destination = try #require(publication.contents.last?.target)
        let sectionIndex = try #require(publication.sectionPaths.firstIndex(of: destination.path))
        let section = try await publication.section(at: sectionIndex)
        let blockIndex: Int
        if let fragment = destination.fragment {
            blockIndex = try #require(section.anchors[fragment])
        } else {
            blockIndex = 0
        }
        let selected = section.blocks[blockIndex...].compactMap { block in
            if case .text(let text, _) = block { String(text.characters) } else { nil }
        }.joined()
        #expect(selected.contains("岛上有树。"))
        #expect(!selected.contains("海中有岛。"))
    }

    @Test func converterErrorsUseTheAppLanguage() {
        let isSimplifiedChinese = Bundle.main.preferredLocalizations.first == "zh-Hans"
        let expected = isSimplifiedChinese ? "请选择要转换的本地 TXT 文件。" : "Choose a local TXT file to convert."
        #expect(TXTToEPUB.ConversionError.unsupportedSource.localizedDescription == expected)
    }
}
