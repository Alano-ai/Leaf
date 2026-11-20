// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import ZIPFoundation

enum EPUBError: String, Error, LocalizedError {
    case invalidZIP = "Invalid or unsupported EPUB ZIP container."
    case protectedBook = "Protected EPUB is outside this reader’s scope."
    case invalidPackage = "Invalid EPUB package or reading order."
    case invalidMarkup = "Unreadable EPUB markup."
    case fixedLayout = "This prototype supports reflowable EPUB only."
    case limit = "The book exceeds this prototype’s resource limits."

    var errorDescription: String? { rawValue }
}

struct BookTarget: Hashable {
    let path: String
    let fragment: String?

    static func resolve(_ reference: String, in base: String) -> Self? {
        guard let url = URLComponents(string: reference), url.scheme == nil, url.host == nil,
              url.query == nil, !url.percentEncodedPath.hasPrefix("/") else { return nil }
        let segments = url.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false)
        var result = base.split(separator: "/").dropLast().map(String.init)
        if url.percentEncodedPath.isEmpty {
            return Self(path: base, fragment: url.fragment)
        }
        for encoded in segments {
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
        path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
            validSegment(String($0)) && $0 != ".." && $0 != "."
        }
    }

    private static func validSegment(_ value: String) -> Bool {
        !value.isEmpty && !value.contains("/") && !value.contains("\\")
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }
}

final class NativeEPUB {
    struct ContentsEntry: Hashable {
        let label: String
        let target: BookTarget
    }

    let title: String
    let spine: [String]
    let contents: [ContentsEntry]
    private let zip: BookZIP
    private let imagePaths: Set<String>

    init(url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let zip = try BookZIP(bytes: try file.read(upToCount: 64_000_001) ?? Data())
        guard !zip.contains("META-INF/encryption.xml") else { throw EPUBError.protectedBook }
        guard try zip.data("mimetype", limit: 128) == Data("application/epub+zip".utf8) else {
            throw EPUBError.invalidPackage
        }
        let container = try BookXML.parse(zip.data("META-INF/container.xml", limit: 128_000))
        guard let path = container.all("rootfile").first?.attributes["full-path"] else {
            throw EPUBError.invalidPackage
        }
        let package = try BookXML.parse(zip.data(path, limit: 1_000_000))
        guard let manifest = package.child("manifest"), let readingOrder = package.child("spine") else {
            throw EPUBError.invalidPackage
        }
        if package.all("meta").contains(where: {
            $0.attributes["property"] == "rendition:layout" && $0.label == "pre-paginated"
        }) { throw EPUBError.fixedLayout }

        var resources: [String: (path: String, type: String, nav: Bool)] = [:]
        for item in manifest.children where item.name == "item" {
            guard let id = item.attributes["id"], resources[id] == nil, let href = item.attributes["href"],
                  let target = BookTarget.resolve(href, in: path), let type = item.attributes["media-type"] else {
                continue
            }
            let nav = item.attributes["properties"]?.split(whereSeparator: \.isWhitespace).contains("nav") == true
            resources[id] = (target.path, type, nav)
        }
        let spine = try readingOrder.children.filter { $0.name == "itemref" }.map { item in
            if item.attributes["properties"]?.split(whereSeparator: \.isWhitespace)
                .contains("rendition:layout-pre-paginated") == true { throw EPUBError.fixedLayout }
            guard let id = item.attributes["idref"], let resource = resources[id],
                  resource.type == "application/xhtml+xml", zip.contains(resource.path) else {
                throw EPUBError.invalidPackage
            }
            return resource.path
        }
        guard !spine.isEmpty else { throw EPUBError.invalidPackage }
        let paths = Set(spine)
        let nav = resources.values.first(where: \.nav)?.path
        let ncx = readingOrder.attributes["toc"].flatMap { resources[$0]?.path }

        self.zip = zip
        self.spine = spine
        imagePaths = Set(resources.values.filter {
            ["image/png", "image/jpeg", "image/gif"].contains($0.type)
        }.map(\.path))
        title = package.all("title").first?.label ?? url.deletingPathExtension().lastPathComponent
        let toc = try Self.readContents(zip: zip, nav: nav, ncx: ncx, spine: paths)
        contents = toc.isEmpty ? spine.enumerated().map { number, path in
            ContentsEntry(label: "Section \(number + 1)", target: BookTarget(path: path, fragment: nil))
        } : toc
    }

    func chapter(at index: Int) throws -> EPUBChapter {
        guard spine.indices.contains(index) else { throw EPUBError.invalidPackage }
        let path = spine[index]
        let document = try BookXML.parse(zip.data(path, limit: 4_000_000))
        guard let body = document.child("body") else { throw EPUBError.invalidMarkup }
        return EPUBChapter(body: body, path: path, spine: Set(spine), images: imagePaths)
    }

    func imageData(_ path: String) throws -> Data {
        guard imagePaths.contains(path) else { throw EPUBError.invalidPackage }
        return try zip.data(path, limit: 8_000_000)
    }

    private static func readContents(zip: BookZIP, nav: String?, ncx: String?,
                                     spine: Set<String>) throws -> [ContentsEntry] {
        if let nav {
            let document = try BookXML.parse(zip.data(nav, limit: 1_000_000))
            let toc = document.all("nav").first {
                $0.attributes["epub:type"]?.split(whereSeparator: \.isWhitespace).contains("toc") == true
            }
            return (toc?.all("a") ?? []).compactMap { link in
                guard let href = link.attributes["href"], let target = BookTarget.resolve(href, in: nav),
                      spine.contains(target.path), !link.label.isEmpty else { return nil }
                return ContentsEntry(label: link.label, target: target)
            }
        }
        guard let ncx else { return [] }
        let document = try BookXML.parse(zip.data(ncx, limit: 1_000_000))
        return document.all("navPoint").compactMap { point in
            guard let src = point.child("content")?.attributes["src"],
                  let target = BookTarget.resolve(src, in: ncx), spine.contains(target.path),
                  let label = point.child("navLabel")?.label, !label.isEmpty else { return nil }
            return ContentsEntry(label: label, target: target)
        }
    }
}

private struct BookZIP {
    let archive: Archive
    let entries: [String: Entry]

    init(bytes: Data) throws {
        guard bytes.count <= 64_000_000 else { throw EPUBError.limit }
        guard let archive = try? Archive(data: bytes, accessMode: .read, pathEncoding: nil) else {
            throw EPUBError.invalidZIP
        }
        guard archive.probeEntryCount <= 10_000 else { throw EPUBError.limit }
        var found: [String: Entry] = [:]
        var total: UInt64 = 0
        var count = 0
        for entry in archive {
            count += 1
            if entry.type == .directory { continue }
            guard entry.type == .file, BookTarget.validEntry(entry.path), found[entry.path] == nil,
                  entry.compressedSize <= bytes.count else {
                throw EPUBError.invalidZIP
            }
            guard entry.uncompressedSize <= 512_000_000 - total else { throw EPUBError.limit }
            total += entry.uncompressedSize
            found[entry.path] = entry
        }
        // ZIPFoundation's iterator ends on encrypted or malformed entries.
        guard count == archive.probeEntryCount else { throw EPUBError.invalidZIP }
        self.archive = archive
        self.entries = found
    }

    func contains(_ path: String) -> Bool { entries[path] != nil }

    func data(_ path: String, limit: Int) throws -> Data {
        guard let entry = entries[path] else { throw EPUBError.invalidPackage }
        guard entry.uncompressedSize <= limit else { throw EPUBError.limit }
        var result = Data()
        let checksum = try archive.extract(entry) { bytes in
            guard bytes.count <= limit - result.count else { throw EPUBError.limit }
            result.append(bytes)
        }
        guard result.count == entry.uncompressedSize, checksum == entry.checksum else { throw EPUBError.invalidZIP }
        return result
    }
}

final class BookXML: NSObject, XMLParserDelegate {
    final class Node {
        enum Content {
            case text(String)
            case element(Node)
        }

        let name: String
        let attributes: [String: String]
        var content: [Content] = []

        init(name: String, attributes: [String: String]) {
            self.name = name.split(separator: ":").last.map(String.init) ?? name
            self.attributes = attributes
        }

        var children: [Node] {
            content.compactMap { if case .element(let child) = $0 { child } else { nil } }
        }

        var label: String {
            content.map {
                switch $0 {
                case .text(let text): text
                case .element(let node): node.label
                }
            }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func child(_ name: String) -> Node? { children.first { $0.name == name } }

        func all(_ name: String) -> [Node] {
            var result: [Node] = []
            for child in children {
                if child.name == name { result.append(child) }
                result.append(contentsOf: child.all(name))
            }
            return result
        }
    }

    private var root: Node?
    private var stack: [Node] = []
    private var nodes = 0

    static func parse(_ data: Data) throws -> Node {
        guard let utf8 = String(data: data, encoding: .utf8), !utf8.contains("\0") else {
            throw EPUBError.invalidMarkup
        }
        if let declared = utf8.range(of: "<!DOCTYPE", options: .caseInsensitive) {
            let declaration = utf8[declared.lowerBound...].prefix { $0 != ">" }
            let words = declaration.lowercased().split(whereSeparator: \.isWhitespace)
            guard words == ["<!doctype", "html"] else { throw EPUBError.invalidMarkup }
        }
        let delegate = BookXML()
        let parser = XMLParser(data: data)
        parser.externalEntityResolvingPolicy = .never
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), let root = delegate.root else { throw EPUBError.invalidMarkup }
        return root
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String]) {
        nodes += 1
        guard nodes <= 100_000, stack.count < 64 else {
            parser.abortParsing()
            return
        }
        let node = Node(name: elementName, attributes: attributes)
        if let parent = stack.last { parent.content.append(.element(node)) } else { root = node }
        stack.append(node)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        stack.last?.content.append(.text(string))
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName: String?) {
        _ = stack.popLast()
    }
}
