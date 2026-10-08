import AppKit

enum DemoArtwork {
    static func make() -> NSImage {
        let size = NSSize(width: 512, height: 512)
        return NSImage(size: size, flipped: false) { rect in
            NSGradient(colors: [NSColor(srgbRed: 0.05, green: 0.09, blue: 0.19, alpha: 1),
                                NSColor(srgbRed: 0.32, green: 0.31, blue: 0.51, alpha: 1),
                                NSColor(srgbRed: 0.92, green: 0.60, blue: 0.43, alpha: 1)])?.draw(in: rect, angle: -65)
            let sun = NSBezierPath(ovalIn: NSRect(x: 190, y: 210, width: 132, height: 132))
            NSColor(srgbRed: 1, green: 0.82, blue: 0.64, alpha: 1).setFill(); sun.fill()
            for i in 0..<4 {
                let path = NSBezierPath()
                let y = CGFloat(100 + i * 34)
                path.move(to: NSPoint(x: 0, y: y)); path.curve(to: NSPoint(x: 512, y: y + 15),
                    controlPoint1: NSPoint(x: 190, y: y + 110), controlPoint2: NSPoint(x: 350, y: y - 55))
                path.line(to: NSPoint(x: 512, y: 0)); path.line(to: .zero); path.close()
                NSColor(srgbRed: 0.07 + Double(i) * 0.035, green: 0.12 + Double(i) * 0.035, blue: 0.22 + Double(i) * 0.035, alpha: 1).setFill(); path.fill()
            }
            let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
            ("MIDNIGHT" as NSString).draw(in: NSRect(x: 0, y: 416, width: 512, height: 40), withAttributes: [
                .font: NSFont.systemFont(ofSize: 24, weight: .light), .foregroundColor: NSColor.white.withAlphaComponent(0.9),
                .kern: 8, .paragraphStyle: paragraph])
            ("S O M E W H E R E" as NSString).draw(in: NSRect(x: 0, y: 383, width: 512, height: 24), withAttributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .medium), .foregroundColor: NSColor.white.withAlphaComponent(0.7),
                .paragraphStyle: paragraph])
            return true
        }
    }
}
