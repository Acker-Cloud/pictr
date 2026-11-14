// Writes JPEGs with EXIF capture dates for simulator testing.
// Usage: swift Tools/make-seed-photos.swift <out-dir>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")
let today = Calendar.current.dateComponents([.month, .day], from: .now)
let years = [1, 1, 2, 3, 3, 3, 5, 8]
let palettes: [(UInt32, UInt32)] = [
    (0xF2A65A, 0x6C3A5C), (0x2E8B57, 0x0B2E1F), (0x87CEEB, 0x1E3A5F), (0xE76F51, 0x264653),
    (0xF4D35E, 0xEE964B), (0x9B5DE5, 0x00BBF9), (0xD62828, 0x003049), (0x8AB17D, 0x2A9D8F),
]
func rgb(_ h: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((h >> 16) & 0xFF) / 255, green: CGFloat((h >> 8) & 0xFF) / 255, blue: CGFloat(h & 0xFF) / 255, alpha: 1)
}
let formatter = DateFormatter()
formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
let thisYear = Calendar.current.component(.year, from: .now)
for (index, ago) in years.enumerated() {
    let w = 1200, h = 1600
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let (a, b) = palettes[index % palettes.count]
    let gradient = CGGradient(colorsSpace: space, colors: [rgb(a), rgb(b)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: w, y: h), options: [])
    ctx.setFillColor(CGColor(gray: 1, alpha: 0.85))
    ctx.fillEllipse(in: CGRect(x: 700, y: 1000, width: 260, height: 260))
    ctx.setFillColor(CGColor(gray: 0, alpha: 0.35))
    ctx.move(to: CGPoint(x: 0, y: 0)); ctx.addLine(to: CGPoint(x: 500, y: 700)); ctx.addLine(to: CGPoint(x: 1200, y: 200)); ctx.addLine(to: CGPoint(x: 1200, y: 0)); ctx.fillPath()
    var parts = DateComponents(year: thisYear - ago, month: today.month, day: today.day, hour: 9 + index, minute: 12)
    if Calendar.current.date(from: parts) == nil { parts.day = 28 }
    let date = Calendar.current.date(from: parts)!
    let stamp = formatter.string(from: date)
    let props: [CFString: Any] = [
        kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: stamp, kCGImagePropertyExifDateTimeDigitized: stamp],
        kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFDateTime: stamp],
    ]
    let url = out.appending(path: "seed-\(index).jpg")
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, props as CFDictionary)
    CGImageDestinationFinalize(dest)
}
// Recent shots for Cleanup analysis: a near-identical set of three and one blurry photo.
func recent(_ name: String, minutesAgo: Double, sunX: CGFloat, blurry: Bool) {
    let w = 1200, h = 1600
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let scale = blurry ? 24 : 1
    let ctx = CGContext(data: nil, width: w / scale, height: h / scale, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: 1 / CGFloat(scale), y: 1 / CGFloat(scale))
    let gradient = CGGradient(colorsSpace: space, colors: [rgb(0x264653), rgb(0xE9C46A)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: h), options: [])
    for i in 0..<40 { // texture so sharpness has edges to find
        ctx.setFillColor(CGColor(gray: i % 2 == 0 ? 0.1 : 0.95, alpha: 1))
        ctx.fill(CGRect(x: 100 + i * 25, y: 300, width: 12, height: 400))
    }
    ctx.setFillColor(CGColor(gray: 1, alpha: 0.9))
    ctx.fillEllipse(in: CGRect(x: sunX, y: 1100, width: 220, height: 220))
    var image = ctx.makeImage()!
    if blurry { // upscale the tiny render: soft edges everywhere
        let big = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        big.interpolationQuality = .high
        big.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        image = big.makeImage()!
    }
    let stamp = formatter.string(from: Date().addingTimeInterval(-minutesAgo * 60))
    let props: [CFString: Any] = [kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: stamp]]
    let dest = CGImageDestinationCreateWithURL(out.appending(path: "\(name).jpg") as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, props as CFDictionary)
    CGImageDestinationFinalize(dest)
}
recent("similar-a", minutesAgo: 62, sunX: 700, blurry: false)
recent("similar-b", minutesAgo: 61.5, sunX: 712, blurry: false)
recent("similar-c", minutesAgo: 61, sunX: 724, blurry: false)
recent("blurry", minutesAgo: 30, sunX: 300, blurry: true)
print("wrote \(years.count + 4) seed photos to \(out.path)")
