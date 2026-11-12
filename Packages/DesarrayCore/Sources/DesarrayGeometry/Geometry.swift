import CoreGraphics
import Foundation

/// A display snapshot in canonical space (global top-left points).
public struct DisplayInfo: Equatable, Sendable {
    public var id: UInt32
    public var name: String
    public var frame: CGRect
    public var scale: CGFloat

    public init(id: UInt32, name: String, frame: CGRect, scale: CGFloat) {
        self.id = id
        self.name = name
        self.frame = frame
        self.scale = scale
    }
}

/// Converts between AppKit global coordinates (origin bottom-left of primary display)
/// and canonical global top-left points (CG / AX convention). The flip is its own inverse.
public struct ScreenSpace: Equatable, Sendable {
    /// Height of the primary display (the one whose Cocoa origin is (0,0)).
    public var primaryHeight: CGFloat

    public init(primaryHeight: CGFloat) { self.primaryHeight = primaryHeight }

    public func flip(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: primaryHeight - p.y) }

    public func flip(_ r: CGRect) -> CGRect {
        let r = r.standardized
        return CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }
}

/// Rectangle spanned by two drag points, in any direction.
public func selectionRect(from a: CGPoint, to b: CGPoint) -> CGRect {
    CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
}

/// Clip a canonical rect to a display. Returns the clipped rect and whether clipping happened.
public func clip(_ rect: CGRect, to display: DisplayInfo) -> (rect: CGRect, clipped: Bool) {
    let r = rect.standardized
    let c = r.intersection(display.frame)
    if c.isNull { return (CGRect(origin: r.origin, size: .zero), true) }
    return (c, c != r)
}

/// Distance from each edge of `rect` to the matching edge of `container` (positive = inside).
public struct EdgeInsets: Equatable, Sendable {
    public var top, left, bottom, right: CGFloat
}

public func edgeDistances(of rect: CGRect, in container: CGRect) -> EdgeInsets {
    EdgeInsets(top: rect.minY - container.minY,
               left: rect.minX - container.minX,
               bottom: container.maxY - rect.maxY,
               right: container.maxX - rect.maxX)
}

public enum GridUnit: String, CaseIterable, Sendable {
    case off, pt4, px4

    public var label: String {
        switch self {
        case .off: "Off"
        case .pt4: "4 pt"
        case .px4: "4 px"
        }
    }

    /// Grid step in logical points for a display with `scale` px/pt. nil when off.
    public func step(scale: CGFloat) -> CGFloat? {
        switch self {
        case .off: nil
        case .pt4: 4
        case .px4: 4 / scale
        }
    }
}

/// Offsets (from 0) of interior grid lines across `length`, every `step`.
public func gridOffsets(length: CGFloat, step: CGFloat) -> [CGFloat] {
    guard step > 0, length > step else { return [] }
    return Array(stride(from: step, to: length, by: step))
}

/// True when `value` sits on a multiple of `step` within half a physical pixel.
public func isAligned(_ value: CGFloat, step: CGFloat, scale: CGFloat) -> Bool {
    guard step > 0 else { return false }
    let remainder = value.truncatingRemainder(dividingBy: step)
    let tolerance = 0.5 / scale
    return abs(remainder) <= tolerance || abs(step - abs(remainder)) <= tolerance
}

public func pixels(_ points: CGFloat, scale: CGFloat) -> CGFloat { points * scale }

/// "12 pt", "12.5 pt" — trims trailing zeros, max 2 decimals.
public func format(_ v: CGFloat, unit: String) -> String {
    let rounded = (v * 100).rounded() / 100
    let s = rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%g", rounded)
    return "\(s) \(unit)"
}
