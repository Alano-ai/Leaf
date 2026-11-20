// SPDX-License-Identifier: GPL-3.0-only

import Observation
import PDFKit

@MainActor
struct ReadingSession {
    enum Content {
        case pdf(PDFDocument)
        case text(PlainText)
        case ebook(EbookReading)
    }

    let book: LibraryBook
    let content: Content
    let positionCount: Int
    let initialPosition: Int

    init(book: LibraryBook, file: ReadingFile) async throws {
        self.book = book
        switch file.content {
        case .text(let text):
            content = .text(text)
            positionCount = text.blocks.count
        case .pdf:
            guard let document = PDFDocument(data: file.data) else { throw ReadingError.invalidPDF }
            guard !document.isEncrypted, !document.isLocked else { throw ReadingError.protectedPDF }
            guard document.pageCount > 0, document.page(at: 0) != nil else { throw ReadingError.invalidPDF }
            content = .pdf(document)
            positionCount = document.pageCount
        case .ebook(let publication):
            let ebook = try await EbookReading(publication: publication, resume: book.ebookPosition ?? EbookPosition())
            content = .ebook(ebook)
            positionCount = publication.sectionPaths.count
        }
        initialPosition = min(max(book.position, 0), positionCount - 1)
    }
}

@MainActor
@Observable
final class LibraryModel {
    var books: [LibraryBook] { catalog.books }
    private(set) var session: ReadingSession?
    private(set) var busy = false
    private(set) var ready = false
    var message: String?

    private let storage: LibraryStorage
    private var catalog = LibraryCatalog()

    init(storage: LibraryStorage = .local) {
        self.storage = storage
    }

    func restore() async -> Bool {
        guard !ready, !busy else { return false }
        busy = true
        defer { busy = false }
        do {
            let storage = storage
            catalog = try await Task.detached { try storage.load() }.value
            ready = true
        } catch {
            message = String(localized: "Leaf couldn’t load its library. \(error.localizedDescription)")
        }
        guard ready, let book = books.first(where: { $0.id == catalog.lastOpenedBookID }) else { return false }
        do {
            session = try await prepare(book)
            return true
        } catch {
            message = error.localizedDescription
            var updated = catalog
            updated.lastOpenedBookID = nil
            try? commit(updated)
            return false
        }
    }

    func importBook(at url: URL) async -> Bool {
        guard ready, !busy else { return false }
        busy = true
        defer { busy = false }
        do {
            let prepared = try await Task.detached(priority: .userInitiated) { try ReadingFile.forImport(url) }.value
            let existing = books.first(where: { $0.id == prepared.book.id })
            let book = existing ?? prepared.book
            let opened = try await ReadingSession(book: book, file: prepared.file)
            let storage = storage
            try await Task.detached(priority: .userInitiated) {
                // The identifier stays the same when retrying a partial import or replacing a missing copy.
                if existing == nil || !FileManager.default.fileExists(atPath: storage.bookURL(book).path()) {
                    try storage.store(prepared.file.data, for: book)
                }
            }.value
            try select(opened, adding: existing == nil)
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    func open(_ book: LibraryBook) async -> Bool {
        guard ready, !busy else { return false }
        busy = true
        defer { busy = false }
        if session?.book.id == book.id { return true }
        do {
            try select(await prepare(book))
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    func position(for session: ReadingSession) -> Int {
        let saved = books.first(where: { $0.id == session.book.id })?.position ?? session.initialPosition
        return min(saved, session.positionCount - 1)
    }

    func savePosition(_ position: Int, in session: ReadingSession) {
        guard self.session?.book.id == session.book.id,
              (0..<session.positionCount).contains(position),
              let index = books.firstIndex(where: { $0.id == session.book.id }),
              catalog.books[index].position != position else { return }
        var updated = catalog
        updated.books[index].position = position
        saveReadingProgress(updated)
    }

    func ebookPosition(for session: ReadingSession, opening: EbookReading) -> EbookPosition {
        guard let saved = books.first(where: { $0.id == session.book.id })?.ebookPosition,
              opening.publication.sectionPaths.indices.contains(saved.section) else { return opening.position }
        // Reopening clamps or moves past a saved position whose section has no renderable content.
        if saved == session.book.ebookPosition { return opening.position }
        return saved
    }

    func savePosition(_ position: EbookPosition, in session: ReadingSession) {
        guard self.session?.book.id == session.book.id,
              (0..<session.positionCount).contains(position.section), position.block >= 0,
              let index = books.firstIndex(where: { $0.id == session.book.id }),
              catalog.books[index].ebookPosition != position else { return }
        var updated = catalog
        updated.books[index].ebookPosition = position
        saveReadingProgress(updated)
    }

    private func saveReadingProgress(_ updated: LibraryCatalog) {
        do {
            try commit(updated)
        } catch {
            message = String(localized: "Leaf couldn’t save your reading position. \(error.localizedDescription)")
        }
    }

    private func prepare(_ book: LibraryBook) async throws -> ReadingSession {
        let url = storage.bookURL(book)
        let file = try await Task.detached(priority: .userInitiated) {
            do {
                return try ReadingFile(url: url, format: book.format)
            } catch CocoaError.fileReadNoSuchFile {
                throw ReadingError.missingBook
            }
        }.value
        return try await ReadingSession(book: book, file: file)
    }

    private func select(_ opened: ReadingSession, adding: Bool = false) throws {
        var updated = catalog
        if adding { updated.books.insert(opened.book, at: 0) }
        updated.lastOpenedBookID = opened.book.id
        try commit(updated)
        session = opened
    }

    private func commit(_ updated: LibraryCatalog) throws {
        try storage.save(updated)
        catalog = updated
    }
}
