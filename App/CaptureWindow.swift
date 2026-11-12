import AppKit
import DesarrayAccessibility
import DesarrayDomain
import DesarrayGeometry
import DesarrayRender
import SwiftUI
import UniformTypeIdentifiers

/// A frozen capture: screenshot + AX snapshot + derived layout. Nothing here is persisted.
@Observable
final class CaptureModel {
    let selection: Selection
    let snapshot: XRaySnapshot?
    let layout: XRayLayout
    let image: CGImage?
    let imageError: String?
    var grid: GridUnit
    var showXRay = true
    var showLabels = true
    var selectedID: Int?
    /// Tree depth per box, for list indentation.
    let depth: [Int: Int]

    init(selection: Selection, snapshot: XRaySnapshot?, image: CGImage?, imageError: String?, grid: GridUnit) {
        self.selection = selection
        self.snapshot = snapshot
        let layout = snapshot.map { xrayLayout($0.boxes, in: selection.rect) } ?? .empty
        self.layout = layout
        var d: [Int: Int] = [:]
        for b in layout.boxes { d[b.id] = b.parent.flatMap { d[$0].map { $0 + 1 } } ?? 0 }
        self.depth = d
        self.image = image
        self.imageError = imageError
        self.grid = grid
    }

    var rect: CGRect { selection.rect }
    var scale: CGFloat { selection.backingScale }

    var options: XRayOptions {
        var o = XRayOptions(gridStep: grid.step(scale: scale), hairline: 1 / scale)
        o.showBoxes = showXRay
        o.showLabels = showXRay && showLabels
        o.highlightID = selectedID
        o.showSelectionChrome = false
        return o
    }


    func composite() -> CGImage? {
        XRayRenderer.composite(image: image, selection: rect, layout: showXRay ? layout : .empty, scale: scale, options: options)
    }

    /// Versioned, provenance-preserving export (PRD §7.4, §14 Phase 6 seed).
    func json() -> String {
        struct Element: Encodable { let id: Int; let parent: Int?; let role: String; let title: String?; let frame: CGRect
            let evidence = "observed"; let source = "accessibility"; let method = "AXPosition+AXSize/1" }
        struct Measure: Encodable { let kind: String; let axis: String; let value: CGFloat; let ownerID: Int
            let from: CGPoint; let to: CGPoint; let evidence = "inferred"; let method: String; let limitation: String }
        struct Export: Encodable {
            let schemaVersion = 1; let tool = "desarray."; let capturedAt: Date; let app: String?
            let coordinateSpace = "globalTopLeftPoints"; let unit = "pt"; let backingScale: CGFloat
            let selection: CGRect; let axStatus: String; let elements: [Element]; let measurements: [Measure]
        }
        let e = Export(
            capturedAt: snapshot?.capturedAt ?? selection.provenance.capturedAt, app: snapshot?.appName,
            backingScale: scale, selection: rect, axStatus: snapshot.map { "\($0.status)" } ?? "unavailable",
            elements: layout.boxes.map { Element(id: $0.id, parent: $0.parent, role: $0.role, title: $0.label, frame: $0.frame) },
            measurements: layout.spacings.map {
                Measure(kind: $0.kind.rawValue, axis: $0.axis.rawValue, value: $0.value, ownerID: $0.ownerID, from: $0.from, to: $0.to,
                        method: $0.kind == .inset ? "ax-parent-child-inset/1" : "ax-sibling-gap/1",
                        limitation: $0.kind == .inset ? "Parent/child inset candidate; not proof of padding."
                                                     : "Geometric gap between frames; not proof of margin or stack spacing.")
            })
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return (try? enc.encode(e)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}

enum CaptureWindow {
    private static var windows: [NSWindow] = []

    static func open(_ model: CaptureModel) {
        let title = [model.snapshot?.appName, "\(num(model.rect.width)) × \(num(model.rect.height)) pt"].compactMap { $0 }.joined(separator: " · ")
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1180, height: 760),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "desarray. — \(title)"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: CaptureView(model: model))
        window.setContentSize(CGSize(width: 1180, height: 760))
        window.center()
        windows.append(window)
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak window] _ in
            MainActor.assumeIsolated { windows.removeAll { $0 === window } }
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

struct CaptureView: View {
    @Bindable var model: CaptureModel

    var body: some View {
        HSplitView {
            canvas.frame(minWidth: 480, minHeight: 400)
            sidebar.frame(minWidth: 280, idealWidth: 320, maxWidth: 420)
        }
    }

    // MARK: canvas

    private var canvas: some View {
        GeometryReader { geo in
            let r = model.rect
            let fit = min((geo.size.width - 48) / r.width, (geo.size.height - 48) / r.height, 4)
            let size = CGSize(width: r.width * fit, height: r.height * fit)
            let offset = CGPoint(x: (geo.size.width - size.width) / 2, y: (geo.size.height - size.height) / 2)
            Canvas { ctx, _ in
                ctx.withCGContext { cg in
                    cg.translateBy(x: offset.x, y: offset.y)
                    cg.scaleBy(x: fit, y: fit)
                    cg.setFillColor(CGColor(gray: 0.12, alpha: 1))
                    cg.fill(CGRect(origin: .zero, size: r.size))
                    if let image = model.image {
                        // Canvas is y-down; CGContext.draw is y-up — flip locally so the image is upright.
                        cg.saveGState()
                        cg.translateBy(x: 0, y: r.height)
                        cg.scaleBy(x: 1, y: -1)
                        cg.interpolationQuality = .high
                        cg.draw(image, in: CGRect(origin: .zero, size: r.size))
                        cg.restoreGState()
                    }
                    var o = model.options
                    o.hairline = 1 / max(fit, 0.01)
                    XRayRenderer.draw(cg, selection: r, layout: model.showXRay ? model.layout : .empty, origin: r.origin, options: o)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { p in
                let global = CGPoint(x: (p.x - offset.x) / fit + r.minX, y: (p.y - offset.y) / fit + r.minY)
                model.selectedID = hitTest(model.layout, at: global)?.id
            }
        }
        .background(Color(white: 0.08))
    }

    // MARK: sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(model.snapshot?.appName ?? "Visual region").font(.headline)
                Text("\(num(model.rect.width)) × \(num(model.rect.height)) pt · @\(num(model.scale))x · \(model.selection.provenance.capturedAt.formatted(date: .omitted, time: .standard))")
                    .font(.caption).foregroundStyle(.secondary)
                warnings
                HStack {
                    Toggle("X-ray", isOn: $model.showXRay)
                    Toggle("Labels", isOn: $model.showLabels).disabled(!model.showXRay)
                }
                .toggleStyle(.checkbox)
                Picker("Grid", selection: $model.grid) {
                    ForEach(GridUnit.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            .padding(12)

            Divider()
            List(model.layout.boxes, id: \.id, selection: $model.selectedID) { b in
                HStack(spacing: 6) {
                    Text(short(b.role)).foregroundStyle(.secondary)
                    if let l = b.label { Text(l).lineLimit(1) }
                    Spacer()
                    Text("\(num(b.frame.width))×\(num(b.frame.height))").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                .padding(.leading, CGFloat(min(model.depth[b.id] ?? 0, 12)) * 10)
                .tag(b.id)
            }
            .listStyle(.sidebar)
            .frame(minHeight: 160)

            if let id = model.selectedID, let b = model.layout.boxes.first(where: { $0.id == id }) {
                Divider()
                details(b).padding(12)
            }

            Divider()
            HStack {
                Button("Copy PNG") { if let i = model.composite() { copy(image: i) } }
                Button("Save PNG…") { save() }
                Button("Copy JSON") { copy(text: model.json()) }
            }
            .controlSize(.small)
            .padding(12)
        }
    }

    @ViewBuilder private var warnings: some View {
        if let e = model.imageError {
            Label(e, systemImage: "exclamationmark.triangle").font(.caption).fixedSize(horizontal: false, vertical: true)
        }
        if model.snapshot == nil || model.snapshot?.status == .notTrusted {
            Label("No element x-ray: Accessibility is off for desarray.", systemImage: "exclamationmark.triangle").font(.caption)
        } else if case .partial(let why) = model.snapshot?.status {
            Label("Partial x-ray (\(why)).", systemImage: "exclamationmark.triangle").font(.caption)
        } else if model.snapshot?.status == .noWindow {
            Label("No window under the frame.", systemImage: "exclamationmark.triangle").font(.caption)
        }
    }

    private func details(_ b: XBox) -> some View {
        let spacings = model.layout.spacings.filter { $0.ownerID == b.id }
        return VStack(alignment: .leading, spacing: 6) {
            HStack { Text(short(b.role)).font(.headline); if let l = b.label { Text(l).lineLimit(1) } }
            Badge(kind: "OBSERVED", detail: "Accessibility frame")
            Text("x \(num(b.frame.minX))  y \(num(b.frame.minY))  w \(num(b.frame.width))  h \(num(b.frame.height)) pt")
                .font(.system(.caption, design: .monospaced))
            if !spacings.isEmpty {
                Badge(kind: "INFERRED", detail: "frame geometry")
                ForEach(Array(spacings.enumerated()), id: \.offset) { _, s in
                    Text("\(s.kind == .inset ? "inset" : "gap") \(s.axis == .vertical ? "↕" : "↔") \(num(s.value)) pt")
                        .font(.system(.caption, design: .monospaced))
                }
                Text("AX frames can differ from painted bounds; insets are not proof of padding.")
                    .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func short(_ role: String) -> String { role.hasPrefix("AX") ? String(role.dropFirst(2)) : role }

    private func copy(text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func copy(image: CGImage) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([NSImage(cgImage: image, size: model.rect.size)])
    }

    private func save() {
        guard let image = model.composite() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "desarray-\(model.snapshot?.appName ?? "capture").png"
        guard panel.runModal() == .OK, let url = panel.url,
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url)
    }
}

/// Evidence badge: the text carries the meaning, colour is secondary (PRD §6.2).
struct Badge: View {
    let kind: String
    let detail: String

    var body: some View {
        HStack(spacing: 6) {
            Text(kind).font(.caption2.weight(.bold))
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(Color(nsColor: accent).opacity(kind == "OBSERVED" ? 1 : 0.5), in: .rect(cornerRadius: 3))
                .foregroundStyle(.white)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
