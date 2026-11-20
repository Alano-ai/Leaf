// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import Testing
@testable import Leaf

struct PlainTextTests {
    @Test func decodesBOMMarkedUTF16AndGB18030() throws {
        let utf16 = try #require("山海".data(using: .utf16))
        let gb18030 = Data([0xc9, 0xbd, 0xba, 0xa3])
        for bytes in [utf16, gb18030] {
            let document = try PlainText(data: bytes)
            #expect(document.content == "山海")
            #expect(document[0] == "山海")
        }
    }

    @Test func preservesLineBreaksAndLimitsIndividualLayouts() throws {
        let lines = String(repeating: "Leaf · 山海\r\n", count: 100)
        let text = lines + String(repeating: "书", count: 1_800)
        let document = try PlainText(data: Data(text.utf8))
        let blocks = document.blocks.indices.map { document[$0] }
        #expect(blocks.count > 3)
        #expect(blocks.allSatisfy { $0.count <= 800 })
        #expect(blocks.joined() == text)
    }
}
