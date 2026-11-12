// Renders docs/assets/banner.png (2x) with SF Pro, so the wordmark looks identical everywhere.
// Run from the repo root: swiftc -O docs/assets/make-banner.swift -o /tmp/make-banner && /tmp/make-banner
import AppKit

let W: CGFloat = 1280, H: CGFloat = 420, S: CGFloat = 2
let accent = NSColor(srgbRed: 0.16, green: 0.58, blue: 1.0, alpha: 1)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * S), pixelsHigh: Int(H * S), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: W, height: H)
let gc = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = gc
let ctx = gc.cgContext
ctx.translateBy(x: 0, y: H); ctx.scaleBy(x: 1, y: -1) // y-down, like the app
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)

// Background: navy glow + 16pt grid.
let bg = NSGradient(colors: [NSColor(srgbRed: 0.07, green: 0.19, blue: 0.31, alpha: 1), NSColor(srgbRed: 0.03, green: 0.07, blue: 0.11, alpha: 1)])!
bg.draw(fromCenter: CGPoint(x: W / 2, y: H * 0.45), radius: 0, toCenter: CGPoint(x: W / 2, y: H * 0.45), radius: W * 0.6, options: [])
accent.withAlphaComponent(0.07).setFill()
for x in stride(from: CGFloat(0), to: W, by: 16) { CGRect(x: x, y: 0, width: 0.5, height: H).fill() }
for y in stride(from: CGFloat(0), to: H, by: 16) { CGRect(x: 0, y: y, width: W, height: 0.5).fill() }

// Wordmark.
let mark = NSMutableAttributedString(string: "desarray", attributes: [
    .font: NSFont.systemFont(ofSize: 112, weight: .bold), .foregroundColor: NSColor(white: 0.97, alpha: 1), .kern: -3.5,
])
mark.append(NSAttributedString(string: ".", attributes: [.font: NSFont.systemFont(ofSize: 112, weight: .bold), .foregroundColor: accent]))
let ms = mark.size()
let textBox = CGRect(x: (W - ms.width) / 2, y: 122, width: ms.width, height: ms.height)

// X-ray frame around it, in the app's own visual language.
let inner = textBox.insetBy(dx: -28, dy: -8)
let frame = inner.insetBy(dx: -40, dy: -28)
accent.withAlphaComponent(0.08).setFill(); frame.fill()
NSGraphicsContext.saveGraphicsState()
NSBezierPath(rect: frame).addClip()
accent.withAlphaComponent(0.16).setStroke()
var hx = frame.minX - frame.height
while hx < frame.maxX {
    let p = NSBezierPath(); p.move(to: CGPoint(x: hx, y: frame.maxY)); p.line(to: CGPoint(x: hx + frame.height, y: frame.minY))
    p.lineWidth = 1; p.stroke(); hx += 7
}
NSGraphicsContext.restoreGraphicsState()
NSColor.black.withAlphaComponent(0.22).setFill(); inner.fill()
accent.withAlphaComponent(0.55).setStroke(); NSBezierPath(rect: inner).stroke()
accent.setStroke(); let fp = NSBezierPath(rect: frame); fp.lineWidth = 1.5; fp.stroke()
for c in [CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: frame.maxX, y: frame.minY), CGPoint(x: frame.minX, y: frame.maxY), CGPoint(x: frame.maxX, y: frame.maxY)] {
    let h = NSBezierPath(rect: CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8))
    NSColor.white.setFill(); h.fill(); accent.setStroke(); h.lineWidth = 1.5; h.stroke()
}
mark.draw(at: textBox.origin)

func tick(_ a: CGPoint, _ b: CGPoint, vertical: Bool) {
    let p = NSBezierPath(); p.lineWidth = 1.5
    p.move(to: a); p.line(to: b)
    for q in [a, b] {
        if vertical { p.move(to: CGPoint(x: q.x - 4, y: q.y)); p.line(to: CGPoint(x: q.x + 4, y: q.y)) }
        else { p.move(to: CGPoint(x: q.x, y: q.y - 4)); p.line(to: CGPoint(x: q.x, y: q.y + 4)) }
    }
    accent.setStroke(); p.stroke()
}
func pill(_ s: String, center c: CGPoint, filled: Bool) {
    let t = NSAttributedString(string: s, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .bold),
                                                       .foregroundColor: filled ? NSColor.white : accent])
    let ts = t.size()
    let box = CGRect(x: c.x - ts.width / 2 - 6, y: c.y - ts.height / 2 - 2, width: ts.width + 12, height: ts.height + 4)
    (filled ? accent : NSColor(srgbRed: 0.02, green: 0.04, blue: 0.07, alpha: 0.95)).setFill()
    NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
    t.draw(at: CGPoint(x: box.minX + 6, y: box.minY + 2))
}
tick(CGPoint(x: frame.minX, y: frame.midY), CGPoint(x: inner.minX, y: frame.midY), vertical: false)
pill("\(Int(inner.minX - frame.minX))", center: CGPoint(x: (frame.minX + inner.minX) / 2, y: frame.midY), filled: false)
tick(CGPoint(x: frame.midX, y: frame.minY), CGPoint(x: frame.midX, y: inner.minY), vertical: true)
pill("\(Int(inner.minY - frame.minY))", center: CGPoint(x: frame.midX, y: (frame.minY + inner.minY) / 2), filled: false)
pill("\(Int(frame.width)) × \(Int(frame.height))", center: CGPoint(x: frame.midX, y: frame.maxY + 18), filled: true)

// Tagline.
let tag = NSAttributedString(string: "See the structure behind the interface.", attributes: [
    .font: NSFont.systemFont(ofSize: 22, weight: .regular), .foregroundColor: NSColor(srgbRed: 0.62, green: 0.71, blue: 0.80, alpha: 1), .kern: 0.2,
])
tag.draw(at: CGPoint(x: (W - tag.size().width) / 2, y: frame.maxY + 50))

try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "docs/assets/banner.png"))
print("wrote docs/assets/banner.png")
