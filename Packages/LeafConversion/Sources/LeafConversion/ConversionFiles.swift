// SPDX-License-Identifier: GPL-3.0-only

import Darwin
import Foundation
import LeafText

enum ConversionFiles {
    static let limit = 64_000_000

    struct Access {
        private let granted: [URL]
        init(_ urls: URL...) { granted = urls.filter { $0.startAccessingSecurityScopedResource() } }
        func end() { for url in granted { url.stopAccessingSecurityScopedResource() } }
    }

    static func workingDirectory(in parent: URL) throws -> URL {
        let path = parent.appending(path: "LeafConversion-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: false)
        return path
    }

    static func read(_ url: URL, output: Bool = false) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw BookConversion.Issue.unreadableBook }
        let tooLarge: TXTToEPUB.ConversionError = output ? .outputTooLarge : .inputTooLarge
        if let size = values.fileSize, size > limit { throw tooLarge }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let data = try file.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw tooLarge }
        return data
    }

    static func decodeText(_ bytes: Data) throws -> String {
        guard let text = TXTText.decode(bytes) else { throw TXTToEPUB.ConversionError.invalidText }
        return text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }

    static func validateDestination(_ destination: URL, source: URL) throws {
        let original = source.resolvingSymlinksInPath().path(percentEncoded: false)
        if original == destination.resolvingSymlinksInPath().path(percentEncoded: false) {
            throw TXTToEPUB.ConversionError.sameFile
        }
        let sourceAttributes = try FileManager.default.attributesOfItem(atPath: original)
        let target: [FileAttributeKey: Any]
        do {
            target = try FileManager.default.attributesOfItem(atPath: destination.path(percentEncoded: false))
        } catch CocoaError.fileReadNoSuchFile {
            return
        } catch CocoaError.fileNoSuchFile {
            return
        }
        guard target[.type] as? FileAttributeType == .typeRegular else {
            throw TXTToEPUB.ConversionError.invalidDestination
        }
        if let device = sourceAttributes[.systemNumber] as? NSNumber,
           let inode = sourceAttributes[.systemFileNumber] as? NSNumber,
           device == target[.systemNumber] as? NSNumber, inode == target[.systemFileNumber] as? NSNumber {
            throw TXTToEPUB.ConversionError.sameFile
        }
    }

    static func publish(_ data: Data, to destination: URL, source: URL, replaceExisting: Bool,
                        checkpoint: () throws -> Void) throws {
        try validateDestination(destination, source: source)
        try checkpoint()
        if replaceExisting {
            try data.write(to: destination, options: .atomic)
        } else {
            // A complete file in the selected folder is published without racing an existing output.
            let temporary = destination.deletingLastPathComponent().appending(path: ".Leaf-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: temporary) }
            try data.write(to: temporary)
            try checkpoint()
            guard renamex_np(temporary.path(percentEncoded: false), destination.path(percentEncoded: false),
                             UInt32(RENAME_EXCL)) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        }
    }
}

extension StringProtocol {
    var escapedBookMarkup: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    var escapedBookAttribute: String {
        escapedBookMarkup.replacingOccurrences(of: "\"", with: "&quot;")
    }
}
