// SPDX-License-Identifier: GPL-3.0-only

import PDFKit

actor LibraryCovers {
    private let images = NSCache<NSString, CGImage>()
    private var missing: Set<String> = []

    init() { images.countLimit = 80 }

    func image(at url: URL, for book: LibraryBook) async -> CGImage? {
        if let cached = images.object(forKey: book.id as NSString) { return cached }
        guard !missing.contains(book.id), !Task.isCancelled else { return nil }
        let result: CGImage?
        switch book.format {
        case .txt:
            result = nil
        case .pdf:
            if let document = PDFDocument(url: url), !document.isEncrypted, !document.isLocked,
               let page = document.page(at: 0) {
                let thumbnail = page.thumbnail(of: CGSize(width: 260, height: 360), for: .cropBox)
                result = thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil)
            } else {
                result = nil
            }
        case .epub, .mobi, .azw3:
            if let file = try? ReadingFile(url: url, format: book.format), case .ebook(let publication) = file.content,
               let data = try? await publication.coverData() {
                result = EbookMarkup.rasterImage(data: data, maximumSize: 360)
            } else {
                result = nil
            }
        }
        if let result { images.setObject(result, forKey: book.id as NSString) }
        else { missing.insert(book.id) }
        return result
    }
}
