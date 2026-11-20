// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

@main
struct LeafApp: App {
    var body: some Scene {
        Window("Leaf", id: "main") {
            WorkspaceView()
                .frame(minWidth: 620, minHeight: 400)
        }
        .defaultSize(width: 960, height: 640)
        .windowResizability(.contentMinSize)
    }
}
