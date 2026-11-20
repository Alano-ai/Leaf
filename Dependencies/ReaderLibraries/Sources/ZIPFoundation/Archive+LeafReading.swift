// SPDX-License-Identifier: GPL-3.0-only

import Foundation

extension Archive {
    public enum LeafValidationError: Error, Equatable {
        case invalidArchive
        case encrypted
        case tooManyEntries
    }

    /// Opens a single-disk ZIP32 archive after validating all member offsets and headers.
    /// Callers still bound decompression and compare the checksum of each extracted member.
    public static func leafRead(data: Data, maximumCount: Int) throws -> (archive: Archive, entries: [Entry]) {
        let input = ZIP32Directory(data: data)
        let (end, offset) = try input.endRecord()
        let count = Int(end.totalNumberOfEntriesInCentralDirectory)
        guard count <= maximumCount else { throw LeafValidationError.tooManyEntries }
        let entries = try input.readEntries(count: count,
                                            directoryStart: Int(end.offsetToStartOfCentralDirectory),
                                            directoryEnd: offset)
        let archive = try Archive(leafValidatedData: data, directoryEnd: end)
        return (archive, entries)
    }
}

private struct ZIP32Directory {
    typealias ValidationError = Archive.LeafValidationError

    let data: Data

    func endRecord() throws -> (Archive.EndOfCentralDirectoryRecord, Int) {
        let size = Archive.EndOfCentralDirectoryRecord.size
        guard data.count >= size else { throw ValidationError.invalidArchive }
        let last = data.count - size
        let first = max(0, last - Int(UInt16.max))
        for offset in stride(from: last, through: first, by: -1) {
            guard uint32(at: offset) == UInt32(endOfCentralDirectoryStructSignature),
                  Int(uint16(at: offset + 20)) == last - offset else { continue }
            let (record, _): (Archive.EndOfCentralDirectoryRecord, Int) = try read(at: offset, before: data.count)
            guard record.numberOfDisk == 0, record.numberOfDiskStart == 0,
                  record.totalNumberOfEntriesOnDisk == record.totalNumberOfEntriesInCentralDirectory,
                  record.totalNumberOfEntriesInCentralDirectory < UInt16.max,
                  Int(record.offsetToStartOfCentralDirectory) + Int(record.sizeOfCentralDirectory) == offset else {
                continue
            }
            return (record, offset)
        }
        throw ValidationError.invalidArchive
    }

    func readEntries(count: Int, directoryStart: Int, directoryEnd: Int) throws -> [Entry] {
        var entries: [Entry] = []
        var localRanges: [Range<Int>] = []
        var offset = directoryStart
        entries.reserveCapacity(count)
        localRanges.reserveCapacity(count)
        for _ in 0..<count {
            let (central, next): (Entry.CentralDirectoryStructure, Int) = try read(at: offset, before: directoryEnd)
            let (entry, range) = try readEntry(central, before: directoryStart)
            entries.append(entry)
            localRanges.append(range)
            offset = next
        }
        guard offset == directoryEnd else { throw ValidationError.invalidArchive }
        localRanges.sort { $0.lowerBound < $1.lowerBound }
        for (previous, next) in zip(localRanges, localRanges.dropFirst()) {
            guard previous.upperBound <= next.lowerBound else { throw ValidationError.invalidArchive }
        }
        return entries
    }

    private func readEntry(_ central: Entry.CentralDirectoryStructure, before limit: Int) throws -> (Entry, Range<Int>) {
        try checkFlags(central.generalPurposeBitFlag)
        guard !central.isZIP64, central.validFields.isEmpty, central.diskNumberStart == 0,
              [0, 8].contains(central.compressionMethod), !central.fileNameData.isEmpty,
              central.compressionMethod != 0 || central.compressedSize == central.uncompressedSize else {
            throw ValidationError.invalidArchive
        }
        let start = Int(central.relativeOffsetOfLocalHeader)
        let (local, payload): (Entry.LocalFileHeader, Int) = try read(at: start, before: limit)
        try checkFlags(local.generalPurposeBitFlag)
        guard local.versionNeededToExtract < 45, local.validFields.isEmpty,
              local.generalPurposeBitFlag == central.generalPurposeBitFlag,
              local.compressionMethod == central.compressionMethod,
              local.fileNameData == central.fileNameData,
              Int(central.compressedSize) <= limit - payload else { throw ValidationError.invalidArchive }

        var end = payload + Int(central.compressedSize)
        let descriptor: Entry.DefaultDataDescriptor?
        if central.usesDataDescriptor {
            (descriptor, end) = try readDescriptor(for: central, at: end, before: limit)
        } else {
            guard local.crc32 == central.crc32, local.compressedSize == central.compressedSize,
                  local.uncompressedSize == central.uncompressedSize else { throw ValidationError.invalidArchive }
            descriptor = nil
        }
        guard let entry = Entry(centralDirectoryStructure: central, localFileHeader: local,
                                dataDescriptor: descriptor) else { throw ValidationError.invalidArchive }
        return (entry, start..<end)
    }

    private func readDescriptor(for central: Entry.CentralDirectoryStructure, at offset: Int, before limit: Int)
    throws -> (Entry.DefaultDataDescriptor, Int) {
        // Descriptors can have a signature. Match the declared values to distinguish a signature from the CRC.
        guard offset <= limit - 12 else { throw ValidationError.invalidArchive }
        let starts = uint32(at: offset) == UInt32(dataDescriptorStructSignature) ? [offset + 4, offset] : [offset]
        for start in starts where start <= limit - 12 {
            guard uint32(at: start) == central.crc32, uint32(at: start + 4) == central.compressedSize,
                  uint32(at: start + 8) == central.uncompressedSize else { continue }
            return (Entry.DefaultDataDescriptor(data: Data(), crc32: central.crc32,
                                                compressedSize: central.compressedSize,
                                                uncompressedSize: central.uncompressedSize), start + 12)
        }
        throw ValidationError.invalidArchive
    }

    private func checkFlags(_ flags: UInt16) throws {
        let encryption: UInt16 = (1 << 0) | (1 << 6) | (1 << 13)
        let supported: UInt16 = (1 << 1) | (1 << 2) | (1 << 3) | (1 << 11)
        guard flags & encryption == 0 else { throw ValidationError.encrypted }
        guard flags & ~supported == 0 else { throw ValidationError.invalidArchive }
    }

    private func read<Record: DataSerializable>(at offset: Int, before limit: Int) throws -> (Record, Int) {
        guard offset >= 0, offset <= limit - Record.size else { throw ValidationError.invalidArchive }
        var cursor = offset + Record.size
        let record = Record(data: bytes(offset..<cursor)) { count in
            guard count <= limit - cursor else { throw ValidationError.invalidArchive }
            let start = cursor
            cursor += count
            return bytes(start..<cursor)
        }
        guard let record else { throw ValidationError.invalidArchive }
        return (record, cursor)
    }

    private func bytes(_ range: Range<Int>) -> Data {
        data.subdata(in: (data.startIndex + range.lowerBound)..<(data.startIndex + range.upperBound))
    }

    private func uint16(at offset: Int) -> UInt16 {
        UInt16(littleEndian: data.scanValue(start: offset))
    }

    private func uint32(at offset: Int) -> UInt32 {
        UInt32(littleEndian: data.scanValue(start: offset))
    }
}
