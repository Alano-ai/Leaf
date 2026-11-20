// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import UniformTypeIdentifiers

struct WorkspaceView: View {
    @State private var workspace = Workspace()
    @State private var library = LibraryModel()
    @State private var conversion = ConversionJob()
    @State private var importing = false

    private static let bookTypes = [UTType.pdf, .plainText, .epub]
        + ["mobi", "azw3"].compactMap { UTType(filenameExtension: $0, conformingTo: .data) }

    private var sidebarSelection: Binding<Workspace?> {
        Binding(
            get: { workspace },
            set: { workspace = Workspace(selection: $0) }
        )
    }

    var body: some View {
        NavigationSplitView {
            List(Workspace.allCases, id: \.self, selection: sidebarSelection) { destination in
                Label(destination.title, systemImage: destination.symbol)
                    .tag(destination)
            }
            .listStyle(.sidebar)
            .accessibilityLabel("Workspaces")
            .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 280)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(title)
        }
        .toolbar {
            if workspace == .library {
                Button("Import Books", systemImage: "plus") { importing = true }
                    .keyboardShortcut("o")
                    .disabled(!library.ready || library.busy)
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: Self.bookTypes) { result in
            switch result {
            case .success(let url):
                Task {
                    if await library.importBook(at: url) { workspace = .reader }
                }
            case .failure(let error):
                library.message = error.localizedDescription
            }
        }
        .alert("Leaf", isPresented: Binding(
            get: { library.message != nil },
            set: { if !$0 { library.message = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(library.message ?? "")
        }
        .task {
            if await library.restore() { workspace = .reader }
        }
    }

    private var title: Text {
        if workspace == .reader, let book = library.session?.book {
            return Text(verbatim: book.title)
        }
        return Text(workspace.title)
    }

    @ViewBuilder
    private var detail: some View {
        switch workspace {
        case .library:
            libraryView
        case .reader:
            if let session = library.session {
                ReaderView(session: session, library: library)
                    .id(session.book.id)
            } else {
                ContentUnavailableView {
                    Label("No Book Open", systemImage: "book")
                } description: {
                    Text("Select a book from your library.")
                } actions: {
                    Button("Show Library") { workspace = .library }
                }
            }
        case .converter:
            ConverterView(job: conversion)
        }
    }

    @ViewBuilder
    private var libraryView: some View {
        if library.busy {
            ProgressView("Opening Book…")
        } else if !library.ready {
            ContentUnavailableView("Library Unavailable", systemImage: "books.vertical")
        } else if library.books.isEmpty {
            ContentUnavailableView {
                Label("Your Library Is Empty", systemImage: "books.vertical")
            } description: {
                Text("Import an EPUB, MOBI, AZW3, PDF, or TXT file to start reading.")
            } actions: {
                Button("Import Book…") { importing = true }
            }
        } else {
            List(library.books) { book in
                Button {
                    Task {
                        if await library.open(book) { workspace = .reader }
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: book.format == .txt ? "doc.text" : "book.closed")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text(verbatim: book.title)
                            .lineLimit(1)
                        Spacer()
                        Text(book.format.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.inset)
        }
    }
}
