import CoreGraphics
import CoreText
import DesarrayGeometry
import Foundation

public struct XRayOptions: Sendable {
    public var gridStep: CGFloat?
    /// Width of a 1-device-pixel line in context units.
    public var hairline: CGFloat = 0.5
    public var showBoxes = true
    public var showLabels = true
    /// Focused element (hover / list selection): outlined, and its spacings are always labelled.
    public var highlightID: Int?
    /// Draw the outer selection outline + its size pill (off for a cropped capture where the frame is the image).
    public var showSelectionChrome = true

    public init(gridStep: CGFloat? = 4, hairline: CGFloat = 0.5) {
        self.gridStep = gridStep
        self.hairline = hairline
    }
}

/// Draws the x-ray. One renderer for the live overlay, the capture window and PNG export.
public enum XRayRenderer {
    public static let accent = CGColor(srgbRed: 0.16, green: 0.58, blue: 1.0, alpha: 1)

    /// `ctx` must be y-down (top-left origin) in points. `origin` is the global point drawn at ctx (0,0).
    public static func draw(_ ctx: CGContext, selection: CGRect, layout: XRayLayout, origin: CGPoint, options o: XRayOptions) {
        let sel = selection.offsetBy(dx: -origin.x, dy: -origin.y)
        func local(_ r: CGRect) -> CGRect { r.offsetBy(dx: -origin.x, dy: -origin.y) }
        func local(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x - origin.x, y: p.y - origin.y) }

        ctx.saveGState()
        ctx.clip(to: sel)

        // Skeleton: blue wash + diagonal hatch.
        ctx.setFillColor(accent.copy(alpha: 0.16)!)
        ctx.fill(sel)
        ctx.setStrokeColor(accent.copy(alpha: 0.22)!)
        ctx.setLineWidth(o.hairline)
        var x = sel.minX - sel.height
        while x < sel.maxX {
            ctx.move(to: CGPoint(x: x, y: sel.maxY))
            ctx.addLine(to: CGPoint(x: x + sel.height, y: sel.minY))
            x += 6
        }
        ctx.strokePath()

        if let step = o.gridStep {
            ctx.setFillColor(accent.copy(alpha: 0.13)!)
            for dx in gridOffsets(length: sel.width, step: step) { ctx.fill(CGRect(x: sel.minX + dx, y: sel.minY, width: o.hairline, height: sel.height)) }
            for dy in gridOffsets(length: sel.height, step: step) { ctx.fill(CGRect(x: sel.minX, y: sel.minY + dy, width: sel.width, height: o.hairline)) }
        }

        if o.showBoxes {
            for b in layout.boxes {
                let r = local(b.frame).insetBy(dx: o.hairline / 2, dy: o.hairline / 2)
                let hot = b.id == o.highlightID
                ctx.setFillColor(CGColor(gray: 0, alpha: hot ? 0 : 0.22))
                ctx.fill(r)
                if hot { ctx.setFillColor(accent.copy(alpha: 0.35)!); ctx.fill(r) }
                ctx.setStrokeColor(accent.copy(alpha: hot ? 1 : 0.55)!)
                ctx.setLineWidth(hot ? 2 * o.hairline : o.hairline)
                ctx.stroke(r)
            }
        }
        ctx.restoreGState()

        var placed: [CGRect] = []
        if o.showLabels {
            let layout = declutter(layout, in: selection, focusID: o.highlightID)
            for s in layout.spacings { drawSpacing(ctx, s, local: local, hairline: o.hairline, placed: &placed) }
            let byID = Dictionary(layout.boxes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            for id in layout.sizeLabelIDs {
                guard let b = byID[id] else { continue }
                let r = local(b.frame)
                guard sel.contains(CGPoint(x: r.midX, y: r.maxY)) else { continue }
                pill(ctx, "\(num(b.frame.width))×\(num(b.frame.height))", center: CGPoint(x: r.midX, y: r.maxY + 8),
                     filled: true, bounds: sel.insetBy(dx: 1, dy: 1), placed: &placed)
            }
        }

        if o.showSelectionChrome {
            ctx.setStrokeColor(accent)
            ctx.setLineWidth(1)
            ctx.stroke(sel.insetBy(dx: 0.5, dy: 0.5))
            pill(ctx, "\(num(selection.width)) × \(num(selection.height))", center: CGPoint(x: sel.midX, y: sel.maxY + 12),
                 filled: true, bounds: .infinite, placed: &placed, force: true)
        }
    }

    /// Screenshot + x-ray composited at pixel resolution (for Copy / Save PNG).
    public static func composite(image: CGImage?, selection: CGRect, layout: XRayLayout, scale: CGFloat, options: XRayOptions) -> CGImage? {
        let w = Int((selection.width * scale).rounded()), h = Int((selection.height * scale).rounded())
        guard w > 0, h > 0, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                                 space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(gray: 0.12, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        if let image { ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h)) } // bitmap ctx is y-up: draws upright
        // Switch to y-down points.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)
        var o = options
        o.hairline = 1 / scale
        o.showSelectionChrome = false
        draw(ctx, selection: selection, layout: layout, origin: selection.origin, options: o)
        return ctx.makeImage()
    }

    // MARK: pieces

    private static func drawSpacing(_ ctx: CGContext, _ s: Spacing, local: (CGPoint) -> CGPoint, hairline: CGFloat, placed: inout [CGRect]) {
        let a = local(s.from), z = local(s.to)
        ctx.setStrokeColor(accent.copy(alpha: 0.95)!)
        ctx.setLineWidth(1)
        ctx.move(to: a); ctx.addLine(to: z)
        // End ticks, perpendicular.
        let t: CGFloat = 3
        for p in [a, z] {
            if s.axis == .vertical { ctx.move(to: CGPoint(x: p.x - t, y: p.y)); ctx.addLine(to: CGPoint(x: p.x + t, y: p.y)) }
            else { ctx.move(to: CGPoint(x: p.x, y: p.y - t)); ctx.addLine(to: CGPoint(x: p.x, y: p.y + t)) }
        }
        ctx.strokePath()
        pill(ctx, num(s.value), center: CGPoint(x: (a.x + z.x) / 2, y: (a.y + z.y) / 2), filled: false, bounds: .infinite, placed: &placed)
    }

    /// Label pill; skipped when it would overlap an already placed label (unless `force`).
    private static func pill(_ ctx: CGContext, _ text: String, center c: CGPoint, filled: Bool, bounds: CGRect,
                             placed: inout [CGRect], force: Bool = false) {
        let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, 9, nil)!
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): filled ? CGColor(gray: 1, alpha: 1) : accent,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        var box = CGRect(x: c.x - width / 2 - 4, y: c.y - (ascent + descent) / 2 - 2, width: width + 8, height: ascent + descent + 4)
        if !bounds.isInfinite {
            box.origin.x = min(max(bounds.minX, box.minX), bounds.maxX - box.width)
            box.origin.y = min(max(bounds.minY, box.minY), bounds.maxY - box.height)
        }
        if !force, placed.contains(where: { $0.insetBy(dx: -1, dy: -1).intersects(box) }) { return }
        placed.append(box)

        ctx.setFillColor(filled ? accent : CGColor(gray: 0.04, alpha: 0.92))
        ctx.addPath(CGPath(roundedRect: box, cornerWidth: 2.5, cornerHeight: 2.5, transform: nil))
        ctx.fillPath()
        ctx.saveGState()
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1) // upright glyphs in a y-down context
        ctx.textPosition = CGPoint(x: box.minX + 4, y: box.minY + 2 + ascent)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }
}

/// "16", "12.5", "97.33" — no unit, max 2 decimals.
public func num(_ v: CGFloat) -> String {
    format(v, unit: "").trimmingCharacters(in: .whitespaces)
}
