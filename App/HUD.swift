import AppKit
import DesarrayAccessibility
import DesarrayGeometry
import DesarrayRender
import SwiftUI

/// Small toolbar that follows the selection (like the ⌘⇧5 bar). Sits above the overlay.
final class HUDController {
    private unowned let session: Session
    private lazy var panel: NSPanel = {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isReleasedWhenClosed = false
        p.becomesKeyOnlyIfNeeded = true
        p.level = NSWindow.Level(NSWindow.Level.screenSaver.rawValue + 1)
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let host = NSHostingView(rootView: HUDView(session: session))
        host.sizingOptions = [.intrinsicContentSize]
        p.contentView = host
        return p
    }()

    init(session: Session) { self.session = session }

    func show() {
        reposition()
        panel.orderFrontRegardless()
    }

    func hide() { panel.orderOut(nil) }

    /// Below the selection (clear of its size pill), flipped above when there's no room; top-centre when no selection.
    func reposition() {
        guard session.isActive else { return }
        let size = panel.contentView?.fittingSize ?? CGSize(width: 480, height: 40)
        let space = session.space
        let anchorDisplay = session.selection.flatMap { session.display(id: $0.displayID) } ?? session.displays.first
        guard let d = anchorDisplay else { return }
        var topLeft: CGPoint // canonical (global top-left points)
        if let r = session.selection?.rect {
            topLeft = CGPoint(x: r.midX - size.width / 2, y: r.maxY + 30)
            if topLeft.y + size.height > d.frame.maxY - 8 { topLeft.y = r.minY - size.height - 12 }
            if topLeft.y < d.frame.minY + 8 { topLeft.y = r.maxY - size.height - 12 } // tall selection: inside bottom
        } else {
            topLeft = CGPoint(x: d.frame.midX - size.width / 2, y: d.frame.minY + 60)
        }
        topLeft.x = min(max(d.frame.minX + 8, topLeft.x), d.frame.maxX - size.width - 8)
        let cocoa = space.flip(CGRect(origin: topLeft, size: size))
        panel.setFrame(cocoa, display: true)
    }
}

struct HUDView: View {
    @Bindable var session: Session

    var body: some View {
        HStack(spacing: 10) {
            status
            Divider().frame(height: 18)
            Picker("Grid", selection: $session.grid) {
                ForEach(GridUnit.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            .help("Grid (G)")
            Toggle("X-ray", isOn: $session.showXRay)
                .toggleStyle(.button)
                .help("Toggle element x-ray (X)")
            Button {
                session.capture()
            } label: {
                Label(session.capturing ? "Capturing…" : "Capture", systemImage: "camera.viewfinder")
            }
            .buttonStyle(.borderedProminent)
            .disabled(session.selection == nil || session.capturing)
            .help("Freeze and open the full x-ray (⏎)")
            Button {
                session.stop()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Exit (Esc Esc)")
            .accessibilityLabel("Exit inspection")
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: .rect(cornerRadius: 10))
        .environment(\.colorScheme, .dark)
        .fixedSize()
    }

    @ViewBuilder private var status: some View {
        if !session.axTrusted {
            Button("Enable Accessibility for x-ray") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
            .buttonStyle(.link)
        } else if let r = session.selection?.rect {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(num(r.width)) × \(num(r.height)) pt").font(.system(.callout, design: .monospaced).weight(.semibold))
                Text(xrayLine).font(.caption2).foregroundStyle(.secondary)
            }
        } else {
            Text("Drag over any UI").font(.callout)
        }
    }

    private var xrayLine: String {
        guard session.showXRay else { return "x-ray off" }
        guard let s = session.snapshot else { return "reading…" }
        switch s.status {
        case .noWindow: return "no window under frame"
        case .notTrusted: return "Accessibility off"
        default:
            let partial = if case .partial = s.status { " · partial" } else { "" }
            return "\(s.appName ?? "?") · \(session.layout.boxes.count) elements · \(s.elapsedMs) ms\(partial)"
        }
    }
}
