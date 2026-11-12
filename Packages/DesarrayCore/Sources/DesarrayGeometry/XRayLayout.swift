import CoreGraphics

/// One element frame from any provider (AX today), canonical global top-left points.
/// Input order must be parent-before-child (DFS order).
public struct XBox: Codable, Equatable, Sendable {
    public var id: Int
    public var parent: Int?
    public var frame: CGRect
    public var role: String
    public var label: String?

    public init(id: Int, parent: Int?, frame: CGRect, role: String, label: String? = nil) {
        self.id = id
        self.parent = parent
        self.frame = frame
        self.role = role
        self.label = label
    }
}

/// A geometric distance between frames. Always INFERRED: an inset is not proven CSS padding
/// and a gap is not proven stack spacing (PRD §7.2).
public struct Spacing: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case inset, gap }
    public enum Axis: String, Codable, Sendable { case horizontal, vertical }

    public var kind: Kind
    public var axis: Axis
    public var from: CGPoint
    public var to: CGPoint
    public var value: CGFloat
    /// The box this distance is measured from (child for insets, upper/left sibling for gaps).
    public var ownerID: Int
}

public struct XRayLayout: Codable, Equatable, Sendable {
    public var boxes: [XBox]
    /// Leaf boxes that get a "W×H" pill.
    public var sizeLabelIDs: [Int]
    public var spacings: [Spacing]

    public static let empty = XRayLayout(boxes: [], sizeLabelIDs: [], spacings: [])
}

/// Turns raw element frames into what the x-ray draws:
/// - drops boxes outside `rect` or under 2pt, and collapses wrappers whose frame equals their parent's;
/// - inset = child edge → parent edge with no sibling in between;
/// - gap = box edge → nearest sibling below / to the right that overlaps on the other axis.
/// ponytail: O(n²) per parent's children; fine for AX trees after viewport pruning.
public func xrayLayout(_ input: [XBox], in rect: CGRect, maxSpacing: CGFloat = 64) -> XRayLayout {
    var kept: [XBox] = []
    var keptIndex: [Int: Int] = [:]          // id -> index in kept
    var representative: [Int: Int?] = [:]    // dropped/merged id -> kept ancestor id (or nil)

    func resolve(_ id: Int?) -> Int? {
        guard let id else { return nil }
        if keptIndex[id] != nil { return id }
        return representative[id] ?? nil
    }

    for b in input {
        let parent = resolve(b.parent)
        let tooSmall = b.frame.width < 2 || b.frame.height < 2
        let outside = !b.frame.intersects(rect)
        let wrapper = parent.map { nearlyEqual(kept[keptIndex[$0]!].frame, b.frame) } ?? false
        if tooSmall || outside || wrapper {
            representative[b.id] = parent
            continue
        }
        keptIndex[b.id] = kept.count
        kept.append(XBox(id: b.id, parent: parent, frame: b.frame, role: b.role, label: b.label))
    }

    var children: [Int: [XBox]] = [:]
    for b in kept { if let p = b.parent { children[p, default: []].append(b) } }

    var spacings: [Spacing] = []
    for b in kept {
        let f = b.frame
        let siblings = b.parent.flatMap { children[$0] }?.filter { $0.id != b.id } ?? []

        // Insets to parent.
        if let p = b.parent, let pf = keptIndex[p].map({ kept[$0].frame }), pf.insetBy(dx: -0.5, dy: -0.5).contains(f) {
            func blocked(_ test: (CGRect) -> Bool) -> Bool { siblings.contains { test($0.frame) } }
            let hOverlap = { (s: CGRect) in overlap(s.minX...s.maxX, f.minX...f.maxX) > 0 }
            let vOverlap = { (s: CGRect) in overlap(s.minY...s.maxY, f.minY...f.maxY) > 0 }
            let candidates: [(CGFloat, Bool, Spacing.Axis, CGPoint, CGPoint)] = [
                (f.minY - pf.minY, blocked { hOverlap($0) && $0.maxY <= f.minY + 0.5 }, .vertical,
                 CGPoint(x: f.midX, y: pf.minY), CGPoint(x: f.midX, y: f.minY)),
                (pf.maxY - f.maxY, blocked { hOverlap($0) && $0.minY >= f.maxY - 0.5 }, .vertical,
                 CGPoint(x: f.midX, y: f.maxY), CGPoint(x: f.midX, y: pf.maxY)),
                (f.minX - pf.minX, blocked { vOverlap($0) && $0.maxX <= f.minX + 0.5 }, .horizontal,
                 CGPoint(x: pf.minX, y: f.midY), CGPoint(x: f.minX, y: f.midY)),
                (pf.maxX - f.maxX, blocked { vOverlap($0) && $0.minX >= f.maxX - 0.5 }, .horizontal,
                 CGPoint(x: f.maxX, y: f.midY), CGPoint(x: pf.maxX, y: f.midY)),
            ]
            for (v, isBlocked, axis, a, z) in candidates where !isBlocked && v >= 2 && v <= maxSpacing {
                spacings.append(Spacing(kind: .inset, axis: axis, from: a, to: z, value: v, ownerID: b.id))
            }
        }

        // Gap to nearest sibling below.
        let below = siblings
            .filter { $0.frame.minY >= f.maxY - 0.5 && overlap($0.frame.minX...$0.frame.maxX, f.minX...f.maxX) > 0 }
            .min { $0.frame.minY < $1.frame.minY }
        if let s = below {
            let v = s.frame.minY - f.maxY
            let x = mid(overlapRange(s.frame.minX...s.frame.maxX, f.minX...f.maxX))
            if v >= 2 && v <= maxSpacing {
                spacings.append(Spacing(kind: .gap, axis: .vertical, from: CGPoint(x: x, y: f.maxY),
                                        to: CGPoint(x: x, y: s.frame.minY), value: v, ownerID: b.id))
            }
        }
        // Gap to nearest sibling on the right.
        let right = siblings
            .filter { $0.frame.minX >= f.maxX - 0.5 && overlap($0.frame.minY...$0.frame.maxY, f.minY...f.maxY) > 0 }
            .min { $0.frame.minX < $1.frame.minX }
        if let s = right {
            let v = s.frame.minX - f.maxX
            let y = mid(overlapRange(s.frame.minY...s.frame.maxY, f.minY...f.maxY))
            if v >= 2 && v <= maxSpacing {
                spacings.append(Spacing(kind: .gap, axis: .horizontal, from: CGPoint(x: f.maxX, y: y),
                                        to: CGPoint(x: s.frame.minX, y: y), value: v, ownerID: b.id))
            }
        }
    }

    let leaves = kept.filter { children[$0.id] == nil && $0.frame.width >= 16 && $0.frame.height >= 10 }
    return XRayLayout(
        boxes: kept,
        sizeLabelIDs: leaves.map(\.id),
        spacings: spacings.filter { rect.contains(CGPoint(x: ($0.from.x + $0.to.x) / 2, y: ($0.from.y + $0.to.y) / 2)) }
    )
}

/// Smallest kept box containing `p` — what a click on the x-ray selects.
public func hitTest(_ layout: XRayLayout, at p: CGPoint) -> XBox? {
    layout.boxes.filter { $0.frame.contains(p) }.min { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
}

private func nearlyEqual(_ a: CGRect, _ b: CGRect) -> Bool {
    abs(a.minX - b.minX) < 0.5 && abs(a.minY - b.minY) < 0.5 && abs(a.width - b.width) < 0.5 && abs(a.height - b.height) < 0.5
}

private func overlapRange(_ a: ClosedRange<CGFloat>, _ b: ClosedRange<CGFloat>) -> ClosedRange<CGFloat> {
    let lo = max(a.lowerBound, b.lowerBound), hi = min(a.upperBound, b.upperBound)
    return lo <= hi ? lo...hi : lo...lo
}

private func overlap(_ a: ClosedRange<CGFloat>, _ b: ClosedRange<CGFloat>) -> CGFloat {
    let r = overlapRange(a, b)
    return r.upperBound - r.lowerBound
}

private func mid(_ r: ClosedRange<CGFloat>) -> CGFloat { (r.lowerBound + r.upperBound) / 2 }

/// Label plan for dense UIs (lists, toolbars). Boxes are untouched; only labels are thinned:
/// - repeats collapse: a spacing with the same kind/axis/value in the same lane (same `from.x`)
///   is shown once (first, i.e. top-most) — a list of 12 rows shows "4" once, not 12×;
/// - sizes collapse: each distinct W×H pill is shown once;
/// - focus: spacings touching `focusID`'s frame always come first;
/// - budget: at most one label per ~`areaPerLabel` pt² of selection, shallow elements first.
/// The renderer's overlap check runs after this, in this order.
public func declutter(_ layout: XRayLayout, in rect: CGRect, focusID: Int?, areaPerLabel: CGFloat = 1600) -> XRayLayout {
    let byID = Dictionary(layout.boxes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    var depth: [Int: Int] = [:]
    for b in layout.boxes { depth[b.id] = b.parent.flatMap { depth[$0].map { $0 + 1 } } ?? 0 }
    let focus = focusID.flatMap { byID[$0]?.frame }

    func touchesFocus(_ s: Spacing) -> Bool {
        guard let f = focus?.insetBy(dx: -0.5, dy: -0.5) else { return false }
        return s.ownerID == focusID || f.contains(s.from) || f.contains(s.to)
    }
    let focused = layout.spacings.filter(touchesFocus)

    var seen = Set<String>()
    let rest = layout.spacings
        .filter { !touchesFocus($0) }
        .sorted { ($0.from.y, $0.from.x) < ($1.from.y, $1.from.x) } // top-most instance of a repeat wins
        .filter { s in
            let key = "\(s.kind)|\(s.axis)|\(Int((s.value * 2).rounded()))|\(Int(s.from.x.rounded()))"
            return seen.insert(key).inserted
        }
        .sorted { (depth[$0.ownerID] ?? 0, -$0.value) < (depth[$1.ownerID] ?? 0, -$1.value) }

    let budget = max(12, Int(rect.width * rect.height / areaPerLabel))
    var sizesSeen = Set<String>()
    let sizes = layout.sizeLabelIDs.filter { id in
        guard let f = byID[id]?.frame else { return false }
        return id == focusID || sizesSeen.insert("\(Int(f.width.rounded()))x\(Int(f.height.rounded()))").inserted
    }
    return XRayLayout(boxes: layout.boxes,
                      sizeLabelIDs: Array(sizes.prefix(max(6, budget / 3))),
                      spacings: focused + rest.prefix(max(0, budget - focused.count)))
}
