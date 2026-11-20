// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import LeafConversion
import Testing
@testable import Leaf

struct CompatibilityTests {
    @Test func reopensTheNativeAZW3AndReportsInvalidKindleFiles() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appending(path: "Source.txt")
        let output = folder.appending(path: "Output.azw3")
        try Data("中英文 and Latin text".utf8).write(to: input)
        try await BookConversion.convert(source: input, destination: output)

        let good = try await CompatibilityInspection.inspect(output, format: .azw3)
        #expect(good.status == .readable)
        #expect(good.kindleHeaderVersion == 8)
        #expect(good.sections == 1)
        #expect(good.hasSelectableText == true)
        #expect(good.unreadableSections == 0)

        try Data("Invalid".utf8).write(to: output)
        let corrupt = try await CompatibilityInspection.inspect(output, format: .azw3)
        #expect(corrupt.status == .invalid)
        #expect(corrupt.kindleHeaderVersion == nil)
    }

    @Test func deepSeekRequestContainsOnlyAnonymousStructureFacts() throws {
        var report = CompatibilityReport(format: .azw3, status: .readable)
        report.kindleHeaderVersion = 8
        report.rasterImages = 4
        let snapshot = CompatibilitySnapshot(file: report, original: nil)
        let request = try DeepSeekClient.makeRequest(snapshot, key: "synthetic-key", inChinese: true)

        #expect(request.url?.absoluteString == "https://api.deepseek.com/chat/completions")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-key")
        let body = try #require(request.httpBody)
        #expect(!String(decoding: body, as: UTF8.self).contains("synthetic-key"))

        let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(payload["model"] as? String == "deepseek-flash")
        let messages = try #require(payload["messages"] as? [[String: String]])
        let facts = try #require(messages.last?["content"])
        let encoded = try #require(JSONSerialization.jsonObject(with: Data(facts.utf8)) as? [String: Any])
        let file = try #require(encoded["file"] as? [String: Any])
        #expect(Set(file.keys) == ["format", "status", "kindleHeaderVersion", "rasterImages"])
        #expect(file["rasterImages"] as? Int == 4)
    }

    @Test func deepSeekResponsesHandleProviderFailures() throws {
        let response = Data(#"{"choices":[{"message":{"content":"建议先检查目录。"}}]}"#.utf8)
        #expect(try DeepSeekClient.parse(response, status: 200) == "建议先检查目录。")
        #expect(throws: DeepSeekClient.Issue.authentication) { try DeepSeekClient.parse(Data(), status: 401) }
        #expect(throws: DeepSeekClient.Issue.balance) { try DeepSeekClient.parse(Data(), status: 402) }
        #expect(throws: DeepSeekClient.Issue.rateLimited) { try DeepSeekClient.parse(Data(), status: 429) }
        #expect(throws: DeepSeekClient.Issue.invalidResponse) { try DeepSeekClient.parse(Data(), status: 200) }
        #expect(throws: DeepSeekKeychain.Issue.invalidKey) { try DeepSeekKeychain.validatedKey("abc\r\nInjected") }
    }
}
