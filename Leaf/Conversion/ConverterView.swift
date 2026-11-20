// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

struct ConverterView: View {
    @Bindable var job: ConversionJob
    @State private var choosingSource = false
    @State private var hovering = false
    @State private var compatibility: CompatibilityCandidate?

    var body: some View {
        VStack(spacing: 0) {
            if job.sources.isEmpty {
                dropArea
                    .frame(maxWidth: 510)
                    .padding(28)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(job.sources) { source in sourceRow(source) }
                    .listStyle(.inset)
                    .accessibilityLabel("Files to Convert")
                Divider()
                controls
            }
        }
        .dropDestination(for: URL.self) { urls, _ in job.add(urls) } isTargeted: { hovering = $0 }
        .toolbar {
            Button("Add Files", systemImage: "plus") { choosingSource = true }
                .disabled(job.isBusy)
        }
        .fileImporter(isPresented: $choosingSource, allowedContentTypes: BookFormat.importTypes,
                      allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): job.add(urls)
            case .failure(let error): job.message = error.localizedDescription
            }
        }
        .alert("Leaf", isPresented: Binding(
            get: { job.message != nil },
            set: { if !$0 { job.message = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(job.message ?? "")
        }
        .sheet(item: $compatibility) { candidate in
            CompatibilityView(candidate: candidate)
        }
    }

    private var dropArea: some View {
        ContentUnavailableView {
            Label("Drop Books to Convert", systemImage: "arrow.left.arrow.right")
        } description: {
            Text("EPUB, MOBI, AZW3, PDF and TXT")
        } actions: {
            Button("Choose Files…") { choosingSource = true }
                .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 20)
        .background(hovering ? Color.accentColor.opacity(0.09) : Color.primary.opacity(0.025),
                    in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(hovering ? Color.accentColor : Color.secondary.opacity(0.38),
                              style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .allowsHitTesting(false)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            if job.target == .pdf || job.sources.contains(where: { $0.format == .pdf }) {
                Text("PDF conversion reflows text. Scanned PDFs need OCR first.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Picker("Output Format", selection: $job.target) {
                    ForEach(job.targets) { format in Text(verbatim: format.label).tag(format) }
                }
                .fixedSize()
                .disabled(job.isBusy)
                Spacer()
                if job.isConverting {
                    Button("Cancel", role: .cancel, action: job.cancel)
                } else if job.isCancelling {
                    ProgressView("Cancelling…").controlSize(.small)
                }
                Button("Convert…") { Task { await job.convert() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(!job.canConvert)
            }
        }
        .padding(18)
    }

    private func sourceRow(_ source: ConversionJob.Source) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "doc")
                .font(.title3)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: source.name).lineLimit(1)
                HStack(spacing: 8) {
                    Text(verbatim: source.format.label)
                    status(for: source.status)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Check Compatibility…", systemImage: "checkmark.shield") {
                let input = CompatibilityCandidate.File(url: source.url, format: source.format)
                if case .saved(let url) = source.status, let format = BookFormat(file: url) {
                    compatibility = CompatibilityCandidate(file: .init(url: url, format: format), original: input)
                } else {
                    compatibility = CompatibilityCandidate(file: input)
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help("Check Compatibility…")
            .disabled(job.isBusy)
            if case .saved(let url) = source.status {
                Button("Show in Finder", systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            }
            Button("Remove File", systemImage: "xmark") { job.remove(source.id) }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(job.isBusy)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func status(for status: ConversionJob.Source.Status) -> some View {
        switch status {
        case .ready: EmptyView()
        case .converting: Text("Converting…")
        case .cancelled: Text("Conversion cancelled.")
        case .skipped: Text("Already in the output format")
        case .saved: Label("Saved", systemImage: "checkmark.circle")
        case .failed(let message): Label(message, systemImage: "exclamationmark.circle").textSelection(.enabled)
        }
    }
}
