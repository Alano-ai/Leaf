// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import LeafText
import ZIPFoundation

public enum TXTToEPUB {
    public enum ConversionError: LocalizedError, Equatable {
        case unsupportedSource
        case inputTooLarge
        case invalidText
        case invalidXMLCharacter
        case invalidDestination
        case sameFile
        case outputTooLarge

        public var errorDescription: String? {
            switch self {
            case .unsupportedSource: String(localized: "Choose a local TXT file to convert.", bundle: .module)
            case .inputTooLarge: String(localized: "Choose a TXT file no larger than 64 MB.", bundle: .module)
            case .invalidText: String(localized: "The TXT file must contain readable UTF-8, UTF-16, or GB18030 text.", bundle: .module)
            case .invalidXMLCharacter: String(localized: "The TXT file contains a control character that EPUB cannot store.", bundle: .module)
            case .invalidDestination: String(localized: "Choose a regular file ending in .epub as the destination.", bundle: .module)
            case .sameFile: String(localized: "Choose a destination separate from the original TXT file.", bundle: .module)
            case .outputTooLarge: String(localized: "The generated EPUB exceeds Leaf’s 64 MB reading limit.", bundle: .module)
            }
        }
    }

    private static let fileLimit = 64_000_000

    public static func convert(source: URL, destination: URL) throws {
        try convert(source: source, destination: destination,
                    temporaryDirectory: FileManager.default.temporaryDirectory, checkpoint: Task.checkCancellation)
    }

    static func convert(source: URL, destination: URL, temporaryDirectory: URL,
                        checkpoint: () throws -> Void) throws {
        try checkpoint()
        guard source.isFileURL, source.pathExtension.lowercased() == "txt" else {
            throw ConversionError.unsupportedSource
        }
        guard destination.isFileURL, destination.pathExtension.lowercased() == "epub" else {
            throw ConversionError.invalidDestination
        }
        let reading = source.startAccessingSecurityScopedResource()
        let writing = destination.startAccessingSecurityScopedResource()
        defer {
            if writing { destination.stopAccessingSecurityScopedResource() }
            if reading { source.stopAccessingSecurityScopedResource() }
        }
        try validateDestination(destination, source: source)
        let text = try read(source)
        let fileName = source.deletingPathExtension().lastPathComponent
        let title = fileName.isEmpty ? String(localized: "Untitled", bundle: .module) : fileName
        try checkpoint()

        let work = temporaryDirectory.appending(path: "LeafConversion-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: work) }
        let staged = work.appending(path: "Book.epub", directoryHint: .notDirectory)
        let date = Date()
        do {
            let archive = try Archive(url: staged, accessMode: .create, pathEncoding: nil)
            try EPUBPackage.write(text: text, title: title, date: date, archive: archive, checkpoint: checkpoint)
        }
        try checkpoint()
        let output = try Data(contentsOf: staged, options: .mappedIfSafe)
        guard output.count <= fileLimit else { throw ConversionError.outputTooLarge }
        try validateDestination(destination, source: source)
        try checkpoint()
        // Begin publication only after the complete archive is available and cancellation has been checked.
        try output.write(to: destination, options: .atomic)
    }

    private static func read(_ source: URL) throws -> String {
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw ConversionError.unsupportedSource }
        if let count = values.fileSize, count > fileLimit { throw ConversionError.inputTooLarge }
        let handle = try FileHandle(forReadingFrom: source)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: fileLimit + 1) ?? Data()
        guard data.count <= fileLimit else { throw ConversionError.inputTooLarge }
        guard let text = TXTText.decode(data) else { throw ConversionError.invalidText }
        return text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }

    private static func validateDestination(_ destination: URL, source: URL) throws {
        let sourcePath = source.resolvingSymlinksInPath().path(percentEncoded: false)
        let destinationPath = destination.resolvingSymlinksInPath().path(percentEncoded: false)
        if sourcePath == destinationPath {
            throw ConversionError.sameFile
        }
        let original = try FileManager.default.attributesOfItem(atPath: sourcePath)
        let existing: [FileAttributeKey: Any]
        do {
            existing = try FileManager.default.attributesOfItem(atPath: destination.path(percentEncoded: false))
        } catch CocoaError.fileReadNoSuchFile {
            return
        } catch CocoaError.fileNoSuchFile {
            return
        }
        guard existing[.type] as? FileAttributeType == .typeRegular else {
            throw ConversionError.invalidDestination
        }
        if let device = original[.systemNumber] as? NSNumber, let inode = original[.systemFileNumber] as? NSNumber,
           device == existing[.systemNumber] as? NSNumber, inode == existing[.systemFileNumber] as? NSNumber {
            throw ConversionError.sameFile
        }
    }
}
