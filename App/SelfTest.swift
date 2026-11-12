#if DEBUG
import AppKit
import DesarrayGeometry

/// DEBUG-only end-to-end check: `desarray.app/Contents/MacOS/desarray -selftest <outdir>`.
/// Drives the real overlay view with synthetic events (no global input), renders overlay +
/// HUD + capture window to PNG, prints PASS/FAIL lines, then exits. Global hotkey is NOT covered.
enum SelfTest {
    static func runIfRequested(session: Session) {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "-selftest"), i + 1 < args.count else { return }
        let out = URL(fileURLWithPath: args[i + 1])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { run(session, out) }
    }

    private static var failures = 0
    private static func check(_ name: String, _ ok: Bool) {
        print("\(ok ? "PASS" : "FAIL") \(name)")
        if !ok { failures += 1 }
    }

    private static func run(_ session: Session, _ out: URL) {
        session.promptsForPermissions = false // never pop system dialogs from a test
        session.start()
        check("session active", session.isActive)
        let overlays = NSApp.windows.compactMap { $0.contentView as? OverlayView }.filter { $0.window?.isVisible == true }
        check("one overlay per screen (\(overlays.count)/\(NSScreen.screens.count))", overlays.count == NSScreen.screens.count)
        guard let view = overlays.first, let window = view.window else { return finish() }

        // Drag bottom-right → top-left (reverse direction) in view-local top-left points.
        func send(_ type: NSEvent.EventType, _ local: CGPoint) {
            let inWindow = view.convert(local, to: nil)
            let e = NSEvent.mouseEvent(with: type, location: inWindow, modifierFlags: [], timestamp: 0,
                                       windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                       clickCount: 1, pressure: 1)!
            switch type {
            case .leftMouseDown: view.mouseDown(with: e)
            case .leftMouseDragged: view.mouseDragged(with: e)
            default: view.mouseUp(with: e)
            }
        }
        send(.leftMouseDown, CGPoint(x: 500, y: 400))
        send(.leftMouseDragged, CGPoint(x: 300, y: 300))
        send(.leftMouseDragged, CGPoint(x: 260, y: 252))
        send(.leftMouseUp, CGPoint(x: 260, y: 252))
        let expected = CGRect(x: view.display.frame.minX + 260, y: view.display.frame.minY + 252, width: 240, height: 148)
        check("reverse drag → \(session.selection.map { "\($0.rect)" } ?? "nil")", session.selection?.rect == expected)
        check("provenance observed/selectionGeometry/pt",
              session.selection?.provenance.kind == .observed && session.selection?.provenance.unit == "pt")

        // Drag past the display edge → clipped and disclosed.
        send(.leftMouseDown, CGPoint(x: view.bounds.width - 50, y: 100))
        send(.leftMouseDragged, CGPoint(x: view.bounds.width + 200, y: 160))
        send(.leftMouseUp, CGPoint(x: view.bounds.width + 200, y: 160))
        check("off-edge drag clipped", session.selection?.clipped == true && session.selection?.rect.maxX == view.display.frame.maxX)

        // Tiny click clears selection.
        send(.leftMouseDown, CGPoint(x: 900, y: 600))
        send(.leftMouseUp, CGPoint(x: 900.5, y: 600.5))
        check("click (<2pt) leaves no selection", session.selection == nil)

        // Recreate, then move via drag inside, then keyboard nudge + resize.
        send(.leftMouseDown, CGPoint(x: 260, y: 252)); send(.leftMouseDragged, CGPoint(x: 500, y: 400)); send(.leftMouseUp, CGPoint(x: 500, y: 400))
        send(.leftMouseDown, CGPoint(x: 300, y: 300)); send(.leftMouseDragged, CGPoint(x: 340, y: 320)); send(.leftMouseUp, CGPoint(x: 340, y: 320))
        check("move keeps size", session.selection?.rect.size == CGSize(width: 240, height: 148)
              && session.selection?.rect.minX == view.display.frame.minX + 300)
        session.nudge(dx: 0, dy: 10, resize: false)
        session.nudge(dx: 4, dy: 4, resize: true)
        check("nudge + resize", session.selection?.rect.size == CGSize(width: 244, height: 152))

        session.grid = .pt4
        snapshot(view, to: out.appendingPathComponent("overlay.png"))
        let hud = NSApp.windows.first { $0.level.rawValue == NSWindow.Level.screenSaver.rawValue + 1 && $0.isVisible }
        if let hud, let sel = session.selection {
            let hudTop = session.space.flip(hud.frame).minY
            check("HUD visible above overlay, below selection", hud.level.rawValue > window.level.rawValue && hudTop >= sel.rect.maxY)
            grab(hud, to: out.appendingPathComponent("hud.png"))
        } else { check("HUD exists", false) }

        // Keys: G cycles grid, X toggles x-ray.
        func key(_ code: UInt16, _ ch: String) {
            view.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                windowNumber: window.windowNumber, context: nil, characters: ch,
                                                charactersIgnoringModifiers: ch, isARepeat: false, keyCode: code)!)
        }
        key(5, "g"); check("G cycles grid 4pt → 4px", session.grid == .px4)
        key(5, "g"); key(5, "g"); check("G wraps back to 4pt", session.grid == .pt4)
        key(7, "x"); check("X turns x-ray off", !session.showXRay)
        key(7, "x"); check("X turns x-ray on", session.showXRay)

        // Escape: first clears, second ends session and removes overlays.
        let esc = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                   windowNumber: window.windowNumber, context: nil, characters: "\u{1b}",
                                   charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
        view.keyDown(with: esc)
        check("esc #1 clears selection, session still active", session.selection == nil && session.isActive)
        view.keyDown(with: esc)
        let visibleOverlays = NSApp.windows.filter { $0.contentView is OverlayView && $0.isVisible }.count
        check("esc #2 ends session, no overlays intercepting input", !session.isActive && visibleOverlays == 0)

        // Stress: 30 start/select/cancel/stop cycles without stuck windows.
        for _ in 0..<30 {
            session.start()
            session.select(CGRect(x: 10, y: 10, width: 40, height: 40), on: session.displays[0], requestedClip: false)
            session.escape(); session.escape()
        }
        let stuck = NSApp.windows.filter { $0.contentView is OverlayView && $0.isVisible }.count
        check("30 cycles, 0 stuck overlays (\(stuck))", stuck == 0 && !session.isActive)

        // Capture (⏎ path): opens the capture window and ends the live session.
        session.start()
        session.select(CGRect(x: 400, y: 200, width: 420, height: 300), on: session.displays[0], requestedClip: false)
        session.capture()
        // Yield to the main actor (a nested RunLoop spin would starve the capture Task).
        Task { @MainActor in
            var cap: NSWindow?
            for _ in 0..<100 where cap == nil {
                try? await Task.sleep(for: .milliseconds(100))
                cap = NSApp.windows.first { $0.title.hasPrefix("desarray. —") && $0.isVisible }
            }
            check("capture window opened", cap != nil)
            check("capture ended live session, overlays gone",
                  !session.isActive && NSApp.windows.filter { $0.contentView is OverlayView && $0.isVisible }.isEmpty)
            if let cap {
                try? await Task.sleep(for: .milliseconds(800))
                grab(cap, to: out.appendingPathComponent("capture.png"))
            }
            finish()
        }
    }

    /// cacheDisplay misses SwiftUI text layers; capture the composited window instead.
    private static func grab(_ w: NSWindow, to url: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-x", "-o", "-l", "\(w.windowNumber)", url.path]
        try? p.run(); p.waitUntilExit()
        print("wrote \(url.lastPathComponent) (status \(p.terminationStatus))")
    }

    private static func snapshot(_ view: NSView, to url: URL) {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        print("wrote \(url.path)")
    }

    private static func finish() {
        print(failures == 0 ? "SELFTEST OK" : "SELFTEST FAILED (\(failures))")
        exit(failures == 0 ? 0 : 1)
    }
}
#endif
