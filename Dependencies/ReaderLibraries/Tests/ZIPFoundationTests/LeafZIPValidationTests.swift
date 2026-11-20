// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import XCTest
import ZIPFoundation

final class LeafZIPValidationTests: XCTestCase {
    func testReadsStoredAndDeflatedEntriesFromASlice() throws {
        let data = try makeArchive()
        let slice = (Data([1, 2, 3]) + data).dropFirst(3)
        let (archive, entries) = try Archive.leafRead(data: slice, maximumCount: 2)

        XCTAssertEqual(entries.map(\.path), ["first.txt", "second.txt"])
        XCTAssertEqual(try extract(entries[0], from: archive), "first")
        XCTAssertEqual(try extract(entries[1], from: archive), "second")
    }

    func testReadsStreamingDataDescriptor() throws {
        // A one-entry archive written to a non-seekable ZIP stream.
        let fixture = "UEsDBBQACAAIAMpydF0AAAAAAAAAAAAAAAAKAAAAcGFydC54aHRtbMtIzcnJV0hJLU4uyiwoyS8CAFBLBwiOvXPZEgAAABAAAABQSwECFAMUAAgACADKcnRdjr1z2RIAAAAQAAAACgAAAAAAAAAAAAAAgAEAAAAAcGFydC54aHRtbFBLBQYAAAAAAQABADgAAABKAAAAAAA="
        let data = try XCTUnwrap(Data(base64Encoded: fixture))
        let (archive, entries) = try Archive.leafRead(data: data, maximumCount: 1)
        XCTAssertEqual(try extract(XCTUnwrap(entries.first), from: archive), "hello descriptor")
    }

    func testRejectsProtectedLocalAndCentralFlags() throws {
        let data = try makeArchive()
        let directoryStart = data.withUnsafeBytes {
            Int(UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: data.count - 6, as: UInt32.self)))
        }

        for flagIndex in [6, directoryStart + 8] {
            var flagged = data
            flagged[flagIndex] |= 1
            assertRejected(flagged, as: .encrypted)
        }
    }

    func testRejectsEntryBudgetAndTruncation() throws {
        let data = try makeArchive()
        assertRejected(data, maximumCount: 1, as: .tooManyEntries)
        assertRejected(data.dropLast(), as: .invalidArchive)
    }

    private func makeArchive() throws -> Data {
        let archive = try Archive(accessMode: .create, pathEncoding: nil)
        for (text, method) in [("first", CompressionMethod.none), ("second", .deflate)] {
            let content = Data(text.utf8)
            try archive.addEntry(with: "\(text).txt", type: .file, uncompressedSize: Int64(content.count),
                                 compressionMethod: method) { offset, length in
                let start = Int(offset)
                return content.subdata(in: start..<(start + length))
            }
        }
        return try XCTUnwrap(archive.data)
    }

    private func extract(_ entry: Entry, from archive: Archive) throws -> String {
        var contents = Data()
        let checksum = try archive.extract(entry) { contents.append($0) }
        XCTAssertEqual(checksum, entry.checksum)
        return String(decoding: contents, as: UTF8.self)
    }

    private func assertRejected(_ data: Data, maximumCount: Int = 10, as expected: Archive.LeafValidationError,
                                file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try Archive.leafRead(data: data, maximumCount: maximumCount),
                             file: file, line: line) { error in
            XCTAssertEqual(error as? Archive.LeafValidationError, expected, file: file, line: line)
        }
    }
}
