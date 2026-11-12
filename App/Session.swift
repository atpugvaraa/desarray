import AppKit
import DesarrayAccessibility
import DesarrayCapture
import DesarrayDomain
import DesarrayGeometry
import Observation

/// Owns the live inspection session: selection, live AX x-ray, overlay + HUD windows, capture.
@Observable
final class Session {
    private(set) var isActive = false
    var selection: Selection? {
        didSet {
            overlay.redraw()
            hud.reposition()
            if oldValue?.rect != selection?.rect { refreshXRay() }
        }
    }
    var grid: GridUnit = .pt4 { didSet { overlay.redraw() } }
    var showXRay = true { didSet { overlay.redraw(); refreshXRay() } }
    private(set) var snapshot: XRaySnapshot?
    private(set) var layout: XRayLayout = .empty
    private(set) var axTrusted = AXProbe.isTrusted
    private(set) var capturing = false
    private(set) var displays: [DisplayInfo] = []
    private(set) var space = ScreenSpace(primaryHeight: 0)
    var hotKeyStatus: String?
    /// Off only for the DEBUG self-test, so it never triggers system prompts.
    @ObservationIgnored var promptsForPermissions = true

    @ObservationIgnored private lazy var overlay = OverlayController(session: self)
    @ObservationIgnored private lazy var hud = HUDController(session: self)
    @ObservationIgnored private var hotKey: HotKey?
    @ObservationIgnored private var liveTimer: Timer?
    @ObservationIgnored private var axInFlight = false

    init() {
        do {
            hotKey = try HotKey(keyCode: HotKey.keyD, modifiers: HotKey.optionShift) { [weak self] in self?.toggle() }
        } catch {
            hotKeyStatus = "⌥⇧D unavailable (\(error)). Use the menu."
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.topologyChanged() } }
        #if DEBUG
        SelfTest.runIfRequested(session: self)
        #endif
    }

    func toggle() { isActive ? stop() : start() }

    func start() {
        guard !isActive else { return }
        snapshotDisplays()
        isActive = true
        axTrusted = AXProbe.isTrusted
        if !axTrusted && promptsForPermissions { AXProbe.requestTrust() }
        overlay.show(displays: displays, space: space)
        hud.show()
        // Live x-ray: bounded polling only while a session is open (PRD §10.2 — AX notifications don't
        // cover hover/animation repaint in arbitrary apps). One query in flight at a time.
        liveTimer = Timer.scheduledTimer(withTimeInterval: 0.125, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshXRay() }
        }
    }

    func stop() {
        guard isActive else { return }
        isActive = false
        liveTimer?.invalidate()
        liveTimer = nil
        overlay.hide()
        hud.hide()
        layout = .empty
        snapshot = nil
    }

    /// Escape: clear the selection first, exit on the second press.
    func escape() {
        if selection != nil { selection = nil } else { stop() }
    }

    func display(id: UInt32) -> DisplayInfo? { displays.first { $0.id == id } }

    func select(_ rect: CGRect, on display: DisplayInfo, requestedClip: Bool) {
        let (r, clipped) = clip(rect, to: display)
        selection = Selection(rect: r, displayID: display.id, displayName: display.name,
                              backingScale: display.scale, clipped: clipped || requestedClip)
    }

    func nudge(dx: CGFloat, dy: CGFloat, resize: Bool) {
        guard var r = selection?.rect, let s = selection, let d = display(id: s.displayID) else { return }
        if resize {
            r.size.width = max(1, r.width + dx)
            r.size.height = max(1, r.height + dy)
        } else {
            r.origin.x += dx
            r.origin.y += dy
        }
        select(r, on: d, requestedClip: false)
    }

    func cycleGrid() {
        let all = GridUnit.allCases
        grid = all[(all.firstIndex(of: grid)! + 1) % all.count]
    }

    // MARK: live x-ray

    func refreshXRay() {
        guard isActive, showXRay, !axInFlight, let rect = selection?.rect else { return }
        axTrusted = AXProbe.isTrusted
        guard axTrusted else { layout = .empty; return }
        axInFlight = true
        let pid = getpid()
        Task.detached(priority: .userInitiated) { [weak self] in
            let snap = AXProbe.snapshot(of: rect, excludingPID: pid)
            await self?.apply(snap)
        }
    }

    private func apply(_ snap: XRaySnapshot) {
        axInFlight = false
        guard isActive, let rect = selection?.rect else { return }
        snapshot = snap
        layout = xrayLayout(snap.boxes, in: rect)
        overlay.redraw()
        hud.reposition()
    }

    // MARK: capture (⏎)

    /// Freeze the region: a full-budget AX snapshot + a ScreenCaptureKit image with desarray's own
    /// windows excluded, then open the capture window. Like ⌘⇧4, the live session ends.
    func capture() {
        guard !capturing, let sel = selection, let d = display(id: sel.displayID) else { return }
        capturing = true
        let rect = sel.rect, pid = getpid(), prompt = promptsForPermissions, grid = grid, live = snapshot
        Task { [weak self] in
            debugLog("capture: AX snapshot…")
            let snap = await Task.detached { AXProbe.isTrusted ? AXProbe.snapshot(of: rect, excludingPID: pid, budget: .capture) : nil }.value
            let grab = await ScreenGrab.capture(rect: rect, displayID: d.id, displayOrigin: d.frame.origin,
                                                scale: d.scale, excludingPID: pid, prompt: prompt)
            debugLog("capture: grab done \(grab)")
            guard let self else { return }
            self.capturing = false
            self.stop()
            let image: CGImage?, error: String?
            switch grab {
            case .success(let i): (image, error) = (i, nil)
            case .failure(let e): (image, error) = (nil, e.description)
            }
            CaptureWindow.open(CaptureModel(selection: sel, snapshot: snap ?? live, image: image, imageError: error, grid: grid))
        }
    }

    // MARK: displays

    private func snapshotDisplays() {
        let screens = NSScreen.screens
        space = ScreenSpace(primaryHeight: screens.first?.frame.height ?? 0)
        displays = screens.map { screen in
            DisplayInfo(id: screen.displayID, name: screen.localizedName,
                        frame: space.flip(screen.frame), scale: screen.backingScaleFactor)
        }
    }

    private func topologyChanged() {
        snapshotDisplays()
        if isActive { overlay.show(displays: displays, space: space); hud.reposition() }
    }
}

func debugLog(_ s: @autoclosure () -> String) {
    #if DEBUG
    if ProcessInfo.processInfo.environment["DESARRAY_DEBUG"] != nil { print(s()) }
    #endif
}

extension NSScreen {
    var displayID: UInt32 {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
