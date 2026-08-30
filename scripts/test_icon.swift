import AppKit
import CryptoKit
import Foundation
import Vision

guard CommandLine.arguments.count == 3 else {
    fputs("usage: test_icon.swift <source.png> <icon.icns>\n", stderr)
    exit(2)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let iconURL = URL(fileURLWithPath: CommandLine.arguments[2])
let sourceData = try Data(contentsOf: sourceURL)
let expectedSourceSHA256 = "5a3ee6137f8039b2f4a0954027a7c6ff09e89ff0ffa6f93431fe02e0ce96aa26"
let sourceSHA256 = SHA256.hash(data: sourceData).map { String(format: "%02x", $0) }.joined()

guard sourceSHA256 == expectedSourceSHA256 else {
    fputs("icon source differs from the user-approved image\n", stderr)
    exit(1)
}

guard let sourceImage = NSImage(data: sourceData),
      let sourceRepresentation = sourceImage.representations.first,
      sourceRepresentation.pixelsWide == 1_254,
      sourceRepresentation.pixelsHigh == 1_254 else {
    fputs("approved icon source must be the original 1254x1254 PNG\n", stderr)
    exit(1)
}

let iconData = try Data(contentsOf: iconURL)
func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
    data[offset..<(offset + 4)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
}

guard iconData.count >= 8,
      String(data: iconData[0..<4], encoding: .ascii) == "icns",
      Int(readUInt32(iconData, at: 4)) == iconData.count else {
    fputs("invalid icns container\n", stderr)
    exit(1)
}

let roundTripRoot = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("ppt-timer-icon-test-\(UUID().uuidString)", isDirectory: true)
let roundTripIconset = roundTripRoot.appendingPathComponent("PPTTimer.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: roundTripRoot, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: roundTripRoot) }

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "iconset", iconURL.path, "-o", roundTripIconset.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    fputs("iconutil could not unpack generated icns\n", stderr)
    exit(1)
}

let expectedFiles: [String: Int] = [
    "icon_16x16.png": 16,
    "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32,
    "icon_32x32@2x.png": 64,
    "icon_128x128.png": 128,
    "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256,
    "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512,
    "icon_512x512@2x.png": 1_024
]

var extractedBitmaps: [String: NSBitmapImageRep] = [:]
for (fileName, expectedPixels) in expectedFiles {
    let fileURL = roundTripIconset.appendingPathComponent(fileName)
    guard let fileData = try? Data(contentsOf: fileURL),
          let bitmap = NSBitmapImageRep(data: fileData),
          bitmap.pixelsWide == expectedPixels,
          bitmap.pixelsHigh == expectedPixels else {
        fputs("missing or invalid \(fileName)\n", stderr)
        exit(1)
    }
    extractedBitmaps[fileName] = bitmap
}

func resizedBitmap(from image: NSImage, pixels: Int) throws -> NSBitmapImageRep {
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

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw CocoaError(.fileWriteUnknown)
    }
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: pixels, height: pixels).fill()
    image.draw(
        in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
        from: NSRect(origin: .zero, size: image.size),
        operation: .copy,
        fraction: 1,
        respectFlipped: false,
        hints: [.interpolation: NSImageInterpolation.high]
    )
    return bitmap
}

guard let largeBitmap = extractedBitmaps["icon_512x512@2x.png"] else {
    fputs("missing 1024px icon\n", stderr)
    exit(1)
}
let expectedLargeBitmap = try resizedBitmap(from: sourceImage, pixels: 1_024)
var totalDifference = 0.0
var sampleCount = 0
for y in stride(from: 0, to: 1_024, by: 4) {
    for x in stride(from: 0, to: 1_024, by: 4) {
        guard let expected = expectedLargeBitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
              let actual = largeBitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
        totalDifference += abs(expected.redComponent - actual.redComponent)
        totalDifference += abs(expected.greenComponent - actual.greenComponent)
        totalDifference += abs(expected.blueComponent - actual.blueComponent)
        totalDifference += abs(expected.alphaComponent - actual.alphaComponent)
        sampleCount += 4
    }
}
let meanDifference = totalDifference / Double(sampleCount)
guard meanDifference <= 0.02 else {
    fputs("generated icon changes the approved artwork (mean difference: \(meanDifference))\n", stderr)
    exit(1)
}

guard let largeImage = largeBitmap.cgImage else {
    fputs("unable to decode 1024px icon\n", stderr)
    exit(1)
}
let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = true
request.recognitionLanguages = ["en-US"]
request.customWords = ["PPT Timer"]
try VNImageRequestHandler(cgImage: largeImage).perform([request])
let recognizedText = (request.results ?? [])
    .compactMap { $0.topCandidates(1).first?.string }
    .joined(separator: " ")
    .split(whereSeparator: \.isWhitespace)
    .joined(separator: " ")

guard recognizedText.contains("PPT Timer") else {
    fputs("expected OCR text 'PPT Timer'; recognized: \(recognizedText)\n", stderr)
    exit(1)
}

print("Icon validation passed: approved source preserved and all standard macOS sizes verified.")
