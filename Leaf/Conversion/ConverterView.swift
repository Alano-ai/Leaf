// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import UniformTypeIdentifiers

struct ConverterView: View {
    let job: ConversionJob
    @State private var choosingSource = false

    var body: some View {
        Group {
            if let source = job.source {
                Form {
                    Section {
                        LabeledContent("TXT File") {
                            Text(verbatim: source.lastPathComponent)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Button("Choose Another File…") { choosingSource = true }
                            .disabled(job.isBusy)
                    }
                    Section {
                        HStack(spacing: 12) {
                            Button("Convert to EPUB…") {
                                Task { await job.convert() }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(job.isBusy)
                            if case .converting = job.state {
                                Button("Cancel", role: .cancel, action: job.cancel)
                            }
                        }
                        status
                    }
                }
                .formStyle(.grouped)
            } else {
                ContentUnavailableView {
                    Label("Convert TXT to EPUB", systemImage: "arrow.left.arrow.right")
                } description: {
                    Text("Choose a local TXT file to create an EPUB with a table of contents.")
                } actions: {
                    Button("Choose TXT File…") { choosingSource = true }
                    status
                }
            }
        }
        .fileImporter(isPresented: $choosingSource, allowedContentTypes: [.plainText]) { result in
            job.chooseSource(result)
        }
    }

    @ViewBuilder
    private var status: some View {
        switch job.state {
        case .idle, .choosingDestination:
            EmptyView()
        case .converting:
            ProgressView("Converting…")
        case .cancelling:
            ProgressView("Cancelling…")
        case .saved(let destination):
            VStack(alignment: .leading, spacing: 4) {
                Label("EPUB Saved", systemImage: "checkmark.circle")
                Text(verbatim: destination.path(percentEncoded: false))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        case .cancelled:
            Text("Conversion cancelled.")
                .foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.circle")
                .foregroundStyle(.secondary)
        }
    }
}
