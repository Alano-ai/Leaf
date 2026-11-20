// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

struct CompatibilityCandidate: Identifiable, Sendable {
    struct File: Sendable {
        let url: URL
        let format: BookFormat
    }

    let file: File
    var original: File?
    var id: URL { file.url }
}

struct CompatibilityView: View {
    let candidate: CompatibilityCandidate
    @Environment(\.dismiss) private var dismiss
    @State private var snapshot: CompatibilitySnapshot?
    @State private var analysis: Task<Void, Never>?
    @State private var suggestion: String?
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Compatibility Check").font(.headline)
            Text(verbatim: candidate.file.url.lastPathComponent)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Divider()
            if let snapshot {
                ScrollViewReader { reader in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if let original = snapshot.original {
                                details("Original File", report: original)
                            }
                            details(snapshot.original == nil ? "Checked File" : "Converted File", report: snapshot.file)
                            if let suggestion {
                                Divider()
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("DeepSeek Suggestions").font(.headline)
                                    Text(verbatim: suggestion).textSelection(.enabled)
                                }
                                .id("suggestion")
                            }
                            if let message {
                                Label(message, systemImage: "exclamationmark.circle")
                                    .textSelection(.enabled)
                                    .id("error")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onChange(of: suggestion) { if suggestion != nil { reader.scrollTo("suggestion", anchor: .top) } }
                    .onChange(of: message) { if message != nil { reader.scrollTo("error", anchor: .bottom) } }
                }
            } else if let message {
                Label(message, systemImage: "exclamationmark.circle")
                Spacer()
            } else {
                ProgressView("Checking locally…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            Text("DeepSeek receives the format, counts, and check results shown here. Book text, images, titles, and filenames stay on this Mac. Your DeepSeek account may be charged.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                SettingsLink { Text("Open Leaf Settings") }
                Spacer()
                if analysis != nil {
                    ProgressView().controlSize(.small)
                }
                Button("Ask DeepSeek", action: ask)
                    .disabled(snapshot == nil || analysis != nil)
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 585, height: 525)
        .task { await inspect() }
        .onDisappear { analysis?.cancel() }
    }

    private func details(_ title: LocalizedStringKey, report: CompatibilityReport) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.headline)
            LabeledContent("Format", value: report.format.label)
            LabeledContent("Local Result", value: report.status.label)
            if let version = report.kindleHeaderVersion {
                LabeledContent("Kindle Header Version", value: version.formatted())
            }
            if let sections = report.sections {
                LabeledContent(report.format == .pdf ? "Pages" : "Sections", value: sections.formatted())
            }
            if let entries = report.contentsEntries {
                LabeledContent("Contents Entries", value: entries.formatted())
            }
            if let images = report.rasterImages {
                LabeledContent("Raster Images", value: images.formatted())
            }
            if let cover = report.hasReadableCover {
                LabeledContent("Readable Cover", value: availability(cover))
            }
            if let text = report.hasSelectableText {
                LabeledContent("Selectable Text", value: availability(text))
            }
            if let unreadable = report.unreadableSections, unreadable > 0 {
                LabeledContent("Unreadable Sections", value: unreadable.formatted())
            }
            if let unresolved = report.unresolvedContentsEntries, unresolved > 0 {
                LabeledContent("Unresolved Contents Entries", value: unresolved.formatted())
            }
            if let unreadable = report.unreadableImages, unreadable > 0 {
                LabeledContent("Unreadable Images", value: unreadable.formatted())
            }
        }
    }

    private func availability(_ present: Bool) -> String {
        present ? String(localized: "Present") : String(localized: "Absent")
    }

    private func inspect() async {
        do {
            let current = try await CompatibilityInspection.inspect(candidate.file.url, format: candidate.file.format)
            let prior: CompatibilityReport?
            if let original = candidate.original {
                prior = try await CompatibilityInspection.inspect(original.url, format: original.format)
            } else {
                prior = nil
            }
            snapshot = CompatibilitySnapshot(file: current, original: prior)
        } catch is CancellationError {
            return
        } catch {
            message = error.localizedDescription
        }
    }

    private func ask() {
        guard let snapshot, analysis == nil else { return }
        message = nil
        suggestion = nil
        analysis = Task {
            defer { analysis = nil }
            do {
                let key = try DeepSeekKeychain.read()
                let chinese = Bundle.main.preferredLocalizations.first?.hasPrefix("zh") == true
                let result = try await DeepSeekClient.analyze(snapshot, key: key, inChinese: chinese)
                try Task.checkCancellation()
                suggestion = result
            } catch is CancellationError {
                return
            } catch {
                message = error.localizedDescription
            }
        }
    }
}
