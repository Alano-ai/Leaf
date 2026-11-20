// SPDX-License-Identifier: GPL-3.0-only

import CoreGraphics
import Foundation

let url = URL(fileURLWithPath: CommandLine.arguments[1])
var bounds = CGRect(x: 0, y: 0, width: 540, height: 720)
let options = [
    kCGPDFContextOwnerPassword as String: "leaf-probe-owner",
    kCGPDFContextUserPassword as String: "leaf-probe",
] as CFDictionary
let document = CGContext(url as CFURL, mediaBox: &bounds, options)!
document.beginPDFPage(nil)
document.fill(CGRect(x: 40, y: 40, width: 20, height: 20))
document.endPDFPage()
document.closePDF()
precondition(CGPDFDocument(url as CFURL)?.isEncrypted == true, "Expected an encrypted PDF fixture")
