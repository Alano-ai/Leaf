// SPDX-License-Identifier: GPL-3.0-only

import Foundation

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

    public static func convert(source: URL, destination: URL) throws {
        try convert(source: source, destination: destination,
                    temporaryDirectory: FileManager.default.temporaryDirectory, checkpoint: Task.checkCancellation)
    }

    static func convert(source: URL, destination: URL, temporaryDirectory: URL,
                        title: String? = nil, checkpoint: () throws -> Void) throws {
        try checkpoint()
        guard source.isFileURL, source.pathExtension.lowercased() == "txt" else {
            throw ConversionError.unsupportedSource
        }
        guard destination.isFileURL, destination.pathExtension.lowercased() == "epub" else {
            throw ConversionError.invalidDestination
        }
        let access = ConversionFiles.Access(source, destination)
        defer { access.end() }
        try ConversionFiles.validateDestination(destination, source: source)
        let text = try ConversionFiles.decodeText(ConversionFiles.read(source))
        let fileName = title ?? source.deletingPathExtension().lastPathComponent
        let title = fileName.isEmpty ? String(localized: "Untitled", bundle: .module) : fileName
        try checkpoint()

        let work = try ConversionFiles.workingDirectory(in: temporaryDirectory)
        defer { try? FileManager.default.removeItem(at: work) }
        let staged = work.appending(path: "Book.epub", directoryHint: .notDirectory)
        let book = ConversionBook(title: title, chapters: [.init(text: text)])
        try EPUBPackage.write(book, to: staged, checkpoint: checkpoint)
        try checkpoint()
        let result = try ConversionFiles.read(staged, output: true)
        try ConversionFiles.publish(result, to: destination, source: source, replaceExisting: true, checkpoint: checkpoint)
    }
}
