// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import CoreText
import Foundation

enum PDFOutput {
    static func write(_ text: String, title: String, to output: URL) throws {
        // A4 page with a 19 mm text margin and a system-provided Chinese font fallback.
        var page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let paper = page.insetBy(dx: 54, dy: 54)
        let properties = [kCGPDFContextTitle as String: title] as CFDictionary
        guard let context = CGContext(output as CFURL, mediaBox: &page, properties) else {
            throw BookConversion.Issue.unreadableBook
        }
        defer { context.closePDF() }
        let font = CTFontCreateWithName("PingFangSC-Regular" as CFString, 12, nil)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        let body = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            .paragraphStyle: paragraph,
        ])
        let framesetter = CTFramesetterCreateWithAttributedString(body)
        let path = CGPath(rect: paper, transform: nil)
        var index = 0
        while index < body.length {
            try Task.checkCancellation()
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: index, length: 0), path, nil)
            let length = CTFrameGetVisibleStringRange(frame).length
            guard length > 0 else { throw BookConversion.Issue.unreadableBook }
            context.beginPDFPage(nil)
            CTFrameDraw(frame, context)
            context.endPDFPage()
            index += length
        }
    }
}
