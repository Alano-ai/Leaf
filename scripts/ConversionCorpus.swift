// SPDX-License-Identifier: GPL-3.0-only

import CryptoKit
import Foundation
import LeafConversion
@testable import Leaf

@main
struct ConversionCorpus {
    struct Trial: Encodable {
        enum Outcome: String, Encodable { case converted, unsupportedInput, noText, failed }

        var sample: String
        var sha256: String
        var input: CompatibilityReport
        var target: LeafConversion.BookFormat
        var output: CompatibilityReport?
        var outcome: Outcome
        var detail: String?
    }

    static func main() async throws {
        let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let report = URL(fileURLWithPath: CommandLine.arguments[2])
        let work = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
        let documentFiles = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey],
                                                                       options: [.skipsHiddenFiles])
        var trials: [Trial] = []
        for source in documentFiles.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let format = LeafConversion.BookFormat(file: source),
                  try source.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            let input = try await CompatibilityInspection.inspect(source, format: format)
            let originalHash = try checksum(source)
            for target in LeafConversion.BookFormat.allCases where target != format {
                let output = work.appending(path: "result.\(target.rawValue)")
                defer { try? FileManager.default.removeItem(at: output) }
                var trial = Trial(sample: source.lastPathComponent, sha256: originalHash, input: input,
                                  target: target, outcome: .failed)
                do {
                    try await BookConversion.convert(source: source, destination: output, decodeEbook: ConversionSource.decode)
                    let inspected = try await CompatibilityInspection.inspect(output, format: target)
                    trial.output = inspected
                    if inspected.status != .readable || (inspected.unreadableSections ?? 0) > 0 {
                        trial.detail = "Converted output could not be reopened completely"
                    } else if input.hasSelectableText == true && inspected.hasSelectableText != true {
                        trial.detail = "Selectable text was lost"
                    } else if (inspected.unreadableImages ?? 0) > 0 {
                        trial.detail = "Converted images could not be decoded"
                    } else if let originalImages = input.rasterImages, let resultImages = inspected.rasterImages,
                              originalImages - (input.unreadableImages ?? 0) > resultImages {
                        trial.detail = "Readable raster resource count decreased"
                    } else if input.hasReadableCover == true && inspected.hasReadableCover == false {
                        trial.detail = "Readable cover was lost"
                    } else {
                        trial.outcome = .converted
                    }
                } catch {
                    switch error {
                    case EbookError.unsupportedLayout, EbookError.protectedBook, EbookError.limitExceeded,
                         TXTToEPUB.ConversionError.inputTooLarge:
                        trial.outcome = .unsupportedInput
                    case BookConversion.Issue.pdfWithoutText:
                        trial.outcome = .noText
                    case BookConversion.Issue.unreadableBook
                        where input.status == .readable && input.hasSelectableText == false &&
                              (target == .pdf || target == .txt || (input.rasterImages ?? 0) == 0):
                        trial.outcome = .noText
                    default:
                        break
                    }
                    trial.detail = error.localizedDescription
                }
                if try checksum(source) != originalHash {
                    trial.outcome = .failed
                    trial.detail = "Source was modified"
                }
                trials.append(trial)
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(trials).write(to: report, options: .atomic)
        let outcomes = Dictionary(grouping: trials, by: \.outcome).mapValues(\.count)
        let routes = Set(trials.map { "\($0.input.format.rawValue) → \($0.target.rawValue)" })
        print("\(Set(trials.map(\.sample)).count) samples · \(routes.count) routes · \(trials.count) attempts")
        print("\(outcomes[.converted, default: 0]) reopened, \(outcomes[.unsupportedInput, default: 0]) unsupported, " +
              "\(outcomes[.noText, default: 0]) without usable text, \(outcomes[.failed, default: 0]) failed")
        if trials.isEmpty || outcomes[.failed, default: 0] != 0 { exit(1) }
    }

    private static func checksum(_ url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = SHA256()
        while let chunk = try file.read(upToCount: 1_024 * 1_024), !chunk.isEmpty {
            hash.update(data: chunk)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
