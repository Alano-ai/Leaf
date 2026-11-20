// SPDX-License-Identifier: GPL-3.0-only

import Testing
@testable import Leaf

struct WorkspaceTests {
    @Test func libraryIsTheInitialWorkspace() {
        #expect(Workspace() == .library)
    }

    @Test(arguments: Workspace.allCases)
    func explicitSidebarSelectionUsesTheRequestedWorkspace(selection: Workspace) {
        #expect(Workspace(selection: selection) == selection)
    }

    @Test func clearingSidebarSelectionReturnsToLibrary() {
        #expect(Workspace(selection: nil) == .library)
    }
}
