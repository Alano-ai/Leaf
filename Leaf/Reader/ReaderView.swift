// SPDX-License-Identifier: GPL-3.0-only

import PDFKit
import SwiftUI

struct ReaderView: View {
    let session: ReadingSession
    let library: LibraryModel

    private var position: Int { library.position(for: session) }

    var body: some View {
        switch session.content {
        case .pdf(let document):
            PDFReader(document: document, position: position) {
                library.savePosition($0, in: session)
            }
        case .text(let document):
            TextReader(document: document, position: position) {
                library.savePosition($0, in: session)
            }
        }
    }
}

private struct PDFReader: View {
    let document: PDFDocument
    let position: Int
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
            Text("Page \(position + 1) of \(document.pageCount)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
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
            pdf.displayMode = .singlePage
            pdf.autoScales = true
            pdf.document = document
            if let page = document.page(at: position) { pdf.go(to: page) }
            view = pdf
        }
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
    let onPositionChange: (Int) -> Void
    @State private var visibleBlock: Int?
    @State private var phase = ScrollPhase.idle

    init(document: PlainText, position: Int, onPositionChange: @escaping (Int) -> Void) {
        self.document = document
        self.onPositionChange = onPositionChange
        _visibleBlock = State(initialValue: position)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(document.blocks.indices, id: \.self) { index in
                    Text(verbatim: String(document[index]))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .scrollTargetLayout()
            .font(.system(size: 17))
            .lineSpacing(4)
            .textSelection(.enabled)
            .frame(maxWidth: 680)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .scrollPosition(id: $visibleBlock, anchor: .top)
        .onScrollPhaseChange { _, current in
            phase = current
            if current == .idle { savePosition() }
        }
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
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 24)
                .background(.background)
        }
    }

    private func savePosition() {
        if let visibleBlock { onPositionChange(visibleBlock) }
    }
}
