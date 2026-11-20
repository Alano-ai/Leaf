// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

struct LibraryShelf: View {
    let library: LibraryModel
    let workspace: Workspace
    let onOpen: (LibraryBook) -> Void
    let onImport: () -> Void
    let onConvert: (LibraryBook) -> Void
    @State private var renaming: LibraryBook?
    @State private var newTitle = ""
    @State private var information: LibraryBook?

    private var books: [LibraryBook] {
        switch workspace {
        case .recent: library.recentBooks
        case .favorites: library.books.filter { $0.favorite == true }
        default: library.books
        }
    }

    var body: some View {
        Group {
            if !library.ready && library.busy {
                ProgressView("Opening Book…")
            } else if !library.ready {
                ContentUnavailableView("Library Unavailable", systemImage: "books.vertical")
            } else if books.isEmpty {
                emptyShelf
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 122, maximum: 170), spacing: 24)],
                              alignment: .leading, spacing: 26) {
                        ForEach(books) { book in
                            Button { onOpen(book) } label: {
                                shelfItem(book)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(verbatim: book.title))
                            .contextMenu { bookActions(book) }
                        }
                    }
                    .padding(26)
                }
                .disabled(library.busy)
            }
        }
        .alert("Rename Book", isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )) {
            TextField("Book Title", text: $newTitle)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                if let renaming { library.rename(renaming, to: newTitle) }
            }
            .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .sheet(item: $information) { book in bookInformation(book) }
    }

    private func bookInformation(_ book: LibraryBook) -> some View {
        let size = try? library.fileURL(for: book).resourceValues(forKeys: [.fileSizeKey]).fileSize
        return VStack(alignment: .leading, spacing: 14) {
            Text("Book Information").font(.headline)
            LabeledContent("Book Title") { Text(verbatim: book.title) }
            LabeledContent("Format") { Text(verbatim: book.format.label) }
            if let size {
                LabeledContent("File Size") {
                    Text(verbatim: ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                }
            }
            Button("Done") { information = nil }
                .keyboardShortcut(.defaultAction)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(20)
        .frame(minWidth: 330)
    }

    @ViewBuilder private var emptyShelf: some View {
        switch workspace {
        case .recent:
            ContentUnavailableView("No Recently Read Books", systemImage: "clock")
        case .favorites:
            ContentUnavailableView("No Favorites", systemImage: "star")
        default:
            ContentUnavailableView {
                Label("Your Library Is Empty", systemImage: "books.vertical")
            } description: {
                Text("Drop EPUB, MOBI, AZW3, PDF, or TXT files here.")
            } actions: {
                Button("Import Books…", action: onImport)
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func shelfItem(_ book: LibraryBook) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            BookCover(book: book, library: library)
            Text(verbatim: book.title)
                .font(.callout.weight(.semibold))
                .lineLimit(2, reservesSpace: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                Text(verbatim: book.format.label)
                Spacer(minLength: 0)
                if book.favorite == true { Image(systemName: "star.fill").accessibilityLabel("Favorite") }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder private func bookActions(_ book: LibraryBook) -> some View {
        if book.favorite == true {
            Button("Remove from Favorites", systemImage: "star.slash") { library.toggleFavorite(book) }
        } else {
            Button("Add to Favorites", systemImage: "star") { library.toggleFavorite(book) }
        }
        Button("Convert Book…", systemImage: "arrow.left.arrow.right") { onConvert(book) }
        Button("Rename…", systemImage: "pencil") {
            newTitle = book.title
            renaming = book
        }
        Button("Get Info", systemImage: "info.circle") { information = book }
    }
}

private struct BookCover: View {
    let book: LibraryBook
    let library: LibraryModel
    @State private var cover: CGImage?

    var body: some View {
        Color.accentColor.opacity(0.08)
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .overlay {
                GeometryReader { proxy in
                    if let cover {
                        Image(decorative: cover, scale: 1)
                            .resizable()
                            .scaledToFit()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                    } else {
                        Image(systemName: "book.closed")
                            .font(.system(size: 31, weight: .light))
                            .foregroundStyle(Color.accentColor.opacity(0.74))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .clipShape(.rect(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.09)) }
            .accessibilityHidden(true)
            .task(id: book.id) { cover = await library.cover(for: book) }
    }
}
