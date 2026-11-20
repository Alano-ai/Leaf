// SPDX-License-Identifier: GPL-3.0-only

import CryptoKit
import Foundation

enum BookFormat: String, Codable, Sendable {
    case pdf
    case txt

    var label: String { rawValue.uppercased() }
}

struct LibraryBook: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let format: BookFormat
    var position = 0

    static func identifier(for data: Data, format: BookFormat) -> String {
        "\(format.rawValue)-\(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())"
    }

    var hasValidIdentifier: Bool {
        let prefix = format.rawValue + "-"
        let digest = id.dropFirst(prefix.count)
        return id.hasPrefix(prefix) && digest.utf8.count == 64
            && digest.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}

struct LibraryCatalog: Codable, Sendable {
    var books: [LibraryBook] = []
    var lastOpenedBookID: LibraryBook.ID?
}

struct LibraryStorage: Sendable {
    static let local = Self(directory: URL.applicationSupportDirectory
        .appending(path: "Leaf/Library", directoryHint: .isDirectory))

    let directory: URL

    private var catalogURL: URL { directory.appending(path: "Catalog.json") }
    private var booksDirectory: URL { directory.appending(path: "Books", directoryHint: .isDirectory) }

    func load() throws -> LibraryCatalog {
        let data: Data
        do {
            data = try Data(contentsOf: catalogURL)
        } catch CocoaError.fileReadNoSuchFile {
            return LibraryCatalog()
        }
        let catalog = try JSONDecoder().decode(LibraryCatalog.self, from: data)
        guard catalog.books.allSatisfy({ $0.hasValidIdentifier && $0.position >= 0 }),
              Set(catalog.books.map(\.id)).count == catalog.books.count else {
            throw ReadingError.invalidCatalog
        }
        return catalog
    }

    func save(_ catalog: LibraryCatalog) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(catalog).write(to: catalogURL, options: .atomic)
    }

    func bookURL(_ book: LibraryBook) -> URL {
        booksDirectory.appending(path: "\(book.id).\(book.format.rawValue)")
    }

    func store(_ data: Data, for book: LibraryBook) throws {
        try FileManager.default.createDirectory(at: booksDirectory, withIntermediateDirectories: true)
        try data.write(to: bookURL(book), options: .atomic)
    }
}
