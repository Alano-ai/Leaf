// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import PDFKit

/// A fixed set of structure checks. Keep this type free of filenames, metadata strings and book content.
struct CompatibilityReport: Codable, Sendable {
    enum Status: String, Codable {
        case readable, invalid, protected, unsupported, tooLarge, unavailable

        var label: String {
            switch self {
            case .readable: String(localized: "Opened in Leaf")
            case .invalid: String(localized: "Book structure could not be read")
            case .protected: String(localized: "Protected book")
            case .unsupported: String(localized: "Unsupported book layout")
            case .tooLarge: String(localized: "Book exceeds the reading limit")
            case .unavailable: String(localized: "File could not be accessed")
            }
        }
    }

    let format: BookFormat
    var status: Status = .unavailable
    var kindleHeaderVersion: Int?
    var sections: Int?
    var contentsEntries: Int?
    var unreadableSections: Int?
    var unresolvedContentsEntries: Int?
    var rasterImages: Int?
    var unreadableImages: Int?
    var hasReadableCover: Bool?
    var hasSelectableText: Bool?
}

struct CompatibilitySnapshot: Codable, Sendable {
    let file: CompatibilityReport
    let original: CompatibilityReport?
}

enum CompatibilityInspection {
    static func inspect(_ url: URL, format: BookFormat) async throws -> CompatibilityReport {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        var report = CompatibilityReport(format: format)
        do {
            try Task.checkCancellation()
            let file = try ReadingFile(url: url, format: format)
            report.status = .readable
            switch file.content {
            case .ebook(let publication):
                if format == .mobi || format == .azw3 {
                    report.kindleHeaderVersion = kindleHeaderVersion(file.data)
                }
                try await inspect(publication, report: &report)
            case .pdf:
                guard let document = PDFDocument(data: file.data), document.pageCount > 0 else {
                    report.status = .invalid
                    return report
                }
                guard !document.isEncrypted, !document.isLocked else {
                    report.status = .protected
                    return report
                }
                report.sections = document.pageCount
                report.hasSelectableText = false
                for index in 0..<document.pageCount {
                    try Task.checkCancellation()
                    if let text = document.page(at: index)?.string, text.contains(where: { !$0.isWhitespace }) {
                        report.hasSelectableText = true
                        break
                    }
                }
            case .text(let document):
                report.hasSelectableText = document.content.contains { !$0.isWhitespace }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch EbookError.protectedBook {
            report.status = .protected
        } catch EbookError.unsupportedLayout {
            report.status = .unsupported
        } catch ReadingError.tooLarge {
            report.status = .tooLarge
        } catch EbookError.limitExceeded {
            report.status = .tooLarge
        } catch is EbookError {
            report.status = .invalid
        } catch ReadingError.invalidText {
            report.status = .invalid
        } catch {
            report.status = .unavailable
        }
        return report
    }

    private static func inspect(_ publication: any EbookPublication, report: inout CompatibilityReport) async throws {
        let contents = Dictionary(grouping: publication.contents, by: \.target.path)
        var unreadableSections = 0
        var unresolvedEntries = 0
        var hasText = false
        var images = Set<String>()
        for (index, path) in publication.sectionPaths.enumerated() {
            try Task.checkCancellation()
            do {
                let section = try await publication.section(at: index)
                for entry in contents[path] ?? [] {
                    if let anchor = entry.target.fragment, section.anchors[anchor] == nil {
                        unresolvedEntries += 1
                    }
                }
                for block in section.blocks {
                    switch block {
                    case .text: hasText = true
                    case .image(let path, _): images.insert(path)
                    }
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                unreadableSections += 1
                unresolvedEntries += contents[path]?.count ?? 0
            }
        }

        var unreadableImages = 0
        for path in images {
            try Task.checkCancellation()
            if let data = try? await publication.imageData(at: path), EbookMarkup.rasterImage(data: data, maximumSize: 128) != nil {
                continue
            }
            unreadableImages += 1
        }
        let cover = try? await publication.coverData()
        try Task.checkCancellation()

        report.sections = publication.sectionPaths.count
        report.contentsEntries = publication.contents.count
        report.unreadableSections = unreadableSections
        report.unresolvedContentsEntries = unresolvedEntries
        report.rasterImages = images.count
        report.unreadableImages = unreadableImages
        report.hasReadableCover = cover.flatMap { EbookMarkup.rasterImage(data: $0, maximumSize: 128) } != nil
        report.hasSelectableText = hasText
    }

    private static func kindleHeaderVersion(_ data: Data) -> Int? {
        guard data.count >= 82 else { return nil }
        let offset = data[78..<82].reduce(0) { ($0 << 8) | Int($1) }
        guard offset <= data.count - 40, data[offset + 16..<offset + 20].elementsEqual("MOBI".utf8) else { return nil }
        return data[offset + 36..<offset + 40].reduce(0) { ($0 << 8) | Int($1) }
    }
}
