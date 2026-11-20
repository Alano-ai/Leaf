// SPDX-License-Identifier: GPL-3.0-only

import CLibMobi
import Foundation
import LeafText
import PDFKit
import ZIPFoundation

public enum BookFormat: String, CaseIterable, Codable, Identifiable, Sendable {
    case epub, mobi, azw3, pdf, txt
    public var id: Self { self }
    public var label: String { rawValue.uppercased() }

    public init?(file: URL) {
        guard file.isFileURL else { return nil }
        self.init(rawValue: file.pathExtension.lowercased())
    }
}

public struct ConversionBook: Sendable {
    public struct Illustration: Sendable {
        public enum Format: String, Sendable {
            case jpeg, png, gif

            var mediaType: String { "image/\(rawValue)" }
        }

        let data: Data
        let format: Format
        public var byteCount: Int { data.count }

        public init(data: Data, format: Format) {
            self.data = data
            self.format = format
        }
    }

    public struct Chapter: Sendable {
        public enum Block: Sendable {
            case text(String)
            case image(Int, alternative: String)
        }

        let title: String?
        let blocks: [Block]

        public init(title: String? = nil, text: String) {
            self.init(title: title, blocks: [.text(text)])
        }

        public init(title: String? = nil, blocks: [Block]) {
            self.title = title
            self.blocks = blocks
        }

        var text: String {
            blocks.compactMap { if case .text(let text) = $0 { text } else { nil } }.joined(separator: "\n\n")
        }
    }

    public let title: String
    let chapters: [Chapter]
    let illustrations: [Illustration]
    let coverIndex: Int?

    public init(title: String, chapters: [Chapter], illustrations: [Illustration] = [], coverIndex: Int? = nil) {
        self.title = title
        self.chapters = chapters
        self.illustrations = illustrations
        self.coverIndex = coverIndex
    }

    var coverOutsideChapters: Int? {
        guard let coverIndex else { return nil }
        let alreadyPresent = chapters.contains { chapter in
            chapter.blocks.contains {
                if case .image(let index, _) = $0 { return index == coverIndex }
                return false
            }
        }
        return alreadyPresent ? nil : coverIndex
    }

    func validate(for format: BookFormat) throws {
        if let coverIndex, !illustrations.indices.contains(coverIndex) { throw BookConversion.Issue.unreadableBook }
        let supportsImages = format == .epub || format == .mobi || format == .azw3
        var hasContent = supportsImages && coverIndex != nil
        for chapter in chapters {
            try Task.checkCancellation()
            for block in chapter.blocks {
                switch block {
                case .text(let text):
                    if !hasContent { hasContent = text.contains { !$0.isWhitespace } }
                case .image(let index, _):
                    guard illustrations.indices.contains(index) else { throw BookConversion.Issue.unreadableBook }
                    if supportsImages { hasContent = true }
                }
            }
        }
        guard hasContent else { throw BookConversion.Issue.unreadableBook }
    }

    var text: String {
        chapters.map { chapter in
            [chapter.title, chapter.text].compactMap { $0 }.joined(separator: "\n\n")
        }.joined(separator: "\n\n")
    }
}

public enum BookConversion {
    /// The app supplies its existing EPUB and Kindle decoders so the reader and converter share those paths.
    public typealias EbookDecoder = @Sendable (Data, BookFormat) async throws -> ConversionBook

    public enum Issue: LocalizedError, Equatable {
        case unsupportedPair, protectedBook, unreadableBook, pdfWithoutText

        public var errorDescription: String? {
            switch self {
            case .unsupportedPair:
                String(localized: "Choose two different supported formats.", bundle: .module)
            case .protectedBook:
                String(localized: "Leaf cannot convert protected or encrypted books.", bundle: .module)
            case .unreadableBook:
                String(localized: "The book is empty, damaged, or does not match its file extension.", bundle: .module)
            case .pdfWithoutText:
                String(localized: "This PDF has no selectable text. Convert scanned pages with OCR first.", bundle: .module)
            }
        }
    }

    public static func convert(source: URL, destination: URL, title: String? = nil,
                               replaceExisting: Bool = true, decodeEbook: EbookDecoder? = nil) async throws {
        try Task.checkCancellation()
        guard let input = BookFormat(file: source), let output = BookFormat(file: destination), input != output else {
            throw Issue.unsupportedPair
        }
        let access = ConversionFiles.Access(source, destination)
        defer { access.end() }
        try ConversionFiles.validateDestination(destination, source: source)
        let bytes = try ConversionFiles.read(source)
        let defaultTitle = title ?? source.deletingPathExtension().lastPathComponent
        let book: ConversionBook
        switch input {
        case .txt:
            let text = try ConversionFiles.decodeText(bytes)
            book = ConversionBook(title: defaultTitle, chapters: [.init(text: text)])
        case .pdf:
            let document = try pdf(bytes)
            let bookTitle = title ?? (document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String) ?? defaultTitle
            book = ConversionBook(title: bookTitle, chapters: [.init(text: try extractText(document))])
        case .epub, .mobi, .azw3:
            guard let decodeEbook else { throw Issue.unreadableBook }
            let original = try await decodeEbook(bytes, input)
            book = ConversionBook(title: title ?? original.title, chapters: original.chapters,
                                  illustrations: original.illustrations, coverIndex: original.coverIndex)
        }
        try book.validate(for: output)
        let work = try ConversionFiles.workingDirectory(in: FileManager.default.temporaryDirectory)
        defer { try? FileManager.default.removeItem(at: work) }
        let staged = work.appending(path: "result.\(output.rawValue)")
        try Task.checkCancellation()
        switch output {
        case .txt:
            try Data(book.text.utf8).write(to: staged)
        case .epub:
            try EPUBPackage.write(book, to: staged, checkpoint: Task.checkCancellation)
        case .pdf:
            try PDFOutput.write(book.text, title: book.title, to: staged)
        case .mobi, .azw3:
            try KindleOutput.write(book, format: output, to: staged)
        }

        let result = try ConversionFiles.read(staged, output: true)
        switch output {
        case .epub:
            _ = try Archive.leafRead(data: result, maximumCount: 8_192)
        case .mobi, .azw3:
            try checkKindle(result)
        case .pdf:
            _ = try pdf(result)
        case .txt:
            break
        }
        try ConversionFiles.publish(result, to: destination, source: source,
                                    replaceExisting: replaceExisting, checkpoint: Task.checkCancellation)
    }

    private static func pdf(_ data: Data) throws -> PDFDocument {
        guard let document = PDFDocument(data: data) else { throw Issue.unreadableBook }
        guard !document.isLocked, !document.isEncrypted else { throw Issue.protectedBook }
        guard document.pageCount > 0, document.page(at: 0) != nil else { throw Issue.unreadableBook }
        return document
    }

    private static func extractText(_ document: PDFDocument) throws -> String {
        var pages: [String] = []
        var bytes = 0
        for index in 0..<document.pageCount {
            try Task.checkCancellation()
            guard let page = document.page(at: index)?.string,
                  page.contains(where: { !$0.isWhitespace }) else { continue }
            bytes += page.utf8.count + 2
            guard bytes <= ConversionFiles.limit else { throw TXTToEPUB.ConversionError.inputTooLarge }
            pages.append(page)
        }
        guard !pages.isEmpty else { throw Issue.pdfWithoutText }
        return pages.joined(separator: "\n\n")
    }

    private static func checkKindle(_ data: Data) throws {
        var status: Int32 = 0
        let book = data.withUnsafeBytes { bytes in
            leaf_kindle_load(bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count, &status)
        }
        guard let book else { throw Issue.unreadableBook }
        mobi_free(book)
    }
}
