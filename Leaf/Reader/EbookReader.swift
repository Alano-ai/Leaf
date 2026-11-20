// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

struct EbookReader: View {
    private struct Page: Identifiable {
        let id = UUID()
        let section: EbookSection
        let position: EbookPosition
    }

    let opening: EbookReading
    let resume: EbookPosition
    let style: ReadingStyle
    let onPositionChange: (EbookPosition) -> Void
    let onFailure: (any Error) -> Void

    @State private var page: Page?
    @State private var navigation: Task<Void, Never>?
    @State private var showingContents = false
    @State private var activeBlock: Int?

    init(opening: EbookReading, resume: EbookPosition, style: ReadingStyle,
         onPositionChange: @escaping (EbookPosition) -> Void,
         onFailure: @escaping (any Error) -> Void) {
        self.opening = opening
        self.resume = resume
        self.style = style
        self.onPositionChange = onPositionChange
        self.onFailure = onFailure
        if resume.section == opening.position.section {
            let position = EbookPosition(section: resume.section, block: opening.section.clamp(resume.block))
            _page = State(initialValue: Page(section: opening.section, position: position))
        }
    }

    private var publication: any EbookPublication { opening.publication }

    var body: some View {
        Group {
            if let page {
                if page.section.blocks.isEmpty {
                    ContentUnavailableView("Empty Section", systemImage: "doc.text")
                } else {
                    readingContent(page)
                    .id(page.id)
                    .environment(\.openURL, OpenURLAction { url in
                        guard let target = EbookTarget(readerURL: url),
                              let index = publication.sectionPaths.firstIndex(of: target.path) else {
                            return .discarded
                        }
                        show(section: index, fragment: target.fragment)
                        return .handled
                    })
                }
            } else if navigation == nil {
                ContentUnavailableView("Section Unavailable", systemImage: "doc.text")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(style.appearance.background)
        .overlay {
            if navigation != nil { ProgressView().padding().background(.background, in: RoundedRectangle(cornerRadius: 8)) }
        }
        .toolbar {
            if !publication.contents.isEmpty {
                Button("Contents", systemImage: "list.bullet") { showingContents.toggle() }
                    .popover(isPresented: $showingContents) {
                        List {
                            ForEach(Array(publication.contents.enumerated()), id: \.offset) { _, entry in
                                Button(entry.label) {
                                    showingContents = false
                                    if let index = publication.sectionPaths.firstIndex(of: entry.target.path) {
                                        show(section: index, fragment: entry.target.fragment)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .frame(width: 300, height: 360)
                    }
            }
            ControlGroup {
                Button("Previous Section", systemImage: "chevron.left") {
                    if let page { show(section: page.position.section - 1) }
                }
                .disabled(page?.position.section == nil || page?.position.section == 0)
                Button("Next Section", systemImage: "chevron.right") {
                    if let page { show(section: page.position.section + 1) }
                }
                .disabled(page?.position.section == nil || page?.position.section == publication.sectionPaths.count - 1)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let page {
                let block = activeBlock ?? page.position.block
                let progress = (Double(page.position.section) + Double(block) / Double(max(1, page.section.blocks.count)))
                    / Double(publication.sectionPaths.count)
                HStack {
                    Text("Section \(page.position.section + 1) of \(publication.sectionPaths.count)")
                    Spacer()
                    Text(progress, format: .percent.precision(.fractionLength(0)))
                        .accessibilityLabel("Reading Position")
                }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(style.appearance.foreground.opacity(0.7))
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity, minHeight: 24)
                    .background(style.appearance.background)
            }
        }
        .task {
            if page == nil { show(section: resume.section, block: resume.block) }
        }
        .onDisappear {
            navigation?.cancel()
            navigation = nil
        }
    }

    @ViewBuilder private func readingContent(_ page: Page) -> some View {
        let start = activeBlock ?? page.position.block
        let changed: (Int) -> Void = { block in
            guard self.page?.id == page.id else { return }
            activeBlock = block
            onPositionChange(EbookPosition(section: page.position.section, block: block))
        }
        if style.layout == .scrolling {
            EbookSectionView(section: page.section, publication: publication, start: start, style: style, onChange: changed)
        } else {
            ReflowPager(count: page.section.blocks.count, start: start, block: { page.section.blocks[$0] },
                        publication: publication, style: style, onPositionChange: changed)
        }
    }

    private func show(section index: Int, block: Int = 0, fragment: String? = nil) {
        guard publication.sectionPaths.indices.contains(index) else { return }
        navigation?.cancel()
        if let page, page.position.section == index {
            navigation = nil
            display(page.section, index: index, block: block, fragment: fragment)
            return
        }
        navigation = Task {
            defer { if !Task.isCancelled { navigation = nil } }
            do {
                let section = try await publication.section(at: index)
                try Task.checkCancellation()
                display(section, index: index, block: block, fragment: fragment)
            } catch {
                if !Task.isCancelled { onFailure(error) }
            }
        }
    }

    private func display(_ section: EbookSection, index: Int, block: Int, fragment: String?) {
        let target = fragment.flatMap { section.anchors[$0] } ?? block
        let position = EbookPosition(section: index, block: section.clamp(target))
        activeBlock = position.block
        page = Page(section: section, position: position)
        onPositionChange(position)
    }
}

private struct EbookSectionView: View {
    let section: EbookSection
    let publication: any EbookPublication
    let style: ReadingStyle
    let onChange: (Int) -> Void
    @State private var visibleBlock: Int?
    @State private var phase = ScrollPhase.idle

    init(section: EbookSection, publication: any EbookPublication, start: Int, style: ReadingStyle,
         onChange: @escaping (Int) -> Void) {
        self.section = section
        self.publication = publication
        self.onChange = onChange
        self.style = style
        _visibleBlock = State(initialValue: start)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(section.blocks.indices, id: \.self) { index in
                    switch section.blocks[index] {
                    case .text(let text, let heading):
                        Text(text)
                            .font(style.textFont(heading: heading))
                            .accessibilityAddTraits(heading ? .isHeader : [])
                            .frame(maxWidth: .infinity, alignment: .leading)
                    case .image(let path, let alternative):
                        EbookImage(publication: publication, path: path, alternative: alternative)
                    }
                }
            }
            .scrollTargetLayout()
            .foregroundStyle(style.appearance.foreground)
            .lineSpacing(style.spacing)
            .textSelection(.enabled)
            .padding(style.margin)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .scrollPosition(id: $visibleBlock, anchor: .top)
        .onChange(of: visibleBlock) {
            if phase == .idle { save() }
        }
        .onScrollPhaseChange { _, current in
            phase = current
            if current == .idle { save() }
        }
        .onDisappear(perform: save)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in save() }
    }

    private func save() {
        if let visibleBlock { onChange(visibleBlock) }
    }
}

struct EbookImage: View {
    let publication: any EbookPublication
    let path: String
    let alternative: String
    var maximumHeight: CGFloat = 520
    @State private var image: CGImage?
    @State private var loaded = false

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: maximumHeight)
                    .accessibilityHidden(alternative.isEmpty)
                    .accessibilityLabel(alternative)
            } else if !alternative.isEmpty {
                Text(verbatim: alternative)
            }
        }
        .task(id: path) {
            guard !loaded else { return }
            let publication = publication
            let path = path
            image = await Task.detached(priority: .userInitiated) {
                guard let data = try? await publication.imageData(at: path) else { return nil as CGImage? }
                return EbookMarkup.rasterImage(data: data)
            }.value
            loaded = true
        }
    }
}
