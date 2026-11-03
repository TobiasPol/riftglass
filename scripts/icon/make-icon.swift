// Renders the Riftglass app icon (a faceted glass diamond) into an Xcode AppIcon set.
// Run: swift scripts/icon/make-icon.swift src/mac/App/Assets.xcassets/AppIcon.appiconset
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "AppIcon.appiconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func polygon(_ points: [CGPoint], fill: NSColor) {
    let path = NSBezierPath()
    path.move(to: points[0])
    points.dropFirst().forEach { path.line(to: $0) }
    path.close()
    fill.setFill()
    path.fill()
}

func drawIcon(size: CGFloat) {
    // macOS icon grid: 824/1024 body with rounded corners.
    let inset = size * 100 / 1024
    let body = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let shape = NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.width * 0.225)
    NSGradient(colors: [color(0x0B1220), color(0x123047), color(0x0E5A68)])?.draw(in: shape, angle: -60)

    let center = CGPoint(x: body.midX, y: body.midY - body.height * 0.02)
    let width = body.width * 0.30, height = body.height * 0.36, shoulder = body.height * 0.12
    let top = CGPoint(x: center.x, y: center.y + height)
    let bottom = CGPoint(x: center.x, y: center.y - height)
    let left = CGPoint(x: center.x - width, y: center.y + shoulder)
    let right = CGPoint(x: center.x + width, y: center.y + shoulder)
    let innerLeft = CGPoint(x: center.x - width * 0.42, y: center.y + shoulder)
    let innerRight = CGPoint(x: center.x + width * 0.42, y: center.y + shoulder)

    // Glow behind the gem.
    NSGradient(colors: [color(0x5CC8DC, 0.45), color(0x5CC8DC, 0)])?
        .draw(fromCenter: center, radius: 0, toCenter: center, radius: body.width * 0.48, options: [])
    // Crown facets.
    polygon([left, top, innerLeft], fill: color(0x9FE7F2))
    polygon([innerLeft, top, innerRight], fill: color(0xD9F7FB))
    polygon([innerRight, top, right], fill: color(0x7AD3E3))
    // Pavilion facets.
    polygon([left, innerLeft, bottom], fill: color(0x2E8EA3))
    polygon([innerLeft, innerRight, bottom], fill: color(0x48B3C7))
    polygon([innerRight, right, bottom], fill: color(0x1F6E80))
    // Rift: a thin crack across the gem.
    let crack = NSBezierPath()
    crack.move(to: CGPoint(x: center.x - width * 0.55, y: center.y + shoulder * 0.2))
    crack.line(to: CGPoint(x: center.x - width * 0.1, y: center.y - shoulder * 0.4))
    crack.line(to: CGPoint(x: center.x + width * 0.15, y: center.y + shoulder * 0.1))
    crack.line(to: CGPoint(x: center.x + width * 0.6, y: center.y - shoulder * 0.9))
    crack.lineWidth = max(1, size * 0.012)
    crack.lineJoinStyle = .round
    color(0x0B1220, 0.85).setStroke()
    crack.stroke()
}

func png(pixels: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
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
    )
    else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    drawIcon(size: CGFloat(pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)@\(scale)x.png"
        try png(pixels: points * scale)?.write(to: output.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}

let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: output.appendingPathComponent("Contents.json"))
print("Wrote \(images.count) icons to \(output.path)")
