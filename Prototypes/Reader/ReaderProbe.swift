// SPDX-License-Identifier: GPL-3.0-only

import CoreFoundation
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

struct ProbeError: LocalizedError {
    let errorDescription: String?

    init(_ message: String) { errorDescription = message }
}

struct TextBook {
    let encoding: String
    let lines: [String]

    init(data: Data) throws {
        let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        ))
        let candidates: [(String, String.Encoding)]
        if data.starts(with: [0xff, 0xfe]) || data.starts(with: [0xfe, 0xff]) {
            candidates = [("UTF-16", .utf16)]
        } else {
            candidates = [("UTF-8", .utf8), ("GB18030", gb18030)]
        }
        for (label, encoding) in candidates {
            if let text = String(data: data, encoding: encoding), !text.contains("\0"),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.encoding = label
                lines = text.components(separatedBy: .newlines)
                return
            }
        }
        throw ProbeError("No readable UTF-8, UTF-16 or GB18030 text was found")
    }
}

struct TextViewport: Equatable {
    var offset = 0.0
    var height = 0.0
    var contentHeight = 0.0
}

@MainActor
final class ProbeModel: ObservableObject {
    enum Content {
        case web(WebReader)
        case pdf(PDFView)
        case text(TextBook)
    }

    @Published private(set) var content: Content?
    @Published private(set) var title = "Leaf Reader Probe"
    @Published private(set) var status = ""
    @Published private(set) var chapters: [WebPage.Chapter] = []
    @Published private(set) var busy = false
    @Published private(set) var textTarget: Double?
    var viewport = TextViewport()
    var textReady = false
    private var webPage: WebPage?
    private let clock = ContinuousClock()

    var isPDF: Bool {
        if case .pdf = content { return true }
        return false
    }

    func open(_ url: URL) async throws -> [String: Any] {
        let start = clock.now
        busy = true
        defer { busy = false }
        content = nil
        chapters = []
        webPage = nil
        textTarget = nil
        viewport = TextViewport()
        textReady = false
        title = url.lastPathComponent
        status = "Opening…"
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let size = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard size.isRegularFile == true, let bytes = size.fileSize, bytes > 0, bytes <= 64 * 1024 * 1024 else {
            throw ProbeError("Choose a regular file between 1 byte and 64 MiB")
        }
        let format = url.pathExtension.lowercased()
        var details: [String: Any] = ["file": url.lastPathComponent, "bytes": bytes]
        switch format {
        case "epub", "mobi", "azw3":
            let web = WebReader(file: try Data(contentsOf: url, options: .mappedIfSafe))
            content = .web(web)
            let page = try await web.open(format: format)
            chapters = page.chapters ?? []
            update(page)
            details["firstPage"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(page))
        case "pdf":
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            guard let document = PDFDocument(data: data) else { throw ProbeError("Invalid PDF") }
            guard !document.isEncrypted, !document.isLocked else { throw ProbeError("Protected PDF is unsupported") }
            guard document.pageCount > 0 else { throw ProbeError("PDF has no pages") }
            let pdf = PDFView()
            pdf.displayMode = .singlePage
            pdf.autoScales = true
            pdf.document = document
            content = .pdf(pdf)
            guard try await waitUntil({ pdf.window != nil && pdf.currentPage != nil }) else {
                throw ProbeError("PDF viewport did not appear")
            }
            pdf.layoutSubtreeIfNeeded()
            status = "Page 1 of \(document.pageCount)"
            details["pages"] = document.pageCount
        case "txt":
            let book = try TextBook(data: Data(contentsOf: url, options: .mappedIfSafe))
            content = .text(book)
            guard try await waitUntil({ self.textReady && self.viewport.height > 0 }) else {
                throw ProbeError("TXT viewport did not appear")
            }
            status = book.encoding
            details["encoding"] = book.encoding
            details["lines"] = book.lines.count
            details["containsFixtureChinese"] = book.lines.first?.contains("山海之间") == true
        default:
            throw ProbeError("Choose an EPUB, MOBI, AZW3, PDF or TXT file")
        }
        details["firstPageMs"] = elapsed(since: start)
        return details
    }

    @discardableResult
    func move(_ forward: Bool) async throws -> Bool {
        switch content {
        case .web(let web):
            let prior = webPage?.cfi
            let page = try await web.run(forward
                ? "return JSON.stringify(await reader.next())"
                : "return JSON.stringify(await reader.previous())")
            update(page)
            return !page.cfi.isEmpty && page.cfi != prior
        case .pdf(let view):
            let prior = view.currentPage
            if forward { view.goToNextPage(nil) } else { view.goToPreviousPage(nil) }
            view.layoutSubtreeIfNeeded()
            if let doc = view.document, let page = view.currentPage {
                status = "Page \(doc.index(for: page) + 1) of \(doc.pageCount)"
            }
            return view.currentPage != prior
        case .text:
            let prior = viewport.offset
            let maximum = max(0, viewport.contentHeight - viewport.height)
            let step = viewport.height * (forward ? 0.85 : -0.85)
            let target = min(maximum, max(0, prior + step))
            guard abs(target - prior) > 2 else { return false }
            textTarget = target
            return try await waitUntil(timeout: .milliseconds(300)) {
                abs(self.viewport.offset - prior) > 1
            }
        case nil:
            return false
        }
    }

    @discardableResult
    func jump(_ chapter: WebPage.Chapter) async throws -> Bool {
        guard case .web(let web) = content else { return false }
        let page = try await web.run("return JSON.stringify(await reader.jump(href))", arguments: ["href": chapter.href])
        update(page)
        return page.targetVisible ?? (page.chapter == chapter.label)
    }

    @discardableResult
    func zoom() -> Bool {
        guard case .pdf(let pdf) = content else { return false }
        let initial = pdf.scaleFactor
        pdf.scaleFactor = min(initial * 1.25, pdf.maxScaleFactor)
        pdf.layoutSubtreeIfNeeded()
        return pdf.scaleFactor > initial
    }

    func show(_ error: any Error) {
        content = nil
        chapters = []
        status = error.localizedDescription
    }

    func benchmark(_ url: URL) async throws -> [String: Any] {
        var result = try await open(url)
        var turns: [Double] = []
        for _ in 0..<4 {
            let start = clock.now
            guard try await move(true) else { break }
            turns.append(elapsed(since: start))
        }
        if turns.isEmpty { throw ProbeError("The page or viewport did not advance") }
        result["turnMs"] = turns
        if isPDF { result["zoom"] = zoom() }
        if let chapter = chapters.last, chapters.count > 1 {
            result["jump"] = try await jump(chapter)
            result["jumpLabel"] = webPage?.chapter
        }
        return result
    }

    private func elapsed(since start: ContinuousClock.Instant) -> Double {
        let duration = (clock.now - start).components
        return Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15
    }

    private func update(_ page: WebPage) {
        webPage = page
        let location = "\(Int(min(100, max(0, page.fraction * 100))))%"
        status = page.chapter.isEmpty ? location : "\(page.chapter) · \(location)"
    }

    private func waitUntil(timeout: Duration = .seconds(3), _ ready: () -> Bool) async throws -> Bool {
        let deadline = clock.now + timeout
        while !ready() {
            if clock.now >= deadline { return false }
            try await Task.sleep(for: .milliseconds(5))
        }
        return true
    }
}

@main
struct ReaderProbe: App {
    var body: some Scene {
        Window("Leaf Reader Probe", id: "probe") {
            ProbeView()
                .frame(minWidth: 640, minHeight: 400)
        }
        .defaultSize(width: 920, height: 620)
        .windowResizability(.contentMinSize)
    }
}

struct ProbeView: View {
    @StateObject private var model = ProbeModel()
    @State private var picking = false
    private let fixtures = Bundle.main.resourceURL!.appending(path: "Fixtures")

    var body: some View {
        Group {
            switch model.content {
            case .web(let reader):
                HostView(view: reader.webView)
                    .id(ObjectIdentifier(reader.webView))
            case .pdf(let pdf):
                HostView(view: pdf)
                    .id(ObjectIdentifier(pdf))
            case .text(let book):
                NativeTextView(book: book, model: model)
                    .id(model.title)
            case nil:
                ContentUnavailableView("Open a Book", systemImage: "book",
                                       description: Text("Choose a local file or a test sample."))
            }
        }
        .safeAreaInset(edge: .bottom) {
            Text(model.status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 22)
        }
        .navigationTitle(model.title)
        .toolbar {
            Button("Open", systemImage: "folder") { picking = true }
                .keyboardShortcut("o")
                .disabled(model.busy)
            Menu("Samples", systemImage: "books.vertical") {
                ForEach(["small.epub", "large.epub", "fixed.epub", "small.mobi", "small.azw3",
                         "small.pdf", "small.txt", "legacy.txt"], id: \.self) { sample in
                    Button(sample) { open(fixtures.appending(path: sample)) }
                }
            }
            .disabled(model.busy)
            if !model.chapters.isEmpty {
                Menu("Contents", systemImage: "list.bullet") {
                    ForEach(model.chapters, id: \.self) { chapter in
                        Button(chapter.label) { interact { try await model.jump(chapter) } }
                    }
                }
                .disabled(model.busy)
            }
            Button("Previous Page", systemImage: "chevron.left") { interact { try await model.move(false) } }
                .disabled(model.content == nil || model.busy)
            Button("Next Page", systemImage: "chevron.right") { interact { try await model.move(true) } }
                .disabled(model.content == nil || model.busy)
            if model.isPDF {
                Button("Zoom In", systemImage: "plus.magnifyingglass") { model.zoom() }
            }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.data]) { result in
            switch result {
            case .success(let url): open(url)
            case .failure(let error): model.show(error)
            }
        }
        .task {
            guard CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--benchmark" else { return }
            let sample = CommandLine.arguments[2]
            let watchdog = Task {
                try? await Task.sleep(for: .seconds(20))
                if !Task.isCancelled {
                    print("PROBE_RESULT {\"error\":\"Benchmark timed out\"}")
                    exit(2)
                }
            }
            do {
                let result = try await model.benchmark(fixtures.appending(path: sample))
                output(result)
                watchdog.cancel()
                exit(0)
            } catch {
                output(["file": sample, "error": error.localizedDescription])
                watchdog.cancel()
                exit(2)
            }
        }
    }

    private func open(_ url: URL) {
        Task {
            do { _ = try await model.open(url) }
            catch { model.show(error) }
        }
    }

    private func interact(_ action: @escaping () async throws -> Bool) {
        Task {
            do { _ = try await action() }
            catch { model.show(error) }
        }
    }

    private func output(_ payload: [String: Any]) {
        let json = try! JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        print("PROBE_RESULT \(String(decoding: json, as: UTF8.self))")
    }
}

private struct NativeTextView: View {
    let book: TextBook
    @ObservedObject var model: ProbeModel
    @State private var position = ScrollPosition()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 5) {
                ForEach(book.lines.indices, id: \.self) { index in
                    Text(verbatim: book.lines[index])
                        .onAppear {
                            if index == 0 { model.textReady = true }
                        }
                }
            }
            .font(.system(size: 17))
            .lineSpacing(4)
            .frame(maxWidth: 680, alignment: .leading)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .scrollPosition($position)
        .onChange(of: model.textTarget) { _, target in
            if let target { position.scrollTo(y: target) }
        }
        .onScrollGeometryChange(for: TextViewport.self) { geometry in
            TextViewport(offset: geometry.contentOffset.y, height: geometry.containerSize.height,
                         contentHeight: geometry.contentSize.height)
        } action: { _, viewport in
            model.viewport = viewport
        }
    }
}
