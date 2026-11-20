// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import UniformTypeIdentifiers

@main
struct NativeReaderApp: App {
    var body: some Scene {
        Window("Native EPUB Probe", id: "probe") {
            NativeReaderView()
                .frame(minWidth: 620, minHeight: 420)
        }
        .defaultSize(width: 900, height: 630)
    }
}

private struct NativeReaderView: View {
    @State private var book: NativeEPUB?
    @State private var chapter: EPUBChapter?
    @State private var section = 0
    @State private var scrollTarget = 0
    @State private var navigation = UUID()
    @State private var importing = false
    @State private var message: String?

    private let fixtures = Bundle.main.resourceURL!.appending(path: "Fixtures")

    var body: some View {
        Group {
            if let book, let chapter {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            ForEach(chapter.blocks.indices, id: \.self) { index in
                                block(chapter.blocks[index], in: book)
                                    .id(index)
                            }
                        }
                        .font(.system(size: 17, design: .serif))
                        .lineSpacing(5)
                        .padding(32)
                        .frame(maxWidth: 700)
                        .frame(maxWidth: .infinity)
                    }
                    .textSelection(.enabled)
                    .onChange(of: navigation, initial: true) { proxy.scrollTo(scrollTarget, anchor: .top) }
                }
                .environment(\.openURL, OpenURLAction { url in
                    guard let target = BookTarget(readerURL: url),
                          let index = book.spine.firstIndex(of: target.path) else { return .discarded }
                    show(index, fragment: target.fragment)
                    return .handled
                })
            } else {
                ContentUnavailableView("Open an EPUB", systemImage: "book")
            }
        }
        .navigationTitle(book?.title ?? "Native EPUB Probe")
        .toolbar {
            Button("Open", systemImage: "folder") { importing = true }
                .keyboardShortcut("o")
            Menu("Samples", systemImage: "books.vertical") {
                ForEach(["small.epub", "large.epub", "legacy.epub", "idpf-accessible.epub", "idpf-links.epub"],
                        id: \.self) { file in
                    let url = fixtures.appending(path: file)
                    if FileManager.default.fileExists(atPath: url.path()) {
                        Button(file) { open(url) }
                    }
                }
            }
            if let book {
                Menu("Contents", systemImage: "list.bullet") {
                    ForEach(Array(book.contents.enumerated()), id: \.offset) { _, item in
                        Button(item.label) {
                            if let index = book.spine.firstIndex(of: item.target.path) {
                                show(index, fragment: item.target.fragment)
                            }
                        }
                    }
                }
                Button("Previous Section", systemImage: "chevron.left") { show(section - 1) }
                    .disabled(section == 0)
                Button("Next Section", systemImage: "chevron.right") { show(section + 1) }
                    .disabled(section == book.spine.count - 1)
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.epub]) { result in
            do { open(try result.get()) }
            catch { message = error.localizedDescription }
        }
        .alert("Native EPUB Probe", isPresented: Binding(
            get: { message != nil }, set: { if !$0 { message = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
        .task {
            let arguments = CommandLine.arguments
            guard arguments.count == 3, arguments[1] == "--inspect",
                  !arguments[2].contains("/") else { return }
            inspect(fixtures.appending(path: arguments[2]))
        }
    }

    @ViewBuilder
    private func block(_ value: EPUBChapter.Block, in book: NativeEPUB) -> some View {
        switch value {
        case .text(let text, let heading):
            Text(text)
                .font(heading ? .title2.weight(.semibold) : nil)
                .accessibilityAddTraits(heading ? .isHeader : [])
        case .image(let path, let alternative):
            if let data = try? book.imageData(path), let image = EPUBChapter.rasterImage(data: data) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel(alternative)
            } else if !alternative.isEmpty {
                Text(verbatim: alternative)
            }
        }
    }

    private func open(_ url: URL) {
        do {
            let candidate = try NativeEPUB(url: url)
            chapter = try candidate.chapter(at: 0)
            book = candidate
            section = 0
            scrollTarget = 0
            navigation = UUID()
        } catch {
            message = error.localizedDescription
        }
    }

    private func show(_ index: Int, fragment: String? = nil) {
        guard let book, book.spine.indices.contains(index) else { return }
        do {
            let target = try book.chapter(at: index)
            chapter = target
            section = index
            scrollTarget = min(fragment.flatMap { target.anchors[$0] } ?? 0, max(0, target.blocks.count - 1))
            navigation = UUID()
        } catch {
            message = error.localizedDescription
        }
    }

    private func inspect(_ url: URL) {
        let clock = ContinuousClock()
        let start = clock.now
        do {
            let book = try NativeEPUB(url: url)
            let first = try book.chapter(at: 0)
            let prepare = start.duration(to: clock.now)
            let images = first.blocks.reduce(0) { count, block in
                guard case .image(let path, _) = block, let data = try? book.imageData(path),
                      EPUBChapter.rasterImage(data: data) != nil else { return count }
                return count + 1
            }
            let internalLinks = first.blocks.reduce(0) { count, block in
                guard case .text(let text, _) = block else { return count }
                return count + text.runs.filter { $0.link != nil }.count
            }
            let nextStart = clock.now
            let jump = book.contents.last?.target
            let nextIndex = jump.flatMap { book.spine.firstIndex(of: $0.path) } ?? 0
            let last = try book.chapter(at: nextIndex)
            let jumpDuration = nextStart.duration(to: clock.now)
            let fragmentResolved = jump?.fragment.map { last.anchors[$0] != nil } ?? true
            let scriptVisible = first.blocks.contains { block in
                guard case .text(let text, _) = block else { return false }
                return String(text.characters).contains("BOOK_SCRIPT_MARKER")
            }
            let readable = book.spine.indices.count { index in
                (try? book.chapter(at: index).blocks.isEmpty) == false
            }
            guard !first.blocks.isEmpty, !last.blocks.isEmpty else { throw EPUBError.invalidMarkup }
            print("sections=\(book.spine.count) toc=\(book.contents.count) blocks=\(first.blocks.count) "
                  + "images=\(images) links=\(internalLinks) jump_fragment=\(fragmentResolved) "
                  + "readable_sections=\(readable) script_visible=\(scriptVisible) "
                  + "prepare_ms=\(milliseconds(prepare)) jump_ms=\(milliseconds(jumpDuration))")
            exit(0)
        } catch {
            print(error.localizedDescription)
            exit(2)
        }
    }

    private func milliseconds(_ duration: Duration) -> Double {
        let value = duration.components
        return Double(value.seconds) * 1_000 + Double(value.attoseconds) / 1e15
    }
}
