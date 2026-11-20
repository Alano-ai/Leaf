// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

struct WorkspaceView: View {
    @State private var workspace = Workspace()

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
                .navigationTitle(workspace.title)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch workspace {
        case .library:
            ContentUnavailableView(
                "Your Library Is Empty",
                systemImage: "books.vertical",
                description: Text("Books you add will appear here.")
            )
        case .reader:
            ContentUnavailableView(
                "No Book Open",
                systemImage: "book",
                description: Text("Books open here when you select them from your library.")
            )
        case .converter:
            ContentUnavailableView(
                "Format Conversion",
                systemImage: "arrow.left.arrow.right",
                description: Text("Conversion will be available in a later release.")
            )
        }
    }
}
