// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import ImageIO
import LeafConversion
import UniformTypeIdentifiers

enum ConversionSource {
    static func decode(_ data: Data, format: BookFormat) async throws -> ConversionBook {
        let publication = try ReadingFile.ebook(data, format: format)
        let entries = Dictionary(grouping: publication.contents, by: { $0.target.path })
        var chapters: [ConversionBook.Chapter] = []
        var bytes = 0
        for (index, path) in publication.sectionPaths.enumerated() {
            try Task.checkCancellation()
            let section = try await publication.section(at: index)
            var labels: [Int: String] = [:]
            for entry in entries[path] ?? [] {
                let block = entry.target.fragment.flatMap { section.anchors[$0] } ?? 0
                if labels[block] == nil { labels[block] = entry.label }
            }
            var text = ""
            var title: String?
            for (block, content) in section.blocks.enumerated() {
                try Task.checkCancellation()
                if let label = labels[block] {
                    if !text.isEmpty { chapters.append(.init(title: title, text: text)) }
                    title = label
                    text = ""
                }
                guard case .text(let attributed, let isHeading) = content else { continue }
                let line = String(attributed.characters)
                if isHeading, line.trimmingCharacters(in: .whitespacesAndNewlines) == title { continue }
                bytes += 2 + line.utf8.count
                guard bytes <= ReadingFile.sizeLimit else { throw ReadingError.tooLarge }
                if !text.isEmpty { text += "\n\n" }
                text += line
            }
            if !text.isEmpty { chapters.append(.init(title: title, text: text)) }
        }
        let cover = (try? await publication.coverData()).flatMap { jpegCover($0) }
        return ConversionBook(title: publication.title, chapters: chapters, cover: cover)
    }

    private static func jpegCover(_ data: Data) -> Data? {
        guard let image = EbookMarkup.rasterImage(data: data, maximumSize: 1_000) else { return nil }
        let bytes = NSMutableData()
        guard let output = CGImageDestinationCreateWithData(bytes, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(output, image, nil)
        return CGImageDestinationFinalize(output) ? bytes as Data : nil
    }
}
