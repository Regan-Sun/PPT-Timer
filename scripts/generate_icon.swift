import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("usage: generate_icon.swift <output.icns>\n", stderr)
    exit(2)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])

func drawIcon(pixels: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { throw CocoaError(.fileWriteUnknown) }

    let scale = CGFloat(pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: scale, height: scale).fill()

    let outer = NSBezierPath(
        roundedRect: NSRect(x: scale * 0.06, y: scale * 0.06, width: scale * 0.88, height: scale * 0.88),
        xRadius: scale * 0.19,
        yRadius: scale * 0.19
    )
    NSColor(calibratedRed: 1.0, green: 0.84, blue: 0.24, alpha: 1).setFill()
    outer.fill()

    let display = NSBezierPath(
        roundedRect: NSRect(x: scale * 0.13, y: scale * 0.25, width: scale * 0.74, height: scale * 0.5),
        xRadius: scale * 0.09,
        yRadius: scale * 0.09
    )
    NSColor(calibratedWhite: 0.11, alpha: 1).setFill()
    display.fill()

    if pixels >= 64 {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: scale * 0.205, weight: .bold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph
        ]
        NSString(string: "20:00").draw(
            in: NSRect(x: scale * 0.13, y: scale * 0.385, width: scale * 0.74, height: scale * 0.25),
            withAttributes: attributes
        )
    } else {
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: scale * 0.31, y: scale * 0.44, width: scale * 0.12, height: scale * 0.12)).fill()
        NSBezierPath(ovalIn: NSRect(x: scale * 0.57, y: scale * 0.44, width: scale * 0.12, height: scale * 0.12)).fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return data
}

func bigEndian(_ value: UInt32) -> Data {
    var value = value.bigEndian
    return Data(bytes: &value, count: MemoryLayout<UInt32>.size)
}

let entries: [(type: String, pixels: Int)] = [
    ("ic10", 1_024),
    ("ic09", 512),
    ("ic08", 256),
    ("ic07", 128),
    ("icp6", 64),
    ("icp5", 32),
    ("icp4", 16)
]

var chunks = Data()
for entry in entries {
    let png = try drawIcon(pixels: entry.pixels)
    chunks.append(entry.type.data(using: .ascii)!)
    chunks.append(bigEndian(UInt32(png.count + 8)))
    chunks.append(png)
}

var icns = Data("icns".utf8)
icns.append(bigEndian(UInt32(chunks.count + 8)))
icns.append(chunks)
try icns.write(to: outputURL, options: .atomic)
