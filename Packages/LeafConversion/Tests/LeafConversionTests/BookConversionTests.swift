// SPDX-License-Identifier: GPL-3.0-only

import CoreGraphics
import Foundation
import Testing
@testable import LeafConversion

struct BookConversionTests {
    @Test func nativePDFRoundTripKeepsChineseTextSelectable() async throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appending(path: "山海.txt")
        let pdf = folder.appending(path: "山海.pdf")
        let output = folder.appending(path: "Restored.txt")
        try Data("山海之间\n\nLeaf can read Chinese text.\n".utf8).write(to: input)
        try await BookConversion.convert(source: input, destination: pdf)
        try await BookConversion.convert(source: pdf, destination: output)
        let restored = try String(contentsOf: output, encoding: .utf8)
        #expect(restored.contains("山海之间"))
        #expect(restored.contains("Leaf can read Chinese text."))
    }

    @Test func batchPublicationLeavesAnExistingFileAndTheSourceIntact() async throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appending(path: "山海.txt")
        let output = folder.appending(path: "山海.epub")
        let original = Data("山海之间".utf8)
        let previous = Data("A previous book".utf8)
        try original.write(to: input)
        try previous.write(to: output)
        do {
            try await BookConversion.convert(source: input, destination: output, replaceExisting: false)
            Issue.record("Batch publication replaced an existing file.")
        } catch {
            #expect(try Data(contentsOf: output) == previous)
        }
        let available = folder.appending(path: "山海 (2).epub")
        try await BookConversion.convert(source: input, destination: available, replaceExisting: false)
        #expect(try Data(contentsOf: available).starts(with: [0x50, 0x4b]))
        #expect(try Data(contentsOf: input) == original)
    }

    @Test func rejectsAProtectedPDFBeforeCallingAnEngine() async throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appending(path: "Protected.pdf")
        let output = folder.appending(path: "Protected.epub")
        var page = CGRect(x: 0, y: 0, width: 300, height: 450)
        let context = try #require(CGContext(input as CFURL, mediaBox: &page, [
            kCGPDFContextOwnerPassword as String: "owner-test",
            kCGPDFContextUserPassword as String: "test-password",
        ] as CFDictionary))
        context.beginPDFPage(nil)
        context.endPDFPage()
        context.closePDF()

        await #expect(throws: BookConversion.Issue.protectedBook) {
            try await BookConversion.convert(source: input, destination: output)
        }
        #expect(!FileManager.default.fileExists(atPath: output.path(percentEncoded: false)))
    }

    @Test(arguments: [BookFormat.mobi, .azw3])
    func writesTheCorrectKindleContainer(target: BookFormat) async throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appending(path: "山海.txt")
        let output = folder.appending(path: "山海.\(target.rawValue)")
        try Data("山海之间\n\nLeaf reads Chinese text.".utf8).write(to: source)
        try await BookConversion.convert(source: source, destination: output)
        let data = try Data(contentsOf: output)
        let record = data[78..<82].reduce(0) { ($0 << 8) | Int($1) }
        #expect(data[60..<68] == Data("BOOKMOBI".utf8))
        #expect(data[record + 16..<record + 20] == Data("MOBI".utf8))
        #expect(data[record + 39] == (target == .azw3 ? 8 : 6))
        #expect(data.range(of: Data("山海之间".utf8)) != nil)
    }

    private func scratch() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "Leaf matrix \(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        return folder
    }
}
