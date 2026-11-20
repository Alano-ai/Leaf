// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

struct WorkspaceView: View {
    @State private var workspace = Workspace()
    @State private var library = LibraryModel()
    @State private var conversion = ConversionJob()
    @State private var importing = false

    private var sidebarSelection: Binding<Workspace?> {
        Binding(get: { workspace }, set: { workspace = Workspace(selection: $0) })
    }

    var body: some View {
        NavigationSplitView {
            List(selection: sidebarSelection) {
                Section("Library") {
                    destination(.library)
                    destination(.recent)
                    destination(.favorites)
                }
                destination(.reader)
                destination(.converter)
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
            if workspace.isLibrary {
                Button("Import Books", systemImage: "plus") { importing = true }
                    .keyboardShortcut("o")
                    .disabled(!library.ready || library.busy)
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: BookFormat.importTypes,
                      allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): importBooks(urls)
            case .failure(let error): library.message = error.localizedDescription
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

    private func destination(_ value: Workspace) -> some View {
        Label(value.title, systemImage: value.symbol).tag(value)
    }

    private var title: Text {
        if workspace == .reader, let book = library.session?.book {
            return Text(verbatim: library.books.first(where: { $0.id == book.id })?.title ?? book.title)
        }
        return Text(workspace.title)
    }

    @ViewBuilder
    private var detail: some View {
        switch workspace {
        case .library, .recent, .favorites:
            LibraryShelf(library: library, workspace: workspace) { book in
                Task {
                    if await library.open(book), workspace.isLibrary { workspace = .reader }
                }
            } onImport: {
                importing = true
            } onConvert: { book in
                guard !conversion.isBusy else { return }
                conversion.addBook(at: library.fileURL(for: book), title: book.title, format: book.format)
                workspace = .converter
            }
            .dropDestination(for: URL.self) { urls, _ in importBooks(urls) }
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

    @discardableResult
    private func importBooks(_ urls: [URL]) -> Bool {
        guard library.ready, !library.busy, !urls.isEmpty else { return false }
        Task {
            if urls.count == 1, let url = urls.first {
                if await library.importBook(at: url), workspace.isLibrary { workspace = .reader }
            } else {
                for url in urls { _ = await library.importBook(at: url) }
            }
        }
        return true
    }
}
