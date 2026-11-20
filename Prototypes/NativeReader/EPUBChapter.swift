// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import ImageIO
import UniformTypeIdentifiers

extension BookTarget {
    var readerURL: URL? {
        var components = URLComponents()
        components.scheme = "leaf-epub"
        components.path = "/" + path
        components.fragment = fragment
        return components.url
    }

    init?(readerURL: URL) {
        guard readerURL.scheme == "leaf-epub",
              let parts = URLComponents(url: readerURL, resolvingAgainstBaseURL: false),
              parts.host == nil, parts.query == nil, BookTarget.validEntry(String(parts.path.dropFirst())) else {
            return nil
        }
        self.init(path: String(parts.path.dropFirst()), fragment: parts.fragment)
    }
}

struct EPUBChapter {
    enum Block {
        case text(AttributedString, heading: Bool)
        case image(path: String, alternative: String)
    }

    let blocks: [Block]
    let anchors: [String: Int]

    init(body: BookXML.Node, path: String, spine: Set<String>, images: Set<String>) {
        var builder = Builder(path: path, spine: spine, images: images)
        builder.visit(body)
        builder.flush()
        blocks = builder.blocks
        anchors = builder.anchors
    }

    static func rasterImage(data: Data) -> CGImage? {
        let uncached = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, uncached),
              let type = CGImageSourceGetType(source) as String?,
              [UTType.png.identifier, UTType.jpeg.identifier, UTType.gif.identifier].contains(type),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 16_000_000 / height else { return nil }
        let thumbnail = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1_400
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnail)
    }

    private struct Builder {
        struct Style {
            var intent: InlinePresentationIntent = []
            var link: URL?
            var heading = false
            var preformatted = false
        }

        let path: String
        let spine: Set<String>
        let images: Set<String>
        var blocks: [Block] = []
        var anchors: [String: Int] = [:]
        var text = AttributedString()
        var heading = false

        mutating func visit(_ node: BookXML.Node, inheriting style: Style = Style()) {
            let name = node.name.lowercased()
            let excluded = ["script", "style", "iframe", "object", "audio", "video", "svg", "form", "template"]
            guard !excluded.contains(name), node.attributes["hidden"] == nil else { return }
            let startsBlock = ["h1", "h2", "h3", "h4", "h5", "h6", "p", "div", "section", "li", "ol", "ul",
                               "aside", "blockquote", "pre", "figure", "figcaption", "table", "tr"].contains(name)
            if startsBlock || name == "img" { flush() }
            if let id = node.attributes["id"] ?? node.attributes["xml:id"], anchors[id] == nil {
                anchors[id] = blocks.count
            }
            if name == "img" {
                guard let src = node.attributes["src"], let source = BookTarget.resolve(src, in: path),
                      images.contains(source.path) else { return }
                blocks.append(.image(path: source.path, alternative: node.attributes["alt"] ?? ""))
                return
            }

            var style = style
            switch name {
            case "h1", "h2", "h3", "h4", "h5", "h6": style.heading = true
            case "b", "strong": style.intent.insert(.stronglyEmphasized)
            case "i", "em": style.intent.insert(.emphasized)
            case "pre": style.preformatted = true
            case "a":
                if let href = node.attributes["href"], let target = BookTarget.resolve(href, in: path),
                   spine.contains(target.path) { style.link = target.readerURL }
            case "br": append("\n", style: style, preserveWhitespace: true)
            case "li": append("• ", style: style)
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

        mutating func append(_ value: String, style: Style, preserveWhitespace: Bool = false) {
            let preserve = style.preformatted || preserveWhitespace
            var value = preserve ? value : value.replacingOccurrences(of: #"[\t\r\n ]+"#,
                                                                       with: " ", options: .regularExpression)
            if !preserve, value.hasPrefix(" "), text.characters.last?.isWhitespace != false {
                value.removeFirst()
            }
            guard !value.isEmpty else { return }
            var run = AttributedString(value)
            if !style.intent.isEmpty { run.inlinePresentationIntent = style.intent }
            run.link = style.link
            text.append(run)
            heading = heading || style.heading
        }

        mutating func flush() {
            if text.characters.contains(where: { !$0.isWhitespace }) {
                blocks.append(.text(text, heading: heading))
            }
            text = AttributedString()
            heading = false
        }
    }
}
