// SPDX-License-Identifier: GPL-3.0-only

import CoreFoundation
import Foundation

public enum TXTText {
    public static func decode(_ data: Data) -> String? {
        let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        ))
        let hasUTF16BOM = data.starts(with: [0xff, 0xfe]) || data.starts(with: [0xfe, 0xff])
        let encodings: [String.Encoding] = hasUTF16BOM ? [.utf16] : [.utf8, gb18030]
        guard let decoded = encodings.lazy.compactMap({ String(data: data, encoding: $0) }).first,
              !decoded.contains("\0") else { return nil }
        let text = decoded.first == "\u{feff}" ? String(decoded.dropFirst()) : decoded
        return text.contains(where: { !$0.isWhitespace }) ? text : nil
    }
}
