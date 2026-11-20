// SPDX-License-Identifier: GPL-3.0-only

import CLibMobi
import Foundation

struct KindlePublication: EbookPublication {
    let title: String
    let sectionPaths: [String]
    let contents: [EbookContentsEntry]

    private let chapters: [Data]
    private let images: [String: Data]
    private let sectionNames: Set<String>
    private let imageNames: Set<String>
    private let coverPath: String?

    init(data: Data) throws {
        var status: Int32 = 0
        let document = data.withUnsafeBytes { bytes in
            leaf_kindle_load(bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count, &status)
        }
        guard let document else {
            switch status {
            case Int32(LEAF_KINDLE_PROTECTED): throw EbookError.protectedBook
            case Int32(LEAF_KINDLE_UNSUPPORTED): throw EbookError.unsupportedLayout
            case Int32(LEAF_KINDLE_LIMIT): throw EbookError.limitExceeded
            default: throw EbookError.invalidPackage
            }
        }
        defer { mobi_free(document) }
        guard let raw = mobi_init_rawml(document) else { throw EbookError.invalidPackage }
        defer { mobi_free_rawml(raw) }
        let result = mobi_parse_rawml_opt(raw, document, true, false, true)
        if result == MOBI_FILE_ENCRYPTED { throw EbookError.protectedBook }
        guard result == MOBI_SUCCESS else { throw EbookError.invalidPackage }

        let contents = try Self.copyParts(raw.pointee)
        title = Self.bookTitle(document)
        sectionPaths = contents.paths
        chapters = contents.chapters
        images = contents.images
        sectionNames = Set(contents.paths)
        imageNames = Set(contents.images.keys)
        if let cover = mobi_get_exthrecord_by_tag(document, EXTH_COVEROFFSET)?.pointee,
           let bytes = cover.data, [UInt32(1), 2, 4].contains(cover.size) {
            let offset = mobi_decode_exthvalue(bytes, Int(cover.size))
            let name = String(format: "resource%05u.", offset)
            coverPath = contents.images.keys.first { $0.hasPrefix(name) }
        } else {
            coverPath = nil
        }
        let table = try Self.readContents(contents.ncx, sections: Set(contents.paths))
        self.contents = table.isEmpty ? contents.paths.enumerated().map { index, path in
            EbookContentsEntry(label: String(localized: "Section \(index + 1)"),
                               target: EbookTarget(path: path, fragment: nil))
        } : table
    }

    func section(at index: Int) throws -> EbookSection {
        guard chapters.indices.contains(index) else { throw EbookError.invalidPackage }
        let body = try KindleHTML.parse(chapters[index])
        return EbookMarkup.section(body: body, path: sectionPaths[index], sections: sectionNames, images: imageNames)
    }

    func imageData(at path: String) throws -> Data {
        guard let data = images[path] else { throw EbookError.invalidPackage }
        return data
    }

    func coverData() -> Data? { coverPath.flatMap { images[$0] } }

    private static func bookTitle(_ document: UnsafeMutablePointer<MOBIData>) -> String {
        if let title = mobi_meta_get_title(document) {
            defer { free(title) }
            if let text = String(validatingCString: title)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty { return text }
        }
        let limit = 1_024
        var name = [CChar](repeating: 0, count: limit + 1)
        if mobi_get_fullname(document, &name, limit) == MOBI_SUCCESS,
           let text = name.withUnsafeBufferPointer({ $0.baseAddress.flatMap(String.init(validatingCString:)) })?
            .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return text
        }
        return String(localized: "Kindle Book")
    }

    private struct Parts {
        var paths: [String] = []
        var chapters: [Data] = []
        var images: [String: Data] = [:]
        var ncx: Data?
    }

    private static func copyParts(_ raw: MOBIRawml) throws -> Parts {
        var parts = Parts()
        var chapterBytes = 64 * 1024 * 1024
        var names: Set<String> = []
        var chapter = raw.markup
        while let pointer = chapter {
            let part = pointer.pointee
            chapter = part.next
            guard part.type == T_HTML else { continue }
            guard let data = part.data, part.size > 0 else { throw EbookError.invalidMarkup }
            guard part.size <= 32 * 1024 * 1024, part.size <= chapterBytes,
                  parts.chapters.count < 8_192 else { throw EbookError.limitExceeded }
            let path = String(format: "part%05zu.html", part.uid)
            guard names.insert(path).inserted else { throw EbookError.invalidPackage }
            chapterBytes -= part.size
            parts.paths.append(path)
            parts.chapters.append(Data(bytes: data, count: part.size))
        }
        guard !parts.chapters.isEmpty else { throw EbookError.unsupportedLayout }

        var imageBytes = 64 * 1024 * 1024
        var resource = raw.resources
        while let pointer = resource {
            let part = pointer.pointee
            resource = part.next
            guard let data = part.data, part.size > 0 else { continue }
            if part.type == T_NCX, parts.ncx == nil {
                guard part.size <= 1_000_000 else { throw EbookError.limitExceeded }
                parts.ncx = Data(bytes: data, count: part.size)
                continue
            }
            let fileExtension: String
            switch part.type {
            case T_JPG: fileExtension = "jpg"
            case T_PNG: fileExtension = "png"
            case T_GIF: fileExtension = "gif"
            case T_BMP: fileExtension = "bmp"
            default: continue
            }
            // Skip oversized images so the surrounding chapter can still show its alternative text.
            guard part.size <= 8_000_000, part.size <= imageBytes else { continue }
            let path = String(format: "resource%05zu.%@", part.uid, fileExtension)
            if parts.images[path] == nil {
                imageBytes -= part.size
                parts.images[path] = Data(bytes: data, count: part.size)
            }
        }
        return parts
    }

    private static func readContents(_ data: Data?, sections: Set<String>) throws -> [EbookContentsEntry] {
        guard let data else { return [] }
        let document = try BookXML.parse(data)
        return document.all("navPoint").compactMap { point in
            guard let path = point.child("content")?.attributes["src"],
                  let target = EbookTarget.resolve(path, in: "toc.ncx"),
                  sections.contains(target.path),
                  let label = point.child("navLabel")?.label, !label.isEmpty else { return nil }
            return EbookContentsEntry(label: label, target: target)
        }
    }
}

private enum KindleHTML {
    static func parse(_ data: Data) throws -> BookXML.Node {
        guard let document = data.withUnsafeBytes({ bytes in
            leaf_kindle_parse_html(bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count)
        }) else { throw EbookError.invalidMarkup }
        defer { leaf_kindle_free_html(document) }
        guard let body = leaf_kindle_html_body(document) else { throw EbookError.invalidMarkup }
        let root = BookXML.Node(name: "body", attributes: attributes(body, element: "body"))
        var budget = 500_000
        try appendChildren(of: body, to: root, depth: 1, budget: &budget)
        return root
    }

    private static let inactiveTags: Set<String> = [
        "script", "style", "iframe", "object", "audio", "video", "form", "template", "head"
    ]

    private static func appendChildren(of parent: OpaquePointer, to output: BookXML.Node,
                                       depth: Int, budget: inout Int) throws {
        guard depth <= 64 else { throw EbookError.limitExceeded }
        var next = leaf_kindle_html_first_child(parent)
        while let node = next {
            next = leaf_kindle_html_next(node)
            guard budget > 0 else { throw EbookError.limitExceeded }
            budget -= 1
            if budget.isMultiple(of: 256) { try Task.checkCancellation() }
            if let name = leaf_kindle_html_tag(node).flatMap(String.init(validatingCString:)),
               !inactiveTags.contains(name) {
                let attributes = attributes(node, element: name)
                let renderedName = name == "mbp:pagebreak" ? "div" : name
                let child = BookXML.Node(name: renderedName, attributes: attributes)
                try appendChildren(of: node, to: child, depth: depth + 1, budget: &budget)
                output.content.append(.element(child))
            } else if let text = leaf_kindle_html_text(node).flatMap(String.init(validatingCString:)) {
                output.content.append(.text(text))
            }
        }
    }

    private static func attributes(_ node: OpaquePointer, element: String) -> [String: String] {
        var attributes: [String: String] = [:]
        attributes["id"] = attribute("id", of: node)
        attributes["hidden"] = attribute("hidden", of: node)
        switch element {
        case "a":
            attributes["name"] = attribute("name", of: node)
            attributes["href"] = attribute("href", of: node)
        case "img":
            attributes["src"] = attribute("src", of: node)
            attributes["alt"] = attribute("alt", of: node)
        case "image":
            attributes["href"] = attribute("href", of: node)
            attributes["xlink:href"] = attribute("xlink:href", of: node)
        default:
            break
        }
        return attributes
    }

    private static func attribute(_ name: String, of node: OpaquePointer) -> String? {
        guard let value = leaf_kindle_html_attribute(node, name) else { return nil }
        defer { leaf_kindle_free_attribute(value) }
        guard strnlen(value, 4_097) <= 4_096 else { return nil }
        return String(validatingCString: value)
    }
}
