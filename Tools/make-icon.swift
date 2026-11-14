// Renders the Pictr app icons. Usage: swift Tools/make-icon.swift <Assets.xcassets>
// Writes AppIcon (Red & Black, default) plus the alternates AppIcon-Ember,
// AppIcon-Noir and AppIcon-Classic, each with dark and tinted variants, and a
// small IconPreview-<name> image set per style for the picker in Settings.
// Mirrors PictrMark (Pictr/DesignSystem/PictrMark.swift); change both together.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

struct Style {
    var name: String          // asset name
    var groundTop: UInt32
    var groundBottom: UInt32
    var glow: UInt32?         // red glow from the top left
    var backCard: UInt32
    var frame: UInt32
    var photo: UInt32
    var sun: UInt32
    var farHill: UInt32
    var nearHill: UInt32
}

let styles = [
    Style(name: "AppIcon", groundTop: 0x140606, groundBottom: 0x000000, glow: 0xC0392B,
          backCard: 0xC0392B, frame: 0xF0F0F0, photo: 0x0B0B0B, sun: 0xC0392B, farHill: 0x2A2A2A, nearHill: 0x3D3D3D),
    Style(name: "AppIcon-Ember", groundTop: 0xD8452F, groundBottom: 0x7B241C, glow: nil,
          backCard: 0x0B0B0B, frame: 0xF0F0F0, photo: 0x0B0B0B, sun: 0xC0392B, farHill: 0x2A2A2A, nearHill: 0x3D3D3D),
    Style(name: "AppIcon-Noir", groundTop: 0x111111, groundBottom: 0x000000, glow: nil,
          backCard: 0x2E2E2E, frame: 0xFFFFFF, photo: 0x000000, sun: 0xFFFFFF, farHill: 0x3A3A3A, nearHill: 0x5A5A5A),
    Style(name: "AppIcon-Classic", groundTop: 0x2C2C2C, groundBottom: 0x121212, glow: nil,
          backCard: 0x4A4A4A, frame: 0xF0F0F0, photo: 0x1A1A1A, sun: 0xC0392B, farHill: 0x3D3D3D, nearHill: 0x5A5A5A),
]

enum Variant { case light, dark, tinted }

func render(_ style: Style, _ variant: Variant, size: Int = 1024) -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let s = CGFloat(size)
    ctx.scaleBy(x: s / 1024, y: s / 1024)
    ctx.translateBy(x: 0, y: 1024)
    ctx.scaleBy(x: 1, y: -1)

    let mono = variant == .tinted
    // Ground
    let top: UInt32 = mono ? 0x000000 : style.groundTop
    let bottom: UInt32 = mono ? 0x000000 : style.groundBottom
    let gradient = CGGradient(colorsSpace: space, colors: [color(top), color(bottom)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: 1024), options: [])
    if let glow = style.glow, !mono {
        let radial = CGGradient(colorsSpace: space, colors: [color(glow, 0.55), color(glow, 0)] as CFArray,
                                locations: [0, 1])!
        ctx.drawRadialGradient(radial, startCenter: CGPoint(x: 220, y: 120), startRadius: 0,
                               endCenter: CGPoint(x: 220, y: 120), endRadius: 760, options: [])
    }

    let card = CGSize(width: 500, height: 600)
    func cardPath(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
        CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    // Back card
    ctx.saveGState()
    ctx.translateBy(x: 470, y: 535)
    ctx.rotate(by: -14 * .pi / 180)
    ctx.setShadow(offset: CGSize(width: 0, height: 18), blur: 40, color: color(0x000000, 0.55))
    ctx.addPath(cardPath(CGRect(x: -card.width / 2, y: -card.height / 2, width: card.width, height: card.height), 56))
    ctx.setFillColor(mono ? color(0x8A8A8A) : color(style.backCard))
    ctx.fillPath()
    ctx.restoreGState()

    // Front card (instant-photo frame)
    ctx.saveGState()
    ctx.translateBy(x: 545, y: 495)
    ctx.rotate(by: 7 * .pi / 180)
    let frame = CGRect(x: -card.width / 2, y: -card.height / 2, width: card.width, height: card.height)
    ctx.setShadow(offset: CGSize(width: 0, height: 24), blur: 50, color: color(0x000000, 0.6))
    ctx.addPath(cardPath(frame, 56))
    ctx.setFillColor(mono ? color(0xFFFFFF) : color(style.frame))
    ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)

    let inset: CGFloat = 40
    let photo = CGRect(x: frame.minX + inset, y: frame.minY + inset,
                       width: frame.width - inset * 2, height: frame.height - inset - 150)
    ctx.addPath(cardPath(photo, 24))
    ctx.clip()
    ctx.setFillColor(mono ? color(0x3A3A3A) : color(style.photo))
    ctx.fill(photo)

    // Sun
    ctx.setFillColor(mono ? color(0xFFFFFF) : color(style.sun))
    ctx.fillEllipse(in: CGRect(x: photo.maxX - 170, y: photo.minY + 60, width: 112, height: 112))

    // Hills
    let far = CGMutablePath()
    far.move(to: CGPoint(x: photo.minX, y: photo.maxY - 120))
    far.addLine(to: CGPoint(x: photo.minX + 150, y: photo.maxY - 230))
    far.addLine(to: CGPoint(x: photo.minX + 300, y: photo.maxY - 110))
    far.addLine(to: CGPoint(x: photo.maxX, y: photo.maxY - 190))
    far.addLine(to: CGPoint(x: photo.maxX, y: photo.maxY))
    far.addLine(to: CGPoint(x: photo.minX, y: photo.maxY))
    far.closeSubpath()
    ctx.addPath(far)
    ctx.setFillColor(mono ? color(0x6A6A6A) : color(style.farHill))
    ctx.fillPath()

    let near = CGMutablePath()
    near.move(to: CGPoint(x: photo.minX, y: photo.maxY - 40))
    near.addLine(to: CGPoint(x: photo.minX + 230, y: photo.maxY - 150))
    near.addLine(to: CGPoint(x: photo.maxX, y: photo.maxY - 30))
    near.addLine(to: CGPoint(x: photo.maxX, y: photo.maxY))
    near.addLine(to: CGPoint(x: photo.minX, y: photo.maxY))
    near.closeSubpath()
    ctx.addPath(near)
    ctx.setFillColor(mono ? color(0x9A9A9A) : color(style.nearHill))
    ctx.fillPath()
    ctx.restoreGState()

    return ctx.makeImage()!
}

func write(_ image: CGImage, to url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

func writeJSON(_ json: String, to dir: URL) throws {
    try json.write(to: dir.appending(path: "Contents.json"), atomically: true, encoding: .utf8)
}

let catalog = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Pictr/Resources/Assets.xcassets")
let fm = FileManager.default
for style in styles {
    let iconDir = catalog.appending(path: "\(style.name).appiconset")
    try fm.createDirectory(at: iconDir, withIntermediateDirectories: true)
    write(render(style, .light), to: iconDir.appending(path: "\(style.name).png"))
    write(render(style, .dark), to: iconDir.appending(path: "\(style.name)-Dark.png"))
    write(render(style, .tinted), to: iconDir.appending(path: "\(style.name)-Tinted.png"))
    try writeJSON("""
    {
      "images" : [
        { "filename" : "\(style.name).png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" },
        { "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ],
          "filename" : "\(style.name)-Dark.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" },
        { "appearances" : [ { "appearance" : "luminosity", "value" : "tinted" } ],
          "filename" : "\(style.name)-Tinted.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" }
      ],
      "info" : { "author" : "xcode", "version" : 1 }
    }
    """, to: iconDir)

    let previewName = style.name.replacingOccurrences(of: "AppIcon", with: "IconPreview")
    let previewDir = catalog.appending(path: "\(previewName).imageset")
    try fm.createDirectory(at: previewDir, withIntermediateDirectories: true)
    write(render(style, .light, size: 240), to: previewDir.appending(path: "\(previewName).png"))
    try writeJSON("""
    {
      "images" : [ { "filename" : "\(previewName).png", "idiom" : "universal", "scale" : "3x" } ],
      "info" : { "author" : "xcode", "version" : 1 }
    }
    """, to: previewDir)
}
print("wrote \(styles.count) icon styles to \(catalog.path)")
