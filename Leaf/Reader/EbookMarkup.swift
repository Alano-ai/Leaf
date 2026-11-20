// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import ImageIO
import UniformTypeIdentifiers

struct EbookSection: Sendable {
    enum Block: Sendable {
        case text(AttributedString, heading: Bool)
        case image(path: String, alternative: String)
    }

    let blocks: [Block]
    let anchors: [String: Int]

    func clamp(_ block: Int) -> Int {
        min(max(block, 0), max(blocks.count - 1, 0))
    }
}

enum EbookMarkup {
    static func section(body: BookXML.Node, path: String, sections: Set<String>, images: Set<String>) -> EbookSection {
        var builder = Builder(path: path, sections: sections, images: images)
        builder.visit(body)
        builder.flush()
        return EbookSection(blocks: builder.blocks, anchors: builder.anchors)
    }

    static func rasterImage(data: Data, maximumSize: Int = 1_400) -> CGImage? {
        let uncached = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, uncached),
              let type = CGImageSourceGetType(source) as String?,
              [UTType.png.identifier, UTType.jpeg.identifier, UTType.gif.identifier, UTType.bmp.identifier].contains(type),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 16_000_000 / height else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumSize,
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }

    private struct Builder {
        struct Style {
            var intent: InlinePresentationIntent = []
            var link: URL?
            var heading = false
            var preformatted = false
        }

        private static let excluded: Set = [
            "script", "style", "iframe", "object", "audio", "video", "form", "template",
        ]
        private static let blocksByName: Set = [
            "h1", "h2", "h3", "h4", "h5", "h6", "p", "div", "section", "li", "ol", "ul",
            "aside", "blockquote", "pre", "figure", "figcaption", "table", "tr",
        ]

        let path: String
        let sections: Set<String>
        let images: Set<String>
        var blocks: [EbookSection.Block] = []
        var anchors: [String: Int] = [:]
        var text = AttributedString()
        var textLength = 0
        var heading = false

        mutating func visit(_ node: BookXML.Node, inheriting style: Style = Style()) {
            let name = node.name.lowercased()
            guard !Self.excluded.contains(name), node.attributes["hidden"] == nil else { return }
            let startsBlock = Self.blocksByName.contains(name)
            if startsBlock || name == "img" || name == "svg" { flush() }
            if let id = node.attributes["id"] ?? node.attributes["xml:id"]
                ?? (name == "a" ? node.attributes["name"] : nil), anchors[id] == nil {
                anchors[id] = blocks.count
            }
            if name == "img" {
                addImage(node.attributes["src"], alternative: node.attributes["alt"] ?? "")
                return
            }
            if name == "svg" {
                // Some EPUB covers wrap a single raster image in SVG. Read only the archive image reference.
                let images = node.all("image")
                if images.count == 1, let image = images.first {
                    addImage(image.attributes["href"] ?? image.attributes["xlink:href"],
                             alternative: node.child("title")?.label ?? "")
                }
                return
            }

            var style = style
            switch name {
            case "h1", "h2", "h3", "h4", "h5", "h6": style.heading = true
            case "b", "strong": style.intent.insert(.stronglyEmphasized)
            case "i", "em": style.intent.insert(.emphasized)
            case "pre": style.preformatted = true
            case "a":
                style.link = nil
                if let href = node.attributes["href"], let target = EbookTarget.resolve(href, in: path),
                   sections.contains(target.path) { style.link = target.readerURL }
            case "br": append("\n", style: style, preserveWhitespace: true)
            case "li": append("• ", style: style)
            case "td", "th": append(" ", style: style)
            default: break
            }

            for child in node.content {
                switch child {
                case .text(let value): append(value, style: style)
                case .element(let child): visit(child, inheriting: style)
                }
            }
            if startsBlock { flush() }
        }

        mutating func addImage(_ reference: String?, alternative: String) {
            guard let reference, let source = EbookTarget.resolve(reference, in: path),
                  images.contains(source.path) else { return }
            blocks.append(.image(path: source.path, alternative: alternative))
        }

        mutating func append(_ value: String, style: Style, preserveWhitespace: Bool = false) {
            let preserve = style.preformatted || preserveWhitespace
            var value = preserve ? value : Self.collapsedWhitespace(value)
            if !preserve, value.hasPrefix(" "), text.characters.last?.isWhitespace != false {
                value.removeFirst()
            }
            var remaining = value[...]
            while !remaining.isEmpty {
                let end = remaining.index(remaining.startIndex, offsetBy: 2_048 - textLength,
                                          limitedBy: remaining.endIndex) ?? remaining.endIndex
                let part = remaining[..<end]
                var run = AttributedString(part)
                if !style.intent.isEmpty { run.inlinePresentationIntent = style.intent }
                run.link = style.link
                text.append(run)
                textLength += part.count
                heading = heading || style.heading
                if textLength == 2_048 { flush() }
                remaining = remaining[end...]
            }
        }

        private static func collapsedWhitespace(_ text: String) -> String {
            let source = text.utf8
            var bytes: [UInt8] = []
            bytes.reserveCapacity(source.count)
            var previousWasSpace = false
            for byte in source {
                switch byte {
                case 9, 10, 13, 32:
                    if !previousWasSpace { bytes.append(32) }
                    previousWasSpace = true
                default:
                    bytes.append(byte)
                    previousWasSpace = false
                }
            }
            return String(decoding: bytes, as: UTF8.self)
        }

        mutating func flush() {
            if text.characters.contains(where: { !$0.isWhitespace }) {
                blocks.append(.text(text, heading: heading))
            }
            text = AttributedString()
            textLength = 0
            heading = false
        }
    }
}
