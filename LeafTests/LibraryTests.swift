// SPDX-License-Identifier: GPL-3.0-only

import CoreGraphics
import Foundation
import Testing
@testable import Leaf

@MainActor
struct LibraryTests {
    @Test func legacyCatalogSupportsFavoritesAndRenamingWithoutMovingBooks() async throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let storage = LibraryStorage(directory: scratch)
        let content = Data("山海之间".utf8)
        let id = LibraryBook.identifier(for: content, format: .txt)
        let book = LibraryBook(id: id, title: "山海", format: .txt)
        try storage.store(content, for: book)
        let oldCatalog = """
        {"books":[{"id":"\(id)","title":"山海","format":"txt","position":0}],"lastOpenedBookID":"\(id)"}
        """
        try Data(oldCatalog.utf8).write(to: scratch.appending(path: "Catalog.json"))
        let library = LibraryModel(storage: storage)
        #expect(await library.restore())
        #expect(library.recentBooks.map(\.id) == [id])
        library.toggleFavorite(book)
        library.rename(book, to: "山海拾光")

        let reopened = LibraryModel(storage: storage)
        #expect(await reopened.restore())
        #expect(reopened.books.first?.title == "山海拾光")
        #expect(reopened.books.first?.favorite == true)
        #expect(try Data(contentsOf: storage.bookURL(book)) == content)
    }

    @Test func importsOneCopyAndRestoresTextPositionWithoutTheOriginal() async throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let storage = LibraryStorage(directory: scratch.appending(path: "Library"))
        let original = scratch.appending(path: "山海.txt")
        let duplicate = scratch.appending(path: "Copy.txt")
        let content = Data(String(repeating: "山海之间，Leaf reads local text.\n", count: 120).utf8)
        try content.write(to: original)
        try content.write(to: duplicate)

        let library = LibraryModel(storage: storage)
        #expect(await !library.restore())
        #expect(await library.importBook(at: original))
        let reading = try #require(library.session)
        #expect(library.books.map(\.title) == ["山海"])
        #expect(try Data(contentsOf: original) == content)
        library.savePosition(3, in: reading)
        #expect(await library.importBook(at: duplicate))
        #expect(library.books.count == 1)
        #expect(library.session?.initialPosition == 3)

        try FileManager.default.removeItem(at: original)
        try FileManager.default.removeItem(at: duplicate)
        let reopened = LibraryModel(storage: storage)
        #expect(await reopened.restore())
        #expect(reopened.books.map(\.id) == [reading.book.id])
        #expect(reopened.session?.initialPosition == 3)
        #expect(try Data(contentsOf: storage.bookURL(reading.book)) == content)
    }

    @Test func restoresPDFPageAndRepairsMissingCopyOnReimport() async throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let storage = LibraryStorage(directory: scratch.appending(path: "Library"))
        let original = scratch.appending(path: "Pages.pdf")
        try makePDF(at: original)

        let library = LibraryModel(storage: storage)
        _ = await library.restore()
        #expect(await library.importBook(at: original))
        let reading = try #require(library.session)
        #expect(reading.positionCount == 3)
        library.savePosition(2, in: reading)

        let reopened = LibraryModel(storage: storage)
        #expect(await reopened.restore())
        #expect(reopened.session?.initialPosition == 2)
        try FileManager.default.removeItem(at: storage.bookURL(reading.book))

        let repair = LibraryModel(storage: storage)
        #expect(await !repair.restore())
        #expect(repair.message == ReadingError.missingBook.errorDescription)
        #expect(repair.books.count == 1)
        #expect(await repair.importBook(at: original))
        #expect(repair.books.count == 1)
        #expect(repair.session?.initialPosition == 2)
        #expect(FileManager.default.fileExists(atPath: storage.bookURL(reading.book).path()))
    }

    @Test func rejectsProtectedMalformedAndUnsupportedFilesBeforeAddingEntries() async throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let storage = LibraryStorage(directory: scratch.appending(path: "Library"))
        let library = LibraryModel(storage: storage)
        _ = await library.restore()
        let protected = scratch.appending(path: "Protected.pdf")
        try makePDF(at: protected, passwordProtected: true)
        let brokenPDF = scratch.appending(path: "Broken.pdf")
        try Data("%PDF-1.4\nbroken".utf8).write(to: brokenPDF)
        let brokenText = scratch.appending(path: "Broken.txt")
        try Data([0, 0, 0x81]).write(to: brokenText)
        let unsupported = scratch.appending(path: "Unsupported.fb2")
        try Data([1]).write(to: unsupported)

        for (url, error) in [(protected, ReadingError.protectedPDF), (brokenPDF, .invalidPDF),
                             (brokenText, .invalidText), (unsupported, .unsupportedFormat)] {
            #expect(await !library.importBook(at: url))
            #expect(library.message == error.errorDescription)
        }
        #expect(library.books.isEmpty)
        #expect(library.session == nil)
        #expect(try storage.load().books.isEmpty)
    }

    @Test func preservesUnreadableCatalogAndDeclinesToImport() async throws {
        let storage = LibraryStorage(directory: try makeScratchDirectory())
        defer { try? FileManager.default.removeItem(at: storage.directory) }
        let catalog = storage.directory.appending(path: "Catalog.json")
        let broken = Data("corrupt catalog".utf8)
        try broken.write(to: catalog)
        let original = storage.directory.appending(path: "Book.txt")
        try Data("Still readable.".utf8).write(to: original)

        let library = LibraryModel(storage: storage)
        #expect(await !library.restore())
        #expect(library.message != nil)
        #expect(await !library.importBook(at: original))
        #expect(try Data(contentsOf: catalog) == broken)
    }

    private func makeScratchDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }

    private func makePDF(at url: URL, passwordProtected: Bool = false) throws {
        let options: [String: String] = passwordProtected
            ? [kCGPDFContextOwnerPassword as String: "owner", kCGPDFContextUserPassword as String: "reader"]
            : [:]
        var bounds = CGRect(x: 0, y: 0, width: 320, height: 400)
        let context = try #require(CGContext(url as CFURL, mediaBox: &bounds, options as CFDictionary))
        for page in 1...3 {
            context.beginPDFPage(nil)
            context.fill(CGRect(x: 30, y: 30, width: page * 40, height: 50))
            context.endPDFPage()
        }
        context.closePDF()
        let document = try #require(CGPDFDocument(url as CFURL))
        #expect(document.isEncrypted == passwordProtected)
    }
}
