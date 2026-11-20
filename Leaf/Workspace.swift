// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

enum Workspace: CaseIterable, Hashable {
    case library
    case reader
    case converter

    init(selection: Self? = nil) {
        self = selection ?? .library
    }

    var title: LocalizedStringKey {
        switch self {
        case .library: "Library"
        case .reader: "Reader"
        case .converter: "Converter"
        }
    }

    var symbol: String {
        switch self {
        case .library: "books.vertical"
        case .reader: "book"
        case .converter: "arrow.left.arrow.right"
        }
    }
}
