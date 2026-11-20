// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import ImageIO
import UniformTypeIdentifiers

let space = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [
        CGFloat((hex >> 16) & 255) / 255,
        CGFloat((hex >> 8) & 255) / 255,
        CGFloat(hex & 255) / 255,
        alpha,
    ])!
}

func canvas(width: Int, height: Int, scale: Int = 1) -> CGContext {
    let context = CGContext(data: nil, width: width * scale, height: height * scale,
                            bitsPerComponent: 8, bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.translateBy(x: 0, y: CGFloat(height * scale))
    context.scaleBy(x: CGFloat(scale), y: -CGFloat(scale))
    return context
}

func gradient(_ context: CGContext, in path: CGPath, colors: [UInt32], from: CGPoint, to: CGPoint) {
    context.saveGState()
    context.addPath(path)
    context.clip()
    let fill = CGGradient(colorsSpace: space, colors: colors.map { color($0) } as CFArray, locations: nil)!
    context.drawLinearGradient(fill, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    context.restoreGState()
}

func fill(_ context: CGContext, _ path: CGPath, _ hex: UInt32, alpha: CGFloat = 1) {
    context.addPath(path)
    context.setFillColor(color(hex, alpha: alpha))
    context.fillPath()
}

func stroke(_ context: CGContext, _ path: CGPath, _ hex: UInt32, width: CGFloat, alpha: CGFloat = 1) {
    context.addPath(path)
    context.setStrokeColor(color(hex, alpha: alpha))
    context.setLineWidth(width)
    context.setLineJoin(.round)
    context.setLineCap(.round)
    context.strokePath()
}

func rounded(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func write(_ image: CGImage, to url: URL) {
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    precondition(CGImageDestinationFinalize(destination), "Could not write \(url.path)")
}

// The left page and the leaf share a centre fold. Keep the silhouette clear in Finder at 16 pt.
func drawMark(_ context: CGContext) {
    let leftPage = CGMutablePath()
    leftPage.move(to: CGPoint(x: 489, y: 478))
    leftPage.addCurve(to: CGPoint(x: 288, y: 394), control1: CGPoint(x: 423, y: 405), control2: CGPoint(x: 346, y: 392))
    leftPage.addQuadCurve(to: CGPoint(x: 265, y: 418), control: CGPoint(x: 265, y: 394))
    leftPage.addLine(to: CGPoint(x: 265, y: 627))
    leftPage.addQuadCurve(to: CGPoint(x: 289, y: 651), control: CGPoint(x: 265, y: 650))
    leftPage.addCurve(to: CGPoint(x: 489, y: 719), control1: CGPoint(x: 371, y: 654), control2: CGPoint(x: 432, y: 671))
    leftPage.closeSubpath()

    let rightPage = CGMutablePath()
    rightPage.move(to: CGPoint(x: 513, y: 686))
    rightPage.addCurve(to: CGPoint(x: 746, y: 573), control1: CGPoint(x: 570, y: 616), control2: CGPoint(x: 642, y: 588))
    rightPage.addLine(to: CGPoint(x: 746, y: 628))
    rightPage.addQuadCurve(to: CGPoint(x: 723, y: 651), control: CGPoint(x: 746, y: 650))
    rightPage.addCurve(to: CGPoint(x: 513, y: 719), control1: CGPoint(x: 636, y: 655), control2: CGPoint(x: 570, y: 675))
    rightPage.closeSubpath()

    let leaf = CGMutablePath()
    leaf.move(to: CGPoint(x: 513, y: 657))
    leaf.addCurve(to: CGPoint(x: 754, y: 300), control1: CGPoint(x: 509, y: 507), control2: CGPoint(x: 575, y: 377))
    leaf.addQuadCurve(to: CGPoint(x: 769, y: 313), control: CGPoint(x: 768, y: 294))
    leaf.addCurve(to: CGPoint(x: 664, y: 566), control1: CGPoint(x: 778, y: 425), control2: CGPoint(x: 737, y: 523))
    leaf.addCurve(to: CGPoint(x: 513, y: 657), control1: CGPoint(x: 613, y: 597), control2: CGPoint(x: 562, y: 604))
    leaf.closeSubpath()

    gradient(context, in: leftPage, colors: [0xFAF6E8, 0xDDD0AD],
             from: CGPoint(x: 300, y: 388), to: CGPoint(x: 487, y: 733))
    gradient(context, in: rightPage, colors: [0xF4ECCD, 0xBEB18D],
             from: CGPoint(x: 562, y: 591), to: CGPoint(x: 750, y: 722))
    gradient(context, in: leaf, colors: [0xD3F5AD, 0x9FDF98, 0x56A87E],
             from: CGPoint(x: 739, y: 308), to: CGPoint(x: 507, y: 665))

    let vein = CGMutablePath()
    vein.move(to: CGPoint(x: 545, y: 608))
    vein.addCurve(to: CGPoint(x: 711, y: 388), control1: CGPoint(x: 602, y: 513), control2: CGPoint(x: 652, y: 483))
    stroke(context, vein, 0x29664E, width: 11, alpha: 0.59)
}

func appIcon() -> CGImage {
    let context = canvas(width: 1024, height: 1024)
    let surface = rounded(CGRect(x: 95, y: 95, width: 834, height: 834), radius: 190)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -19), blur: 32, color: color(0x10241B, alpha: 0.38))
    fill(context, surface, 0x16382C)
    context.restoreGState()
    gradient(context, in: surface, colors: [0x40816A, 0x214D3D, 0x102D25],
             from: CGPoint(x: 235, y: 115), to: CGPoint(x: 796, y: 912))
    stroke(context, surface, 0xEFF9EC, width: 4, alpha: 0.26)
    drawMark(context)
    return context.makeImage()!
}

func centerText(_ value: String, y: CGFloat, size: CGFloat, weight: NSFont.Weight, ink: UInt32) {
    let text = NSAttributedString(string: value, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: NSColor(cgColor: color(ink))!,
    ])
    text.draw(at: CGPoint(x: (620 - text.size().width) / 2, y: y))
}

func installerBackground(scale: Int) -> CGImage {
    let context = canvas(width: 620, height: 380, scale: scale)
    let page = CGPath(rect: CGRect(x: 0, y: 0, width: 620, height: 380), transform: nil)
    gradient(context, in: page, colors: [0xF6F7EC, 0xE9F0E8, 0xDBEBE3],
             from: CGPoint(x: 155, y: 0), to: CGPoint(x: 540, y: 380))
    let tray = rounded(CGRect(x: 66, y: 124, width: 488, height: 143), radius: 26)
    fill(context, tray, 0xFFFFFF, alpha: 0.48)
    stroke(context, tray, 0x597B6D, width: 1, alpha: 0.23)

    let arrow = CGMutablePath()
    arrow.move(to: CGPoint(x: 285, y: 188))
    arrow.addLine(to: CGPoint(x: 335, y: 188))
    arrow.move(to: CGPoint(x: 324, y: 177))
    arrow.addLine(to: CGPoint(x: 335, y: 188))
    arrow.addLine(to: CGPoint(x: 324, y: 199))
    stroke(context, arrow, 0x39755D, width: 3)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
    centerText("Install Leaf", y: 29, size: 34, weight: .semibold, ink: 0x15372B)
    centerText("Drag Leaf into Applications", y: 78, size: 17, weight: .medium, ink: 0x3E6253)
    centerText("Open Leaf from Applications, then eject this disk image.", y: 287,
               size: 13, weight: .medium, ink: 0x345548)
    NSGraphicsContext.restoreGraphicsState()
    return context.makeImage()!
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("Usage: xcrun swift Design/render.swift output-directory\n".utf8))
    exit(EXIT_FAILURE)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
write(appIcon(), to: output.appendingPathComponent("LeafIcon.png"))
write(installerBackground(scale: 1), to: output.appendingPathComponent("Installer.png"))
write(installerBackground(scale: 2), to: output.appendingPathComponent("Installer@2x.png"))
