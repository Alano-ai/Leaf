// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

enum Workspace: CaseIterable, Hashable {
    case library
    case recent
    case favorites
    case reader
    case converter

    init(selection: Self? = nil) {
        self = selection ?? .library
    }

    var title: LocalizedStringKey {
        switch self {
        case .library: "All Books"
        case .recent: "Recently Read"
        case .favorites: "Favorites"
        case .reader: "Reader"
        case .converter: "Converter"
        }
    }

    var symbol: String {
        switch self {
        case .library: "books.vertical"
        case .recent: "clock"
        case .favorites: "star"
        case .reader: "book"
        case .converter: "arrow.left.arrow.right"
        }
    }

    var isLibrary: Bool { self == .library || self == .recent || self == .favorites }
}
