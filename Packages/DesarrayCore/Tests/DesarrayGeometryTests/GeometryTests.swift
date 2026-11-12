import CoreGraphics
import Foundation
import Testing
@testable import DesarrayDomain
@testable import DesarrayGeometry

@Suite struct ScreenSpaceTests {
    let space = ScreenSpace(primaryHeight: 1169)

    @Test func flipMatchesSpikeObservation() {
        // Observed in Spikes/coords.swift: cocoa (1123.77, 500.125) == CG (1123.77, 668.875)
        #expect(space.flip(CGPoint(x: 1123.765625, y: 500.125)) == CGPoint(x: 1123.765625, y: 668.875))
    }

    @Test func rectFlipRoundTrips() {
        let r = CGRect(x: 10, y: 20, width: 300, height: 40)
        #expect(space.flip(space.flip(r)) == r)
        #expect(space.flip(r) == CGRect(x: 10, y: 1169 - 60, width: 300, height: 40))
    }

    @Test func secondaryDisplayAboveAndLeftHasNegativeOrigin() {
        // Cocoa: display above-left of primary at (-1920, 1169) size 1920x1080.
        let cocoa = CGRect(x: -1920, y: 1169, width: 1920, height: 1080)
        #expect(space.flip(cocoa) == CGRect(x: -1920, y: -1080, width: 1920, height: 1080))
    }

    @Test func secondaryDisplayBelow() {
        let cocoa = CGRect(x: 0, y: -1440, width: 2560, height: 1440)
        #expect(space.flip(cocoa) == CGRect(x: 0, y: 1169, width: 2560, height: 1440))
    }
}

@Suite struct SelectionMathTests {
    @Test(arguments: [
        (CGPoint(x: 10, y: 10), CGPoint(x: 50, y: 30)),
        (CGPoint(x: 50, y: 30), CGPoint(x: 10, y: 10)),
        (CGPoint(x: 10, y: 30), CGPoint(x: 50, y: 10)),
        (CGPoint(x: 50, y: 10), CGPoint(x: 10, y: 30)),
    ])
    func dragInAnyDirectionNormalizes(a: CGPoint, b: CGPoint) {
        #expect(selectionRect(from: a, to: b) == CGRect(x: 10, y: 10, width: 40, height: 20))
    }

    @Test func clipToDisplay() {
        let d = DisplayInfo(id: 1, name: "A", frame: CGRect(x: 0, y: 0, width: 100, height: 100), scale: 2)
        let inside = clip(CGRect(x: 10, y: 10, width: 20, height: 20), to: d)
        #expect(inside.rect == CGRect(x: 10, y: 10, width: 20, height: 20) && !inside.clipped)
        let crossing = clip(CGRect(x: 90, y: 90, width: 20, height: 20), to: d)
        #expect(crossing.rect == CGRect(x: 90, y: 90, width: 10, height: 10) && crossing.clipped)
    }

    @Test func clipNegativeOriginDisplay() {
        let d = DisplayInfo(id: 2, name: "B", frame: CGRect(x: -1920, y: -1080, width: 1920, height: 1080), scale: 1)
        let r = clip(CGRect(x: -10, y: -10, width: 30, height: 30), to: d)
        #expect(r.rect == CGRect(x: -10, y: -10, width: 10, height: 10) && r.clipped)
    }

    @Test func edgeDistancesInsideContainer() {
        let e = edgeDistances(of: CGRect(x: 10, y: 20, width: 30, height: 40),
                              in: CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(e == EdgeInsets(top: 20, left: 10, bottom: 40, right: 60))
    }
}

@Suite struct GridTests {
    @Test func pointAndPixelGridsDiffer() {
        #expect(GridUnit.pt4.step(scale: 2) == 4)
        #expect(GridUnit.px4.step(scale: 2) == 2)
        #expect(GridUnit.px4.step(scale: 1) == 4)
        #expect(GridUnit.off.step(scale: 2) == nil)
    }

    @Test func gridOffsetsExcludeEdges() {
        #expect(gridOffsets(length: 12, step: 4) == [4, 8])
        #expect(gridOffsets(length: 13, step: 4) == [4, 8, 12])
        #expect(gridOffsets(length: 4, step: 4) == [])
        #expect(gridOffsets(length: 10, step: 0) == [])
    }

    @Test func alignmentUsesHalfPixelTolerance() {
        #expect(isAligned(48, step: 4, scale: 2))
        #expect(isAligned(48.2, step: 4, scale: 2))   // within 0.25pt
        #expect(!isAligned(48.5, step: 4, scale: 2))
        #expect(isAligned(47.8, step: 4, scale: 2))
        #expect(!isAligned(46, step: 4, scale: 2))
    }

    @Test func pixelsUseDisplayScale() {
        #expect(pixels(100, scale: 2) == 200)
        #expect(pixels(100, scale: 1) == 100)
    }

    @Test func formatting() {
        #expect(format(12, unit: "pt") == "12 pt")
        #expect(format(12.5, unit: "pt") == "12.5 pt")
        #expect(format(12.3333, unit: "px") == "12.33 px")
        #expect(format(-0, unit: "pt") == "0 pt")
    }
}

@Suite struct ProvenanceTests {
    @Test func selectionIsObservedAndRoundTrips() throws {
        let s = Selection(rect: CGRect(x: 1, y: 2, width: 3, height: 4), displayID: 1,
                          displayName: "Built-in", backingScale: 2, clipped: true,
                          capturedAt: Date(timeIntervalSince1970: 0))
        #expect(s.provenance.kind == .observed)
        #expect(s.provenance.source == .selectionGeometry)
        #expect(s.provenance.unit == "pt")
        #expect(!s.provenance.limitations.isEmpty)
        let decoded = try JSONDecoder().decode(Selection.self, from: JSONEncoder().encode(s))
        #expect(decoded == s)
    }
}

@Suite struct XRayLayoutTests {
    // A card like the inspo: 360x256 container, header + two rows, each row has a 97x32 button.
    let card = CGRect(x: 0, y: 0, width: 360, height: 256)
    var input: [XBox] {
        [
            XBox(id: 1, parent: nil, frame: card, role: "AXGroup"),
            XBox(id: 2, parent: 1, frame: card, role: "AXGroup"),                                   // wrapper, same frame
            XBox(id: 3, parent: 2, frame: CGRect(x: 16, y: 16, width: 328, height: 40), role: "AXGroup"),   // header
            XBox(id: 4, parent: 2, frame: CGRect(x: 16, y: 76, width: 328, height: 64), role: "AXGroup"),   // row 1
            XBox(id: 5, parent: 4, frame: CGRect(x: 231, y: 92, width: 97, height: 32), role: "AXButton"),
            XBox(id: 6, parent: 2, frame: CGRect(x: 16, y: 152, width: 328, height: 64), role: "AXGroup"),  // row 2
            XBox(id: 7, parent: 6, frame: CGRect(x: 231, y: 168, width: 97, height: 32), role: "AXButton"),
            XBox(id: 8, parent: 1, frame: CGRect(x: 900, y: 900, width: 10, height: 10), role: "AXButton"),  // outside
        ]
    }

    @Test func collapsesWrappersAndDropsOutside() {
        let l = xrayLayout(input, in: card)
        #expect(l.boxes.map(\.id) == [1, 3, 4, 5, 6, 7])
        #expect(l.boxes.first { $0.id == 3 }?.parent == 1) // re-parented past the wrapper
    }

    @Test func insetsAndGaps() {
        let l = xrayLayout(input, in: card)
        func values(_ kind: Spacing.Kind, owner: Int) -> [CGFloat] {
            l.spacings.filter { $0.kind == kind && $0.ownerID == owner }.map(\.value).sorted()
        }
        // Header: top 16, left 16, right 16; bottom blocked by row 1.
        #expect(values(.inset, owner: 3) == [16, 16, 16])
        // Header -> row 1 gap 20, row 1 -> row 2 gap 12.
        #expect(values(.gap, owner: 3) == [20])
        #expect(values(.gap, owner: 4) == [12])
        // Button inside row: top 16, bottom 16, right 16, left 215 (> max, dropped).
        #expect(values(.inset, owner: 5) == [16, 16, 16])
    }

    @Test func sizeLabelsOnLeaves() {
        let l = xrayLayout(input, in: card)
        #expect(Set(l.sizeLabelIDs) == [3, 5, 7])
    }

    @Test func hitTestPicksSmallest() {
        let l = xrayLayout(input, in: card)
        #expect(hitTest(l, at: CGPoint(x: 250, y: 100))?.id == 5)
        #expect(hitTest(l, at: CGPoint(x: 20, y: 100))?.id == 4)
    }
}

@Suite struct DeclutterTests {
    /// A 12-row list: every row has the same 4pt left inset, 8pt right inset, 2pt gap, and a 24×24 icon.
    var list: (XRayLayout, CGRect) {
        let rect = CGRect(x: 0, y: 0, width: 300, height: 12 * 34 + 4)
        var boxes = [XBox(id: 0, parent: nil, frame: rect, role: "AXList")]
        for i in 0..<12 {
            let y = 4 + CGFloat(i) * 34
            boxes.append(XBox(id: 1 + i * 2, parent: 0, frame: CGRect(x: 4, y: y, width: 288, height: 32), role: "AXRow"))
            boxes.append(XBox(id: 2 + i * 2, parent: 1 + i * 2, frame: CGRect(x: 260, y: y + 4, width: 24, height: 24), role: "AXButton"))
        }
        return (xrayLayout(boxes, in: rect), rect)
    }

    @Test func repeatsCollapseToOne() {
        let (raw, rect) = list
        let d = declutter(raw, in: rect, focusID: nil)
        #expect(raw.spacings.count > 40)
        let leftInsets = d.spacings.filter { $0.kind == .inset && $0.axis == .horizontal && $0.value == 4 && $0.from.x == 0 }
        #expect(leftInsets.count == 1)
        #expect(d.spacings.filter { $0.kind == .gap && $0.value == 2 }.count == 1)
        #expect(d.sizeLabelIDs.count == 1) // one "24×24", not twelve
    }

    @Test func focusKeepsItsSpacings() {
        let (raw, rect) = list
        let row7 = 1 + 7 * 2
        let d = declutter(raw, in: rect, focusID: row7)
        let mine = raw.spacings.filter { $0.ownerID == row7 }
        #expect(!mine.isEmpty)
        #expect(mine.allSatisfy { m in d.spacings.contains(m) }) // row 7's repeats survive dedupe when focused
    }

    @Test func budgetCapsLabels() {
        let (raw, _) = list
        let tiny = CGRect(x: 0, y: 0, width: 100, height: 100)
        #expect(declutter(raw, in: tiny, focusID: nil).spacings.count <= 12)
    }
}
