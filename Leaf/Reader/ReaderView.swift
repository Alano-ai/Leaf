// SPDX-License-Identifier: GPL-3.0-only

import PDFKit
import SwiftUI

struct ReaderView: View {
    let session: ReadingSession
    let library: LibraryModel
    @AppStorage("reader.appearance") private var appearance = ReadingAppearance.system
    @AppStorage("reader.typeface") private var typeface = ReadingTypeface.serif
    @AppStorage("reader.layout") private var layout = ReadingLayout.single
    @AppStorage("reader.textSize") private var size = 17.0
    @AppStorage("reader.spacing") private var spacing = 5.0
    @AppStorage("reader.margins") private var margin = 32.0
    @State private var showingPreferences = false

    private var position: Int { library.position(for: session) }
    private var isPDF: Bool {
        if case .pdf = session.content { return true }
        return false
    }
    private var style: ReadingStyle {
        ReadingStyle(appearance: appearance, typeface: typeface, layout: layout, size: size,
                     spacing: spacing, margin: margin)
    }

    var body: some View {
        Group {
            switch session.content {
            case .pdf(let document):
                PDFReader(document: document, position: position, style: style) {
                    library.savePosition($0, in: session)
                }
            case .text(let document):
                TextReader(document: document, position: position, style: style) {
                    library.savePosition($0, in: session)
                }
            case .ebook(let opening):
                EbookReader(opening: opening, resume: library.ebookPosition(for: session, opening: opening), style: style) {
                    library.savePosition($0, in: session)
                } onFailure: {
                    library.message = $0.localizedDescription
                }
            }
        }
        .toolbar {
            Button("Reading Appearance", systemImage: "textformat.size") { showingPreferences.toggle() }
                .popover(isPresented: $showingPreferences, arrowEdge: .top) {
                    ReaderPreferences(appearance: $appearance, typeface: $typeface, layout: $layout, size: $size,
                                      spacing: $spacing, margin: $margin, fixedLayout: isPDF)
                }
        }
    }
}

private struct PDFReader: View {
    let document: PDFDocument
    let position: Int
    let style: ReadingStyle
    let onPositionChange: (Int) -> Void
    @State private var view: PDFView?

    var body: some View {
        Group {
            if let view {
                PDFSurface(view: view)
                    .onReceive(NotificationCenter.default.publisher(for: .PDFViewPageChanged, object: view)) { _ in
                        savePage(in: view)
                    }
            } else {
                ProgressView()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                Text("Page \(position + 1) of \(document.pageCount)")
                Spacer()
                Text(Double(position + 1) / Double(document.pageCount), format: .percent.precision(.fractionLength(0)))
                    .accessibilityLabel("Reading Position")
            }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, minHeight: 24)
                .background(.background)
        }
        .toolbar {
            ControlGroup {
                Button("Previous Page", systemImage: "chevron.left") {
                    view?.goToPreviousPage(nil)
                }
                .disabled(view == nil || position == 0)
                Button("Next Page", systemImage: "chevron.right") {
                    view?.goToNextPage(nil)
                }
                .disabled(view == nil || position >= document.pageCount - 1)
            }
            ControlGroup {
                Button("Zoom Out", systemImage: "minus.magnifyingglass") { view?.zoomOut(nil) }
                Button("Zoom In", systemImage: "plus.magnifyingglass") { view?.zoomIn(nil) }
            }
            .disabled(view == nil)
        }
        .task {
            guard view == nil else { return }
            let pdf = PDFView()
            updateLayout(pdf)
            pdf.autoScales = true
            pdf.document = document
            if let page = document.page(at: position) { pdf.go(to: page) }
            view = pdf
        }
        .onChange(of: style.layout) { if let view { updateLayout(view) } }
        .onChange(of: style.appearance) { if let view { view.backgroundColor = NSColor(style.appearance.background) } }
    }

    private func updateLayout(_ pdf: PDFView) {
        let page = document.page(at: position)
        switch style.layout {
        case .scrolling: pdf.displayMode = .singlePageContinuous
        case .single: pdf.displayMode = .singlePage
        case .spread: pdf.displayMode = .twoUp
        }
        pdf.backgroundColor = NSColor(style.appearance.background)
        if let page, pdf.document != nil { pdf.go(to: page) }
    }

    private func savePage(in view: PDFView) {
        guard let current = view.currentPage else { return }
        let index = document.index(for: current)
        if (0..<document.pageCount).contains(index) { onPositionChange(index) }
    }
}

private struct PDFSurface: NSViewRepresentable {
    let view: PDFView

    func makeCoordinator() -> LocalPDFActions { LocalPDFActions() }

    func makeNSView(context: Context) -> PDFView {
        view.delegate = context.coordinator
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {}

    final class LocalPDFActions: NSObject, PDFViewDelegate {
        func pdfViewWillClick(onLink sender: PDFView, with url: URL) {}
        func pdfViewOpenPDF(_ sender: PDFView, forRemoteGoToAction action: PDFActionRemoteGoTo) {}
    }
}

private struct TextReader: View {
    let document: PlainText
    let style: ReadingStyle
    let onPositionChange: (Int) -> Void
    @State private var visibleBlock: Int?
    @State private var phase = ScrollPhase.idle

    init(document: PlainText, position: Int, style: ReadingStyle, onPositionChange: @escaping (Int) -> Void) {
        self.document = document
        self.style = style
        self.onPositionChange = onPositionChange
        _visibleBlock = State(initialValue: position)
    }

    var body: some View {
        Group {
            if style.layout == .scrolling {
                scrollingReader
            } else {
                ReflowPager(count: document.blocks.count, start: visibleBlock ?? 0, block: { index in
                    .text(AttributedString(String(document[index])), heading: false)
                }, style: style, onPositionChange: { visibleBlock = $0 })
            }
        }
        .background(style.appearance.background)
        .onChange(of: visibleBlock) {
            if phase == .idle { savePosition() }
        }
        .onDisappear(perform: savePosition)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            savePosition()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            let current = visibleBlock ?? 0
            let progress = document.blocks.count == 1 ? 1.0 : Double(current) / Double(document.blocks.count - 1)
            Text(progress, format: .percent.precision(.fractionLength(0)))
                .font(.caption.monospacedDigit())
                .accessibilityLabel("Reading Position")
                .accessibilityValue(Text(progress, format: .percent.precision(.fractionLength(0))))
                .foregroundStyle(style.appearance.foreground.opacity(0.7))
                .frame(maxWidth: .infinity, minHeight: 24)
                .background(style.appearance.background)
        }
    }

    private var scrollingReader: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(document.blocks.indices, id: \.self) { index in
                    Text(verbatim: String(document[index]))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .scrollTargetLayout()
            .font(style.textFont())
            .lineSpacing(style.spacing)
            .foregroundStyle(style.appearance.foreground)
            .textSelection(.enabled)
            .frame(maxWidth: 680)
            .padding(style.margin)
            .frame(maxWidth: .infinity)
        }
        .scrollPosition(id: $visibleBlock, anchor: .top)
        .onScrollPhaseChange { _, current in
            phase = current
            if current == .idle { savePosition() }
        }
    }

    private func savePosition() {
        if let visibleBlock { onPositionChange(visibleBlock) }
    }
}
