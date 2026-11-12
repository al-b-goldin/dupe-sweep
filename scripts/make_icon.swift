import AppKit

// Draws the app icon: two stacked pages (the copy and the original) on a teal tile, with a check badge.
let size: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor { NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a) }

// tile
let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
ctx.saveGState()
let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.30); shadow.shadowOffset = NSSize(width: 0, height: -14); shadow.shadowBlurRadius = 28; shadow.set()
color(20, 110, 124).setFill(); tile.fill()
ctx.restoreGState()
tile.addClip()
NSGradient(colors: [color(46, 170, 184), color(15, 92, 106)])!.draw(in: tile, angle: -65)

func page(_ r: NSRect, alpha: CGFloat, fold: Bool) {
    let p = NSBezierPath()
    let f: CGFloat = fold ? 86 : 0
    p.move(to: NSPoint(x: r.minX + 26, y: r.minY)); p.line(to: NSPoint(x: r.maxX - 26, y: r.minY))
    p.curve(to: NSPoint(x: r.maxX, y: r.minY + 26), controlPoint1: NSPoint(x: r.maxX - 10, y: r.minY), controlPoint2: NSPoint(x: r.maxX, y: r.minY + 10))
    p.line(to: NSPoint(x: r.maxX, y: r.maxY - f - 0)); p.line(to: NSPoint(x: r.maxX - f, y: r.maxY)); p.line(to: NSPoint(x: r.minX + 26, y: r.maxY))
    p.curve(to: NSPoint(x: r.minX, y: r.maxY - 26), controlPoint1: NSPoint(x: r.minX + 10, y: r.maxY), controlPoint2: NSPoint(x: r.minX, y: r.maxY - 10))
    p.line(to: NSPoint(x: r.minX, y: r.minY + 26))
    p.curve(to: NSPoint(x: r.minX + 26, y: r.minY), controlPoint1: NSPoint(x: r.minX, y: r.minY + 10), controlPoint2: NSPoint(x: r.minX + 10, y: r.minY))
    p.close()
    ctx.saveGState()
    let s = NSShadow(); s.shadowColor = NSColor.black.withAlphaComponent(0.25); s.shadowOffset = NSSize(width: 0, height: -8); s.shadowBlurRadius = 16; s.set()
    NSColor.white.withAlphaComponent(alpha).setFill(); p.fill()
    ctx.restoreGState()
    if fold {
        let t = NSBezierPath(); t.move(to: NSPoint(x: r.maxX - f, y: r.maxY)); t.line(to: NSPoint(x: r.maxX - f, y: r.maxY - f)); t.line(to: NSPoint(x: r.maxX, y: r.maxY - f)); t.close()
        color(200, 226, 230).setFill(); t.fill()
    }
}
page(NSRect(x: 330, y: 300, width: 400, height: 470), alpha: 0.55, fold: false)       // the extra copy, behind
page(NSRect(x: 250, y: 232, width: 400, height: 470), alpha: 1.0, fold: true)          // the original, in front
// text lines on the front page
color(150, 190, 198).setFill()
for (i, w) in [260.0, 300.0, 220.0, 280.0].enumerated() { NSBezierPath(roundedRect: NSRect(x: 296, y: 590 - CGFloat(i) * 64, width: CGFloat(w), height: 26), xRadius: 13, yRadius: 13).fill() }
// check badge
let badge = NSRect(x: 560, y: 190, width: 200, height: 200)
ctx.saveGState()
let bs = NSShadow(); bs.shadowColor = NSColor.black.withAlphaComponent(0.3); bs.shadowOffset = NSSize(width: 0, height: -8); bs.shadowBlurRadius = 14; bs.set()
color(40, 168, 92).setFill(); NSBezierPath(ovalIn: badge).fill()
ctx.restoreGState()
let ck = NSBezierPath(); ck.lineWidth = 34; ck.lineCapStyle = .round; ck.lineJoinStyle = .round
ck.move(to: NSPoint(x: badge.minX + 52, y: badge.midY - 2)); ck.line(to: NSPoint(x: badge.minX + 88, y: badge.midY - 38)); ck.line(to: NSPoint(x: badge.minX + 152, y: badge.midY + 36))
NSColor.white.setStroke(); ck.stroke()

NSGraphicsContext.restoreGraphicsState()
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
