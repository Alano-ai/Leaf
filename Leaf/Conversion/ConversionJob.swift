// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import LeafConversion
import Observation
import UniformTypeIdentifiers

extension BookFormat {
    var contentType: UTType {
        switch self {
        case .epub: .epub
        case .pdf: .pdf
        case .txt: .plainText
        case .mobi, .azw3: UTType(filenameExtension: rawValue, conformingTo: .data) ?? .data
        }
    }

    static var importTypes: [UTType] { allCases.map(\.contentType) }
}

@MainActor
@Observable
final class ConversionJob {
    struct Source: Identifiable, Sendable {
        enum Status: Sendable {
            case ready, converting, cancelled, skipped
            case saved(URL)
            case failed(String)
        }

        let url: URL
        let name: String
        let format: BookFormat
        var titleOverride: String?
        var status: Status = .ready
        var id: URL { url }
    }

    private enum Phase { case idle, choosing, converting, cancelling }

    private(set) var sources: [Source] = []
    var target: BookFormat = .epub {
        didSet {
            if oldValue != target {
                for index in sources.indices { sources[index].status = .ready }
            }
        }
    }
    var message: String?
    private var phase = Phase.idle
    @ObservationIgnored private var operation: Task<Void, Never>?

    var isBusy: Bool { phase != .idle }
    var isConverting: Bool { phase == .converting }
    var isCancelling: Bool { phase == .cancelling }
    var targets: [BookFormat] { BookFormat.allCases.filter { candidate in sources.isEmpty || sources.contains { $0.format != candidate } } }
    var canConvert: Bool { !isBusy && !sources.isEmpty }

    @discardableResult
    func add(_ urls: [URL]) -> Bool {
        guard !isBusy else { return false }
        let items = urls.compactMap { url in
            BookFormat(file: url).map { Source(url: url, name: url.deletingPathExtension().lastPathComponent, format: $0) }
        }
        if items.count != urls.count { message = ReadingError.unsupportedFormat.localizedDescription }
        add(items)
        return !items.isEmpty
    }

    func addBook(at url: URL, title: String, format: BookFormat) {
        guard !isBusy else { return }
        add([Source(url: url, name: title, format: format, titleOverride: title)])
    }

    private func add(_ items: [Source]) {
        var existing = Set(sources.map(\.url))
        for item in items where existing.insert(item.url).inserted { sources.append(item) }
        selectValidTarget()
    }

    func remove(_ id: URL) {
        guard !isBusy else { return }
        sources.removeAll { $0.id == id }
        selectValidTarget()
    }

    private func selectValidTarget() {
        if !targets.contains(target), let replacement = targets.first { target = replacement }
    }

    func convert() async {
        guard canConvert else { return }
        phase = .choosing
        let items = sources
        let target = target
        let destination: URL?
        if items.count == 1, let item = items.first {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [target.contentType]
            panel.canCreateDirectories = true
            panel.nameFieldStringValue = Self.fileStem(item.name) + "." + target.rawValue
            panel.prompt = String(localized: "Convert")
            destination = await choose(with: panel) == .OK ? panel.url : nil
        } else {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.prompt = String(localized: "Choose Output Folder")
            destination = await choose(with: panel) == .OK ? panel.url : nil
        }
        guard let destination else {
            phase = .idle
            return
        }

        for index in sources.indices { sources[index].status = .ready }
        phase = .converting
        let work = Task.detached(priority: .userInitiated) { [weak self] in
            let batch = items.count > 1
            let folderAccess = batch && destination.startAccessingSecurityScopedResource()
            defer { if folderAccess { destination.stopAccessingSecurityScopedResource() } }
            for item in items {
                guard item.format != target else {
                    await self?.update(item.id, to: .skipped)
                    continue
                }
                guard !Task.isCancelled else {
                    await self?.update(item.id, to: .cancelled)
                    continue
                }
                let output = batch ? Self.availableFile(in: destination, name: item.name, format: target) : destination
                await self?.update(item.id, to: .converting)
                do {
                    try await BookConversion.convert(source: item.url, destination: output, title: item.titleOverride,
                                                     replaceExisting: !batch, decodeEbook: ConversionSource.decode)
                    await self?.update(item.id, to: .saved(output))
                } catch is CancellationError {
                    await self?.update(item.id, to: .cancelled)
                } catch {
                    await self?.update(item.id, to: .failed(error.localizedDescription))
                }
            }
        }
        operation = work
        await work.value
        operation = nil
        phase = .idle
    }

    func cancel() {
        guard isConverting else { return }
        phase = .cancelling
        operation?.cancel()
    }

    private func update(_ id: URL, to status: Source.Status) {
        if let index = sources.firstIndex(where: { $0.id == id }) { sources[index].status = status }
    }

    private func choose(with panel: NSSavePanel) async -> NSApplication.ModalResponse {
        if let window = NSApp.keyWindow { return await panel.beginSheetModal(for: window) }
        return await panel.begin()
    }

    private nonisolated static func fileStem(_ title: String) -> String {
        var name = title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while name.utf8.count > 180 { name.removeLast() }
        return name.isEmpty || name.hasPrefix(".") ? String(localized: "Untitled") : name
    }

    private nonisolated static func availableFile(in folder: URL, name: String, format: BookFormat) -> URL {
        let stem = fileStem(name)
        var number = 1
        while true {
            let name = number == 1 ? stem : "\(stem) (\(number))"
            let file = folder.appending(path: name + "." + format.rawValue)
            if !FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) { return file }
            number += 1
        }
    }
}
