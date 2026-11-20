// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import ImageIO
import LeafConversion
import UniformTypeIdentifiers

enum ConversionSource {
    static func decode(_ data: Data, format: BookFormat) async throws -> ConversionBook {
        let publication = try ReadingFile.ebook(data, format: format)
        let entries = Dictionary(grouping: publication.contents, by: { $0.target.path })
        let coverData = try? await publication.coverData()
        let cover = coverData.flatMap(illustration)
        var images = cover.map { [$0] } ?? []
        var imageIndices: [String: Int] = [:]
        var unsupportedImages: Set<String> = []
        var chapters: [ConversionBook.Chapter] = []
        var bytes = cover?.byteCount ?? 0
        for (index, path) in publication.sectionPaths.enumerated() {
            try Task.checkCancellation()
            let section = try await publication.section(at: index)
            var labels: [Int: String] = [:]
            for entry in entries[path] ?? [] {
                let block = entry.target.fragment.flatMap { section.anchors[$0] } ?? 0
                if labels[block] == nil { labels[block] = entry.label }
            }
            var blocks: [ConversionBook.Chapter.Block] = []
            var title: String?
            for (block, content) in section.blocks.enumerated() {
                try Task.checkCancellation()
                if let label = labels[block] {
                    if !blocks.isEmpty { chapters.append(.init(title: title, blocks: blocks)) }
                    title = label
                    blocks = []
                }
                switch content {
                case .text(let attributed, let isHeading):
                    let line = String(attributed.characters)
                    if isHeading, line.trimmingCharacters(in: .whitespacesAndNewlines) == title { continue }
                    bytes += 2 + line.utf8.count
                    blocks.append(.text(line))
                case .image(let path, let alternative):
                    if unsupportedImages.contains(path) { continue }
                    if imageIndices[path] == nil {
                        guard let data = try? await publication.imageData(at: path), let image = illustration(data) else {
                            unsupportedImages.insert(path)
                            continue
                        }
                        if cover != nil && data == coverData {
                            imageIndices[path] = 0
                        } else {
                            imageIndices[path] = images.count
                            images.append(image)
                            bytes += image.byteCount
                        }
                    }
                    if let index = imageIndices[path] { blocks.append(.image(index, alternative: alternative)) }
                }
                guard bytes <= ReadingFile.sizeLimit else { throw ReadingError.tooLarge }
            }
            if !blocks.isEmpty { chapters.append(.init(title: title, blocks: blocks)) }
        }
        if chapters.isEmpty, cover != nil { chapters = [.init(blocks: [.image(0, alternative: "")])] }
        return ConversionBook(title: publication.title, chapters: chapters, illustrations: images,
                              coverIndex: cover == nil ? nil : 0)
    }

    private static func illustration(_ data: Data) -> ConversionBook.Illustration? {
        guard let raster = EbookMarkup.rasterSource(data: data) else { return nil }
        switch raster.type {
        case .jpeg: return .init(data: data, format: .jpeg)
        case .png: return .init(data: data, format: .png)
        case .gif: return .init(data: data, format: .gif)
        case .bmp:
            guard let image = CGImageSourceCreateImageAtIndex(raster.source, 0, nil) else { return nil }
            let bytes = NSMutableData()
            guard let output = CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil) else {
                return nil
            }
            CGImageDestinationAddImage(output, image, nil)
            return CGImageDestinationFinalize(output) ? .init(data: bytes as Data, format: .png) : nil
        default:
            return nil
        }
    }
}
