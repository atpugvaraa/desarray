// Dev probe: run the real AX → layout → capture → render pipeline on a screen rect.
// Usage: desarray-probe <x> <y> <w> <h> <out.png>   (global top-left points, main display)
import CoreGraphics
import DesarrayAccessibility
import DesarrayCapture
import DesarrayGeometry
import DesarrayRender
import Foundation
import ImageIO
import UniformTypeIdentifiers

let a = CommandLine.arguments
guard a.count == 6, let x = Double(a[1]), let y = Double(a[2]), let w = Double(a[3]), let h = Double(a[4]) else {
    print("usage: desarray-probe x y w h out.png"); exit(2)
}
let rect = CGRect(x: x, y: y, width: w, height: h)
let out = URL(fileURLWithPath: a[5])

// Run twice: Chromium/Electron builds its AX tree lazily after AXManualAccessibility is set.
_ = AXProbe.snapshot(of: rect, excludingPID: getpid(), budget: .capture)
Thread.sleep(forTimeInterval: Double(ProcessInfo.processInfo.environment["WAIT"] ?? "0.3")!)
let snap = AXProbe.snapshot(of: rect, excludingPID: getpid(), budget: .capture)
let layout = xrayLayout(snap.boxes, in: rect)
print("app=\(snap.appName ?? "-") status=\(snap.status) nodes=\(snap.nodes.count) kept=\(layout.boxes.count) spacings=\(layout.spacings.count) ax=\(snap.elapsedMs)ms")
for (role, n) in Dictionary(grouping: layout.boxes, by: \.role).mapValues(\.count).sorted(by: { $0.value > $1.value }).prefix(8) {
    print("  \(role) ×\(n)")
}
if ProcessInfo.processInfo.environment["DUMP"] != nil { for n in snap.nodes { print("   #\(n.id)<\(n.parent ?? -1) \(n.role) \(n.subrole ?? "") \(n.frame)") } }
for s in layout.spacings.prefix(12) { print("  \(s.kind) \(s.axis) \(num(s.value))") }

let id = CGMainDisplayID()
let scale = CGFloat(CGDisplayCopyDisplayMode(id)?.pixelWidth ?? 1) / CGDisplayBounds(id).width
let sem = DispatchSemaphore(value: 0)
nonisolated(unsafe) var image: CGImage?
Task.detached {
    switch await ScreenGrab.capture(rect: rect, displayID: id, displayOrigin: .zero, scale: scale, excludingPID: getpid(), prompt: false) {
    case .success(let i): image = i; print("capture \(i.width)x\(i.height)px")
    case .failure(let e): print("capture: \(e)")
    }
    sem.signal()
}
sem.wait()

guard let composite = XRayRenderer.composite(image: image, selection: rect, layout: layout, scale: scale, options: XRayOptions(gridStep: 4)),
      let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil) else { exit(1) }
CGImageDestinationAddImage(dest, composite, nil)
CGImageDestinationFinalize(dest)
print("wrote \(out.path)")
