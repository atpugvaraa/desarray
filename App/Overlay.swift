import AppKit
import DesarrayDomain
import DesarrayGeometry
import DesarrayRender

let accent = NSColor(cgColor: XRayRenderer.accent)!

/// One transparent panel per display, alive only during an active session (DECISIONS D6).
final class OverlayController {
    private unowned let session: Session
    private var panels: [OverlayPanel] = []

    init(session: Session) { self.session = session }

    var level: NSWindow.Level { .screenSaver }

    func show(displays: [DisplayInfo], space: ScreenSpace) {
        hide()
        let mouse = NSEvent.mouseLocation
        for display in displays {
            let cocoaFrame = space.flip(display.frame)
            let panel = OverlayPanel(contentRect: cocoaFrame, styleMask: [.borderless, .nonactivatingPanel],
                                     backing: .buffered, defer: false)
            panel.level = level
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.contentView = OverlayView(display: display, session: session, controller: self)
            panel.setFrame(cocoaFrame, display: true)
            panel.orderFrontRegardless()
            if cocoaFrame.contains(mouse) { panel.makeKey() }
            panels.append(panel)
        }
    }

    func hide() {
        panels.forEach { $0.orderOut(nil) }
        panels = []
    }

    func redraw() { panels.forEach { $0.contentView?.needsDisplay = true } }

    func pointerMoved(to view: OverlayView) {
        for case let other as OverlayView in panels.map(\.contentView) where other !== view { other.cursor = nil }
    }
}

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class OverlayView: NSView {
    let display: DisplayInfo
    private unowned let session: Session
    private unowned let controller: OverlayController

    private enum Drag { case create(anchor: CGPoint), move(offset: CGSize), resize(anchor: CGPoint) }
    private var drag: Drag?
    var cursor: CGPoint? { didSet { needsDisplay = true } }

    private let handleSize: CGFloat = 7
    private let minimumSize: CGFloat = 2

    init(display: DisplayInfo, session: Session, controller: OverlayController) {
        self.display = display
        self.session = session
        self.controller = controller
        super.init(frame: CGRect(origin: .zero, size: display.frame.size))
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true } // local coords are top-left, like canonical space
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    private func global(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + display.frame.minX, y: p.y + display.frame.minY) }
    private func local(_ r: CGRect) -> CGRect { r.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY) }
    private func point(_ e: NSEvent) -> CGPoint { convert(e.locationInWindow, from: nil) }

    private var localSelection: CGRect? {
        guard let s = session.selection, s.displayID == display.id else { return nil }
        return local(s.rect)
    }

    private func corners(_ r: CGRect) -> [CGPoint] {
        [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
         CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)]
    }

    // MARK: mouse

    override func mouseDown(with e: NSEvent) {
        window?.makeKey()
        let p = point(e)
        if let r = localSelection {
            let cs = corners(r)
            if let i = cs.firstIndex(where: { hypot($0.x - p.x, $0.y - p.y) <= handleSize }) {
                drag = .resize(anchor: cs[(i + 2) % 4])
                return
            }
            if r.contains(p) {
                drag = .move(offset: CGSize(width: p.x - r.minX, height: p.y - r.minY))
                return
            }
        }
        drag = .create(anchor: p)
    }

    override func mouseDragged(with e: NSEvent) {
        let p = point(e)
        cursor = p
        switch drag {
        case .create(let anchor), .resize(let anchor):
            session.select(selectionRect(from: global(anchor), to: global(p)), on: display, requestedClip: false)
        case .move(let offset):
            guard let r = localSelection else { return }
            let x = min(max(0, p.x - offset.width), bounds.width - r.width)
            let y = min(max(0, p.y - offset.height), bounds.height - r.height)
            session.select(CGRect(origin: global(CGPoint(x: x, y: y)), size: r.size), on: display, requestedClip: false)
        case nil: break
        }
    }

    override func mouseUp(with e: NSEvent) {
        if case .create(let anchor) = drag {
            let r = selectionRect(from: anchor, to: point(e))
            if r.width < minimumSize || r.height < minimumSize { session.selection = nil } // a click, not a selection
        }
        drag = nil
    }

    override func mouseMoved(with e: NSEvent) {
        cursor = point(e)
        controller.pointerMoved(to: self)
    }

    override func mouseExited(with e: NSEvent) { cursor = nil }

    // MARK: keyboard

    override func keyDown(with e: NSEvent) {
        let step: CGFloat = e.modifierFlags.contains(.shift) ? 10 : 1
        let resize = e.modifierFlags.contains(.option)
        switch Int(e.keyCode) {
        case 53: session.escape()
        case 36, 76: session.capture()              // Return / Enter
        case 7: session.showXRay.toggle()            // X
        case 5: session.cycleGrid()                  // G
        case 123: session.nudge(dx: -step, dy: 0, resize: resize)
        case 124: session.nudge(dx: step, dy: 0, resize: resize)
        case 125: session.nudge(dx: 0, dy: step, resize: resize)
        case 126: session.nudge(dx: 0, dy: -step, resize: resize)
        default: super.keyDown(with: e)
        }
    }

    // MARK: drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let sel = localSelection

        // Dim everything outside the selection.
        let dim = NSBezierPath(rect: bounds)
        if let sel { dim.append(NSBezierPath(rect: sel)); dim.windingRule = .evenOdd }
        NSColor.black.withAlphaComponent(0.25).setFill()
        dim.fill()

        if let cursor, drag == nil, !(sel?.contains(cursor) ?? false) { drawCrosshair(at: cursor) } // no crosshair over the x-ray
        guard let r = sel, let s = session.selection else { return }

        var o = XRayOptions(gridStep: session.grid.step(scale: display.scale), hairline: 1 / display.scale)
        o.showBoxes = session.showXRay
        o.showLabels = session.showXRay
        // Hover focus: the element under the pointer gets outlined and all its spacings labelled.
        if let c = cursor, r.contains(c) { o.highlightID = DesarrayGeometry.hitTest(session.layout, at: global(c))?.id }
        // Flipped NSView => ctx is already y-down in view points; renderer origin = this display's origin.
        XRayRenderer.draw(ctx, selection: s.rect, layout: session.showXRay ? session.layout : .empty,
                          origin: display.frame.origin, options: o)

        for c in corners(r) {
            let h = NSBezierPath(rect: CGRect(x: c.x - handleSize / 2, y: c.y - handleSize / 2, width: handleSize, height: handleSize))
            NSColor.white.setFill(); h.fill()
            accent.setStroke(); h.lineWidth = 1; h.stroke()
        }
    }

    private func drawCrosshair(at p: CGPoint) {
        accent.withAlphaComponent(0.45).setFill()
        let hairline = 1 / display.scale
        CGRect(x: p.x, y: 0, width: hairline, height: bounds.height).fill()
        CGRect(x: 0, y: p.y, width: bounds.width, height: hairline).fill()
        let g = global(p)
        let s = NSAttributedString(string: "\(num(g.x)), \(num(g.y))", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold), .foregroundColor: NSColor.white,
        ])
        let size = s.size()
        var box = CGRect(x: p.x + 8, y: p.y + 8, width: size.width + 10, height: size.height + 4)
        box.origin.x = min(box.minX, bounds.width - box.width - 2)
        box.origin.y = min(box.minY, bounds.height - box.height - 2)
        NSColor.black.withAlphaComponent(0.8).setFill()
        NSBezierPath(roundedRect: box, xRadius: 3, yRadius: 3).fill()
        s.draw(at: CGPoint(x: box.minX + 5, y: box.minY + 2))
    }
}
