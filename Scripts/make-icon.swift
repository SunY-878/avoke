import AppKit
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
func render(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                              samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                              bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    let background = NSBezierPath(roundedRect: NSRect(x: 65, y: 65, width: 894, height: 894), xRadius: 205, yRadius: 205)
    NSGradient(colors: [NSColor(srgbRed: 0.13, green: 0.18, blue: 0.30, alpha: 1), NSColor(srgbRed: 0.03, green: 0.05, blue: 0.11, alpha: 1)])!.draw(in: background, angle: -60)
    NSColor.white.withAlphaComponent(0.12).setStroke(); background.lineWidth = 2; background.stroke()
    let glow = NSShadow(); glow.shadowColor = NSColor(srgbRed: 0.32, green: 0.59, blue: 1, alpha: 0.7)
    glow.shadowBlurRadius = 65; glow.shadowOffset = .zero
    NSGraphicsContext.saveGraphicsState(); glow.set()
    let ring = NSBezierPath(roundedRect: NSRect(x: 178, y: 356, width: 668, height: 296), xRadius: 148, yRadius: 148)
    NSGradient(colors: [NSColor(srgbRed: 0.5, green: 0.77, blue: 1, alpha: 1), NSColor(srgbRed: 0.37, green: 0.45, blue: 0.89, alpha: 1)])!.draw(in: ring, angle: -20)
    NSGraphicsContext.restoreGraphicsState()
    NSColor(srgbRed: 0.025, green: 0.04, blue: 0.09, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 193, y: 371, width: 638, height: 266), xRadius: 133, yRadius: 133).fill()
    NSColor(srgbRed: 0.64, green: 0.8, blue: 1, alpha: 1).setFill()
    for (index, height) in [42.0, 91.0, 132.0, 72.0].enumerated() {
        NSBezierPath(roundedRect: NSRect(x: 321 + Double(index) * 42, y: 504 - height / 2, width: 15, height: height), xRadius: 7.5, yRadius: 7.5).fill()
    }
    let star = NSBezierPath()
    star.move(to: NSPoint(x: 651, y: 556)); star.curve(to: NSPoint(x: 699, y: 508), controlPoint1: NSPoint(x: 653, y: 520), controlPoint2: NSPoint(x: 663, y: 510))
    star.curve(to: NSPoint(x: 651, y: 460), controlPoint1: NSPoint(x: 663, y: 506), controlPoint2: NSPoint(x: 653, y: 496))
    star.curve(to: NSPoint(x: 603, y: 508), controlPoint1: NSPoint(x: 649, y: 496), controlPoint2: NSPoint(x: 639, y: 506))
    star.curve(to: NSPoint(x: 651, y: 556), controlPoint1: NSPoint(x: 639, y: 510), controlPoint2: NSPoint(x: 649, y: 520)); star.fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        try render(points * scale).write(to: output.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }
}
