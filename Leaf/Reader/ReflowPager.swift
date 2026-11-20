// SPDX-License-Identifier: GPL-3.0-only

import CoreText
import SwiftUI

struct ReflowPager: View {
    private struct Cursor: Comparable, Hashable {
        var block: Int
        var offset = 0

        static func < (left: Self, right: Self) -> Bool {
            left.block == right.block ? left.offset < right.offset : left.block < right.block
        }
    }

    private struct Page {
        let pieces: [EbookSection.Block]
        let next: Cursor
    }

    let count: Int
    let block: (Int) -> EbookSection.Block
    let publication: (any EbookPublication)?
    let style: ReadingStyle
    let onPositionChange: (Int) -> Void
    let onPreviousSection: (() -> Void)?
    let onNextSection: (() -> Void)?
    @State private var cursor: Cursor
    @State private var history: [Cursor] = []

    init(count: Int, start: Int, block: @escaping (Int) -> EbookSection.Block, publication: (any EbookPublication)? = nil,
         style: ReadingStyle, onPositionChange: @escaping (Int) -> Void,
         onPreviousSection: (() -> Void)? = nil, onNextSection: (() -> Void)? = nil) {
        self.count = count
        self.block = block
        self.publication = publication
        self.style = style
        self.onPositionChange = onPositionChange
        self.onPreviousSection = onPreviousSection
        self.onNextSection = onNextSection
        _cursor = State(initialValue: Cursor(block: start))
    }

    var body: some View {
        GeometryReader { proxy in
            let double = style.layout == .spread
            let width = min(proxy.size.width, double ? 1_360 : 820)
            let column = (width - (double ? 19 : 0)) / (double ? 2 : 1)
            let pageHeight = max(1, proxy.size.height)
            let margin = min(style.margin, max(0, (column - 104) / 2), max(0, (pageHeight - 100) / 2))
            let contentSize = CGSize(width: max(1, column - 2 * margin), height: pageHeight - 2 * margin)
            let first = page(from: cursor, size: contentSize)
            let second = double ? page(from: first.next, size: contentSize) : nil
            let next = second?.next ?? first.next
            HStack(spacing: 9) {
                leaf(first, margin: margin, size: contentSize)
                if double {
                    Rectangle()
                        .fill(style.appearance.foreground.opacity(0.09))
                        .frame(width: 1)
                        .padding(.vertical, 20)
                        .accessibilityHidden(true)
                    leaf(second, margin: margin, size: contentSize)
                }
            }
            .frame(maxWidth: width, maxHeight: .infinity)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar { pageButtons(next: next, size: contentSize, double: double) }
            .onChange(of: contentSize) { history.removeAll() }
            .onChange(of: style.layout) { history.removeAll() }
            .onChange(of: style.size) { history.removeAll() }
            .onChange(of: style.spacing) { history.removeAll() }
            .onChange(of: style.typeface) { history.removeAll() }
        }
        .background(style.appearance.background)
        .onChange(of: cursor) { onPositionChange(cursor.block) }
    }

    private func pageButtons(next: Cursor, size: CGSize, double: Bool) -> some View {
        ControlGroup {
            Button("Previous Page", systemImage: "chevron.left") {
                if cursor == Cursor(block: 0) {
                    onPreviousSection?()
                } else if let previous = history.popLast() {
                    cursor = previous
                } else {
                    cursor = previousPage(from: cursor, size: size, double: double)
                }
            }
            .keyboardShortcut(.leftArrow, modifiers: [])
            .disabled(cursor == Cursor(block: 0) && onPreviousSection == nil)
            Button("Next Page", systemImage: "chevron.right") {
                if next.block >= count {
                    onNextSection?()
                } else {
                    history.append(cursor)
                    cursor = next
                }
            }
            .keyboardShortcut(.rightArrow, modifiers: [])
            .disabled(next.block >= count && onNextSection == nil)
        }
    }

    private func leaf(_ page: Page?, margin: CGFloat, size: CGSize) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array((page?.pieces ?? []).enumerated()), id: \.offset) { _, piece in
                switch piece {
                case .text(let text, let heading):
                    Text(text)
                        .font(style.textFont(heading: heading))
                        .lineSpacing(style.spacing)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(heading ? .isHeader : [])
                case .image(let path, let alternative):
                    if let publication {
                        let height = min(420, size.height * 0.7)
                        EbookImage(publication: publication, path: path, alternative: alternative, maximumHeight: height)
                            .frame(width: size.width, height: height)
                    }
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipped()
        .padding(margin)
        .foregroundStyle(style.appearance.foreground)
        .textSelection(.enabled)
        .id(cursor)
    }

    private func previousPage(from start: Cursor, size: CGSize, double: Bool) -> Cursor {
        var earlier = Cursor(block: max(0, start.block - 20))
        var previous = earlier
        while earlier < start {
            previous = earlier
            let next = page(from: earlier, size: size).next
            earlier = double && next < start ? page(from: next, size: size).next : next
        }
        return previous
    }

    private func page(from start: Cursor, size: CGSize) -> Page {
        var end = start
        var remaining = size.height
        var pieces: [EbookSection.Block] = []
        while end.block < count && remaining > 0 {
            switch block(end.block) {
            case .image(let path, let alternative):
                let height = min(420, size.height * 0.7)
                if !pieces.isEmpty && height > remaining { return Page(pieces: pieces, next: end) }
                pieces.append(.image(path: path, alternative: alternative))
                remaining -= height + 10
                end = Cursor(block: end.block + 1)
            case .text(let text, let heading):
                let begin = text.characters.index(text.startIndex, offsetBy: end.offset)
                let plain = String(text.characters[begin...])
                if plain.isEmpty {
                    end = Cursor(block: end.block + 1)
                    continue
                }
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineSpacing = style.spacing
                let attributed = NSAttributedString(string: plain, attributes: [
                    .font: style.font(heading: heading), .paragraphStyle: paragraph,
                ])
                let framesetter = CTFramesetterCreateWithAttributedString(attributed)
                // Allow for SwiftUI's text layout rounding and font fallback at the bottom of a page.
                let allowance = max(3.0, style.size / 4)
                let bounds = CGRect(x: 0, y: 0, width: size.width, height: max(0, remaining - allowance))
                let frame = CTFramesetterCreateFrame(framesetter, CFRange(), CGPath(rect: bounds, transform: nil), nil)
                var length = CTFrameGetVisibleStringRange(frame).length
                while length > 0 && Range(NSRange(location: 0, length: length), in: plain) == nil { length -= 1 }
                if length == 0 && !pieces.isEmpty { return Page(pieces: pieces, next: end) }
                let visible = Range(NSRange(location: 0, length: length), in: plain)
                    .map { plain[$0].count } ?? 0
                let characters = max(1, visible)
                let limit = text.characters.index(begin, offsetBy: characters)
                pieces.append(.text(AttributedString(text[begin..<limit]), heading: heading))
                if limit < text.endIndex {
                    end.offset += characters
                    return Page(pieces: pieces, next: end)
                }
                let measured = CTFramesetterSuggestFrameSizeWithConstraints(
                    framesetter, CFRange(), nil, CGSize(width: size.width, height: CGFloat.greatestFiniteMagnitude), nil
                )
                remaining -= ceil(measured.height) + 10 + allowance
                end = Cursor(block: end.block + 1)
            }
        }
        return Page(pieces: pieces, next: end)
    }
}
