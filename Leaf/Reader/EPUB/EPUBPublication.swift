// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import ZIPFoundation

actor EPUBPublication: EbookPublication {
    nonisolated let title: String
    nonisolated let sectionPaths: [String]
    nonisolated let contents: [EbookContentsEntry]

    private let archive: EPUBArchive
    private let sectionPathSet: Set<String>
    private let sectionAliases: [String: String]
    private let imagePaths: Set<String>
    private let coverPath: String?

    private struct ManifestItem {
        let path: String?
        let mediaType: String
        let fallback: String?
    }

    init(data: Data) throws {
        let archive = try EPUBArchive(data: data)
        if archive.contains("META-INF/encryption.xml") { throw EbookError.protectedBook }
        guard try archive.data(at: "mimetype", limit: 128) == Data("application/epub+zip".utf8) else {
            throw EbookError.invalidPackage
        }
        let container = try BookXML.parse(archive.data(at: "META-INF/container.xml", limit: 128_000))
        guard container.name == "container",
              let root = container.child("rootfiles")?.children.first(where: {
                  $0.name == "rootfile" && $0.attributes["media-type"] == "application/oebps-package+xml"
              }),
              let packagePath = root.attributes["full-path"], EbookTarget.validEntry(packagePath) else {
            throw EbookError.invalidPackage
        }
        let package = try BookXML.parse(archive.data(at: packagePath, limit: 1_000_000))
        guard package.name == "package", let manifest = package.child("manifest"), let spine = package.child("spine")
        else { throw EbookError.invalidPackage }
        try Self.requireReflowable(package: package, spine: spine, archive: archive)

        var items: [String: ManifestItem] = [:]
        var navigationPath: String?
        var coverImage: String?
        for item in manifest.children where item.name == "item" {
            guard let id = item.attributes["id"], !id.isEmpty, items[id] == nil,
                  let href = item.attributes["href"], !href.isEmpty, let mediaType = item.attributes["media-type"] else {
                throw EbookError.invalidPackage
            }
            let target = EbookTarget.resolve(href, in: packagePath)
            let path = target?.fragment == nil ? target?.path : nil
            let properties = Set(item.attributes["properties"]?.split(whereSeparator: \.isWhitespace) ?? [])
            if properties.contains("cover-image") { coverImage = path }
            if properties.contains("nav") {
                guard navigationPath == nil, let path, mediaType == "application/xhtml+xml" else {
                    throw EbookError.invalidPackage
                }
                navigationPath = path
            }
            items[id] = ManifestItem(path: path, mediaType: mediaType, fallback: item.attributes["fallback"])
        }

        var aliases: [String: String] = [:]
        let sections = try spine.children.filter { $0.name == "itemref" }.map { entry in
            guard let id = entry.attributes["idref"] else { throw EbookError.invalidPackage }
            return try Self.sectionPath(for: id, items: items, archive: archive, aliases: &aliases)
        }
        guard !sections.isEmpty else { throw EbookError.invalidPackage }
        let paths = Set(sections)
        aliases = aliases.filter { !paths.contains($0.key) }
        let ncxPath = spine.attributes["toc"].flatMap { items[$0] }.flatMap {
            $0.mediaType == "application/x-dtbncx+xml" ? $0.path : nil
        }
        let toc = try Self.readContents(archive: archive, navigation: navigationPath, ncx: ncxPath,
                                       sections: paths, aliases: aliases)

        self.archive = archive
        sectionPaths = sections
        sectionPathSet = paths
        sectionAliases = aliases
        let images = Set(items.values.compactMap { item in
            ["image/png", "image/jpeg", "image/gif"].contains(item.mediaType) ? item.path : nil
        })
        imagePaths = images
        let metadata = package.child("metadata")
        let coverID = metadata?.all("meta").first(where: { $0.attributes["name"] == "cover" })?.attributes["content"]
        let epub2Cover = coverID.flatMap { items[$0]?.path }
        coverPath = (coverImage ?? epub2Cover).flatMap { images.contains($0) ? $0 : nil }
        let metadataTitle = metadata?.all("title").first?.label
        title = metadataTitle.flatMap { $0.isEmpty ? nil : String($0.prefix(512)) }
            ?? String(localized: "Untitled EPUB")
        contents = toc.isEmpty ? sections.enumerated().map { index, path in
            EbookContentsEntry(label: String(localized: "Section \(index + 1)"),
                               target: EbookTarget(path: path, fragment: nil))
        } : toc
    }

    func section(at index: Int) throws -> EbookSection {
        guard sectionPaths.indices.contains(index) else { throw EbookError.invalidPackage }
        let path = sectionPaths[index]
        let document = try BookXML.parse(archive.data(at: path, limit: 4_000_000))
        guard document.name == "html", let body = document.child("body") else { throw EbookError.invalidMarkup }
        return EbookMarkup.section(body: body, path: path, sections: sectionPathSet, images: imagePaths,
                                    sectionAliases: sectionAliases)
    }

    func imageData(at path: String) throws -> Data {
        guard imagePaths.contains(path) else { throw EbookError.invalidPackage }
        return try archive.data(at: path, limit: 8_000_000)
    }

    func coverData() throws -> Data? {
        guard let coverPath else { return nil }
        return try imageData(at: coverPath)
    }

    private static func sectionPath(for id: String, items: [String: ManifestItem], archive: EPUBArchive,
                                    aliases: inout [String: String]) throws -> String {
        var next: String? = id
        var seen: Set<String> = []
        var replaced: [String] = []
        while let current = next, seen.insert(current).inserted, let item = items[current] {
            try Task.checkCancellation()
            if let path = item.path, item.mediaType == "application/xhtml+xml", archive.contains(path) {
                for source in replaced where source != path { aliases[source] = path }
                return path
            }
            if let path = item.path { replaced.append(path) }
            next = item.fallback
        }
        throw EbookError.invalidPackage
    }

    private static func requireReflowable(package: BookXML.Node, spine: BookXML.Node,
                                          archive: EPUBArchive) throws {
        let fixedBook = package.child("metadata")?.all("meta").contains {
            $0.attributes["property"] == "rendition:layout" && $0.label == "pre-paginated"
        } == true
        let fixedSection = spine.children.contains {
            $0.name == "itemref" && $0.attributes["properties"]?.split(whereSeparator: \.isWhitespace)
                .contains("rendition:layout-pre-paginated") == true
        }
        if fixedBook || fixedSection { throw EbookError.unsupportedLayout }

        let appleOptions = "META-INF/com.apple.ibooks.display-options.xml"
        if archive.contains(appleOptions) {
            let options = try BookXML.parse(archive.data(at: appleOptions, limit: 128_000))
            if options.all("option").contains(where: {
                $0.attributes["name"] == "fixed-layout" && $0.label == "true"
            }) { throw EbookError.unsupportedLayout }
        }
    }

    private static func readContents(archive: EPUBArchive, navigation: String?, ncx: String?,
                                     sections: Set<String>, aliases: [String: String]) throws -> [EbookContentsEntry] {
        if let navigation {
            let document = try BookXML.parse(archive.data(at: navigation, limit: 1_000_000))
            let toc = document.all("nav").first(where: {
                $0.attributes["epub:type"]?.split(whereSeparator: \.isWhitespace).contains("toc") == true
            })
            return (toc?.all("a") ?? []).compactMap { link in
                contentsEntry(label: link.label, reference: link.attributes["href"], in: navigation,
                              sections: sections, aliases: aliases)
            }
        }
        guard let ncx else { return [] }
        let document = try BookXML.parse(archive.data(at: ncx, limit: 1_000_000))
        guard document.name == "ncx", let navigation = document.child("navMap") else {
            throw EbookError.invalidMarkup
        }
        return navigation.all("navPoint").compactMap { point in
            contentsEntry(label: point.child("navLabel")?.label ?? "",
                          reference: point.child("content")?.attributes["src"], in: ncx,
                          sections: sections, aliases: aliases)
        }
    }

    private static func contentsEntry(label: String, reference: String?, in path: String,
                                      sections: Set<String>, aliases: [String: String]) -> EbookContentsEntry? {
        guard !label.isEmpty, let reference, let resolved = EbookTarget.resolve(reference, in: path) else { return nil }
        let target = resolved.replacingPath(using: aliases)
        guard sections.contains(target.path) else { return nil }
        return EbookContentsEntry(label: String(label.prefix(512)), target: target)
    }
}

private struct EPUBArchive {
    private let archive: Archive
    private let files: [String: Entry]

    init(data: Data) throws {
        guard data.count <= 64_000_000 else { throw EbookError.limitExceeded }
        let checked: (archive: Archive, entries: [Entry])
        do {
            checked = try Archive.leafRead(data: data, maximumCount: 10_000)
        } catch Archive.LeafValidationError.encrypted {
            throw EbookError.protectedBook
        } catch Archive.LeafValidationError.tooManyEntries {
            throw EbookError.limitExceeded
        } catch {
            throw EbookError.invalidArchive
        }
        var total: UInt64 = 0
        var paths: Set<String> = []
        var files: [String: Entry] = [:]
        for entry in checked.entries {
            try Task.checkCancellation()
            let path = entry.type == .directory && entry.path.hasSuffix("/")
                ? String(entry.path.dropLast()) : entry.path
            guard !path.isEmpty, EbookTarget.validEntry(path), paths.insert(path).inserted, entry.type != .symlink
            else { throw EbookError.invalidArchive }
            guard entry.uncompressedSize <= 512_000_000 - total else { throw EbookError.limitExceeded }
            total += entry.uncompressedSize
            if entry.type == .file { files[path] = entry }
        }
        archive = checked.archive
        self.files = files
    }

    func contains(_ path: String) -> Bool { files[path] != nil }

    func data(at path: String, limit: Int) throws -> Data {
        guard let entry = files[path] else { throw EbookError.invalidPackage }
        guard entry.uncompressedSize <= limit else { throw EbookError.limitExceeded }
        try Task.checkCancellation()
        let expected = Int(entry.uncompressedSize)
        var data = Data()
        let checksum: CRC32
        do {
            checksum = try archive.extract(entry) { chunk in
                try Task.checkCancellation()
                guard chunk.count <= expected - data.count else { throw EbookError.invalidArchive }
                data.append(chunk)
            }
        } catch let cancellation as CancellationError {
            throw cancellation
        } catch {
            throw EbookError.invalidArchive
        }
        guard data.count == expected, checksum == entry.checksum else { throw EbookError.invalidArchive }
        return data
    }
}
