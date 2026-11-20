// SPDX-License-Identifier: GPL-3.0-only

import Foundation

protocol EbookPublication: Sendable {
    var title: String { get }
    var sectionPaths: [String] { get }
    var contents: [EbookContentsEntry] { get }

    func section(at index: Int) async throws -> EbookSection
    func imageData(at path: String) async throws -> Data
    func coverData() async throws -> Data?
}

struct EbookContentsEntry: Hashable, Sendable {
    let label: String
    let target: EbookTarget
}

struct EbookPosition: Codable, Equatable, Sendable {
    var section = 0
    var block = 0
}

struct EbookReading: Sendable {
    let publication: any EbookPublication
    let section: EbookSection
    let position: EbookPosition

    init(publication: any EbookPublication, resume: EbookPosition) async throws {
        guard !publication.sectionPaths.isEmpty else { throw EbookError.invalidPackage }
        self.publication = publication
        let start = min(max(resume.section, 0), publication.sectionPaths.count - 1)
        var index = start
        var content = try await publication.section(at: index)
        // A few front-matter files can contain only styles or unsupported cover art.
        while content.blocks.isEmpty, index < publication.sectionPaths.count - 1, index - start < 16 {
            index += 1
            try Task.checkCancellation()
            content = try await publication.section(at: index)
        }
        guard !content.blocks.isEmpty else { throw EbookError.invalidMarkup }
        section = content
        position = EbookPosition(section: index, block: index == resume.section ? content.clamp(resume.block) : 0)
    }
}

enum EbookError: Error, LocalizedError, Equatable, Sendable {
    case invalidArchive
    case invalidPackage
    case invalidMarkup
    case protectedBook
    case unsupportedLayout
    case limitExceeded

    var errorDescription: String? {
        switch self {
        case .invalidArchive: String(localized: "This book’s archive is damaged or uses an unsupported ZIP structure.")
        case .invalidPackage: String(localized: "This book’s package or reading order couldn’t be read.")
        case .invalidMarkup: String(localized: "This book contains a section Leaf couldn’t display.")
        case .protectedBook: String(localized: "Leaf cannot read encrypted ebooks or protected resources.")
        case .unsupportedLayout: String(localized: "Leaf supports reflowable ebooks. This book uses an unsupported layout.")
        case .limitExceeded: String(localized: "This ebook exceeds Leaf’s reading limits.")
        }
    }
}

struct EbookTarget: Hashable, Sendable {
    let path: String
    let fragment: String?

    func replacingPath(using aliases: [String: String]) -> Self {
        Self(path: aliases[path] ?? path, fragment: fragment)
    }

    static func resolve(_ reference: String, in base: String) -> Self? {
        let source = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty, let url = URLComponents(string: source),
              url.scheme == nil, url.host == nil, url.query == nil,
              !url.percentEncodedPath.hasPrefix("/") else { return nil }
        if url.percentEncodedPath.isEmpty {
            return Self(path: base, fragment: url.fragment)
        }
        var result = base.split(separator: "/").dropLast().map(String.init)
        for encoded in url.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false) {
            guard let segment = encoded.removingPercentEncoding, validSegment(segment) else { return nil }
            switch segment {
            case ".": continue
            case "..":
                guard !result.isEmpty else { return nil }
                result.removeLast()
            default: result.append(segment)
            }
        }
        guard !result.isEmpty else { return nil }
        return Self(path: result.joined(separator: "/"), fragment: url.fragment)
    }

    static func validEntry(_ path: String) -> Bool {
        !path.isEmpty && path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
            validSegment(String($0)) && $0 != ".." && $0 != "."
        }
    }

    private static func validSegment(_ value: String) -> Bool {
        !value.isEmpty && !value.contains("/") && !value.contains("\\")
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    var readerURL: URL? {
        var url = URLComponents()
        url.scheme = "leaf-ebook"
        url.path = "/" + path
        url.fragment = fragment
        return url.url
    }

    init?(readerURL: URL) {
        guard readerURL.scheme == "leaf-ebook",
              let url = URLComponents(url: readerURL, resolvingAgainstBaseURL: false),
              url.host == nil, url.query == nil, url.path.hasPrefix("/") else { return nil }
        let path = String(url.path.dropFirst())
        guard Self.validEntry(path) else { return nil }
        self.init(path: path, fragment: url.fragment)
    }

    init(path: String, fragment: String?) {
        self.path = path
        self.fragment = fragment
    }
}
