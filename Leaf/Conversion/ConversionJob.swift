// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import LeafConversion
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class ConversionJob {
    enum State {
        case idle
        case choosingDestination
        case converting
        case cancelling
        case saved(URL)
        case cancelled
        case failed(String)
    }

    private(set) var source: URL?
    private(set) var state = State.idle
    @ObservationIgnored private var operation: Task<Void, any Error>?

    var isBusy: Bool {
        switch state {
        case .choosingDestination, .converting, .cancelling: true
        default: false
        }
    }

    func chooseSource(_ result: Result<URL, any Error>) {
        guard !isBusy else { return }
        do {
            let url = try result.get()
            guard url.isFileURL, url.pathExtension.lowercased() == "txt" else {
                throw TXTToEPUB.ConversionError.unsupportedSource
            }
            source = url
            state = .idle
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func convert() async {
        guard let source, !isBusy else { return }
        state = .choosingDestination
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.epub]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = source.deletingPathExtension().lastPathComponent + ".epub"
        panel.prompt = String(localized: "Convert")

        let response: NSApplication.ModalResponse
        if let window = NSApp.keyWindow {
            response = await panel.beginSheetModal(for: window)
        } else {
            response = await panel.begin()
        }
        guard response == .OK, let destination = panel.url else {
            state = .idle
            return
        }

        state = .converting
        let work = Task.detached(priority: .userInitiated) {
            try TXTToEPUB.convert(source: source, destination: destination)
        }
        operation = work
        defer { operation = nil }
        do {
            try await work.value
            state = .saved(destination)
        } catch is CancellationError {
            state = .cancelled
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func cancel() {
        guard case .converting = state else { return }
        state = .cancelling
        operation?.cancel()
    }
}
