// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import LeafConversion
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

    @Test func converterErrorsUseTheAppLanguage() {
        let isSimplifiedChinese = Bundle.main.preferredLocalizations.first == "zh-Hans"
        let expected = isSimplifiedChinese ? "请选择要转换的本地 TXT 文件。" : "Choose a local TXT file to convert."
        #expect(TXTToEPUB.ConversionError.unsupportedSource.localizedDescription == expected)
    }
}
