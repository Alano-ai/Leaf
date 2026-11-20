// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// Serializes PalmDB INDX records. TAGX defines the values in each entry and IDXT
/// stores the entry offsets. Text referenced by an index lives in a CNCX record.
enum KindleIndex {
    struct Tag {
        let number: UInt8
        let valueCount: UInt8
        let mask: UInt8

        init(_ number: UInt8, _ valueCount: UInt8, _ mask: UInt8) {
            self.number = number
            self.valueCount = valueCount
            self.mask = mask
        }
    }

    static func entry(_ label: String, controls: UInt8, values: [Int]) -> Data {
        var entry = Data([UInt8(label.utf8.count)])
        entry.append(contentsOf: label.utf8)
        entry.append(controls)
        for value in values { entry.appendKindleInteger(value) }
        return entry
    }

    static func records(tags: [Tag], entries: [Data], strings: Data = Data()) -> [Data] {
        var entryRecords: [Data] = []
        var recordCounts: [(Data, Int)] = []
        var record = header()
        var offsets: [UInt16] = []
        for entry in entries {
            if record.count + entry.count + (offsets.count + 1) * 2 + 8 > Int(UInt16.max),
               let last = offsets.last {
                recordCounts.append((lastLabel(in: record, at: last), offsets.count))
                entryRecords.append(finish(record, offsets: offsets))
                record = header()
                offsets.removeAll(keepingCapacity: true)
            }
            offsets.append(UInt16(record.count))
            record.append(entry)
        }
        if let last = offsets.last {
            recordCounts.append((lastLabel(in: record, at: last), offsets.count))
            entryRecords.append(finish(record, offsets: offsets))
        }

        var metadata = header()
        metadata.setBE(UInt32(0), at: 12)
        metadata.setBE(UInt32(2), at: 16)
        metadata.setBE(UInt32(65_001), at: 28)
        metadata.setBE(UInt32(entries.count), at: 36)
        metadata.setBE(UInt32(strings.isEmpty ? 0 : 1), at: 52)
        metadata.setBE(UInt32(metadata.count), at: 180)
        metadata.append(contentsOf: "TAGX".utf8)
        metadata.appendBE(UInt32(12 + 4 * (tags.count + 1)))
        metadata.appendBE(UInt32(1)) // One control byte per entry.
        for tag in tags { metadata.append(contentsOf: [tag.number, tag.valueCount, tag.mask, 0]) }
        metadata.append(contentsOf: [0, 0, 0, 1])
        var groupOffsets: [UInt16] = []
        for (label, count) in recordCounts {
            groupOffsets.append(UInt16(metadata.count))
            metadata.append(label)
            metadata.appendBE(UInt16(count))
        }
        return [finish(metadata, offsets: groupOffsets)] + entryRecords + (strings.isEmpty ? [] : [strings])
    }

    private static func header() -> Data {
        var header = Data(repeating: 0, count: 192)
        header.replaceSubrange(0..<4, with: "INDX".utf8)
        header.setBE(UInt32(header.count), at: 4)
        header.setBE(UInt32(1), at: 12)
        header.setBE(UInt32.max, at: 28)
        header.setBE(UInt32.max, at: 32)
        return header
    }

    private static func lastLabel(in record: Data, at offset: UInt16) -> Data {
        let start = Int(offset)
        return Data(record[start..<(start + 1 + Int(record[start]))])
    }

    private static func finish(_ record: Data, offsets: [UInt16]) -> Data {
        var data = record
        while data.count % 4 != 0 { data.append(0) }
        data.setBE(UInt32(data.count), at: 20)
        data.setBE(UInt32(offsets.count), at: 24)
        data.append(contentsOf: "IDXT".utf8)
        for offset in offsets { data.appendBE(offset) }
        while data.count % 4 != 0 { data.append(0) }
        return data
    }
}

extension Data {
    mutating func appendKindleInteger(_ value: Int) {
        var remaining = value >> 7
        var bytes = [UInt8(value & 0x7f) | 0x80]
        while remaining != 0 {
            bytes.append(UInt8(remaining & 0x7f))
            remaining >>= 7
        }
        append(contentsOf: bytes.reversed())
    }

    mutating func appendBE<T: FixedWidthInteger>(_ value: T) {
        var bytes = value.bigEndian
        Swift.withUnsafeBytes(of: &bytes) { append(contentsOf: $0) }
    }

    mutating func setBE<T: FixedWidthInteger>(_ value: T, at offset: Int) {
        var bytes = value.bigEndian
        Swift.withUnsafeBytes(of: &bytes) { replaceSubrange(offset..<offset + $0.count, with: $0) }
    }
}
