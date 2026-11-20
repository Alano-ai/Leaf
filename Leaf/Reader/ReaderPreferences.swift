// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI

enum ReadingAppearance: String, CaseIterable, Identifiable {
    case system, white, paper, dark
    var id: Self { self }
    var title: LocalizedStringKey {
        switch self {
        case .system: "System"
        case .white: "White"
        case .paper: "Paper"
        case .dark: "Dark"
        }
    }

    var background: Color {
        switch self {
        case .system: Color(nsColor: .textBackgroundColor)
        case .white: .white
        case .paper: Color(red: 0.97, green: 0.93, blue: 0.85)
        case .dark: Color(red: 0.10, green: 0.11, blue: 0.11)
        }
    }

    var foreground: Color {
        switch self {
        case .system: .primary
        case .white: Color(red: 0.12, green: 0.13, blue: 0.14)
        case .paper: Color(red: 0.21, green: 0.17, blue: 0.12)
        case .dark: Color(red: 0.91, green: 0.90, blue: 0.86)
        }
    }
}

enum ReadingTypeface: String, CaseIterable, Identifiable {
    case system, serif, songti, pingfang
    var id: Self { self }
    var title: LocalizedStringKey {
        switch self {
        case .system: "System"
        case .serif: "Serif"
        case .songti: "Songti SC"
        case .pingfang: "PingFang SC"
        }
    }

    func font(size: CGFloat, heading: Bool) -> NSFont {
        let fallback = NSFont.systemFont(ofSize: size, weight: heading ? .semibold : .regular)
        switch self {
        case .system:
            return fallback
        case .serif:
            return fallback.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: size) } ?? fallback
        case .songti:
            return NSFont(name: heading ? "STSongti-SC-Bold" : "STSongti-SC-Regular", size: size) ?? fallback
        case .pingfang:
            return NSFont(name: heading ? "PingFangSC-Semibold" : "PingFangSC-Regular", size: size) ?? fallback
        }
    }
}

enum ReadingLayout: String, CaseIterable, Identifiable {
    case scrolling, single, spread
    var id: Self { self }
    var title: LocalizedStringKey {
        switch self {
        case .scrolling: "Scrolling"
        case .single: "Single Page"
        case .spread: "Two Pages"
        }
    }
}

struct ReadingStyle {
    let appearance: ReadingAppearance
    let typeface: ReadingTypeface
    let layout: ReadingLayout
    let size: Double
    let spacing: Double
    let margin: Double

    func font(heading: Bool = false) -> NSFont {
        typeface.font(size: heading ? size * 1.25 : size, heading: heading)
    }

    func textFont(heading: Bool = false) -> Font {
        let font = font(heading: heading)
        return .custom(font.fontName, fixedSize: font.pointSize)
    }
}

struct ReaderPreferences: View {
    @Binding var appearance: ReadingAppearance
    @Binding var typeface: ReadingTypeface
    @Binding var layout: ReadingLayout
    @Binding var size: Double
    @Binding var spacing: Double
    @Binding var margin: Double
    let fixedLayout: Bool

    var body: some View {
        Form {
            Picker("Background", selection: $appearance) {
                ForEach(ReadingAppearance.allCases) { Text($0.title).tag($0) }
            }
            Picker("Page Layout", selection: $layout) {
                ForEach(ReadingLayout.allCases) { Text($0.title).tag($0) }
            }
            if !fixedLayout {
                Picker("Typeface", selection: $typeface) {
                    ForEach(ReadingTypeface.allCases) { Text($0.title).tag($0) }
                }
                Slider(value: $size, in: 12...32, step: 1) { Text("Text Size") }
                Slider(value: $spacing, in: 0...16, step: 1) { Text("Line Spacing") }
                Slider(value: $margin, in: 16...72, step: 4) { Text("Page Margins") }
            }
        }
        .formStyle(.grouped)
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
    }
}
