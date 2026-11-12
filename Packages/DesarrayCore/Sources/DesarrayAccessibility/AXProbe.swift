import ApplicationServices
import CoreGraphics
import DesarrayGeometry
import Foundation

public struct AXNode: Codable, Equatable, Sendable {
    public var id: Int
    public var parent: Int?
    public var role: String
    public var subrole: String?
    /// AXTitle or AXDescription only. AXValue (text-field contents) is never read (PRD §11.2).
    public var title: String?
    /// Global top-left points, as reported by AX. Not guaranteed to equal painted bounds.
    public var frame: CGRect
}

public struct XRaySnapshot: Codable, Equatable, Sendable {
    public enum Status: Codable, Equatable, Sendable {
        case ok
        case notTrusted
        case noWindow
        /// Budget hit (nodes/time); `nodes` is a usable prefix.
        case partial(String)
    }

    public var rect: CGRect
    public var appName: String?
    public var bundlePID: Int32?
    public var windowFrame: CGRect?
    public var nodes: [AXNode]
    public var status: Status
    public var elapsedMs: Int
    public var capturedAt: Date

    public var boxes: [XBox] {
        nodes.map { XBox(id: $0.id, parent: $0.parent, frame: $0.frame, role: $0.role, label: $0.title) }
    }
}

public struct AXBudget: Sendable {
    public var maxNodes = 2500
    public var maxDepth = 60
    public var maxSeconds = 0.15
    public var messagingTimeout: Float = 0.05

    public init() {}
    public static let live = AXBudget()
    public static var capture: AXBudget { var b = AXBudget(); b.maxNodes = 8000; b.maxSeconds = 1.5; b.messagingTimeout = 0.25; return b }
}

public enum AXProbe {
    public static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system Accessibility prompt (asynchronous; returns current state).
    @discardableResult
    public static func requestTrust() -> Bool {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// Elements of the topmost foreign window under `rect`, pruned to frames intersecting `rect`.
    /// Blocking; call off the main thread.
    public static func snapshot(of rect: CGRect, excludingPID: pid_t, budget: AXBudget = .live) -> XRaySnapshot {
        let start = Date()
        func done(_ nodes: [AXNode], _ status: XRaySnapshot.Status, app: String? = nil, pid: pid_t? = nil, window: CGRect? = nil) -> XRaySnapshot {
            XRaySnapshot(rect: rect, appName: app, bundlePID: pid, windowFrame: window, nodes: nodes, status: status,
                         elapsedMs: Int(Date().timeIntervalSince(start) * 1000), capturedAt: start)
        }
        guard isTrusted else { return done([], .notTrusted) }
        guard let target = topWindow(under: rect, excludingPID: excludingPID) else { return done([], .noWindow) }

        let app = AXUIElementCreateApplication(target.pid)
        AXUIElementSetMessagingTimeout(app, budget.messagingTimeout)
        // Chromium/Electron only build their web AX tree when asked. Harmless elsewhere.
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)

        let root = matchingWindow(of: app, frame: target.bounds) ?? app
        var nodes: [AXNode] = []
        var stack: [(AXUIElement, Int?, Int)] = [(root, nil, 0)]
        let deadline = start.addingTimeInterval(budget.maxSeconds)
        var status: XRaySnapshot.Status = .ok

        while let (el, parent, depth) = stack.popLast() {
            if nodes.count >= budget.maxNodes { status = .partial("node budget \(budget.maxNodes)"); break }
            if Date() > deadline { status = .partial("time budget \(Int(budget.maxSeconds * 1000))ms"); break }
            let a = attributes(of: el)
            var myID = parent
            if let frame = a.frame, frame.width > 0, frame.height > 0 {
                // Prune whole subtrees that are off the selection (children sit inside parents in practice).
                if depth > 0 && !frame.intersects(rect) { continue }
                myID = nodes.count
                nodes.append(AXNode(id: nodes.count, parent: parent, role: a.role ?? "AXUnknown",
                                    subrole: a.subrole, title: a.title, frame: frame))
            }
            if depth < budget.maxDepth {
                for child in a.children.reversed() { stack.append((child, myID, depth + 1)) }
            }
        }
        return done(nodes, status, app: target.name, pid: target.pid, window: target.bounds)
    }

    // MARK: internals

    private struct WindowInfo { let pid: pid_t; let name: String?; let bounds: CGRect }

    /// Front-to-back CG window list; first normal-layer window not owned by us that contains the
    /// selection centre (fallback: largest overlap). This skips desarray's own overlay panels.
    private static func topWindow(under rect: CGRect, excludingPID: pid_t) -> WindowInfo? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return nil }
        let windows: [WindowInfo] = list.compactMap { w in
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  let pid = w[kCGWindowOwnerPID as String] as? pid_t, pid != excludingPID,
                  (w[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let dict = w[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict) else { return nil }
            return WindowInfo(pid: pid, name: w[kCGWindowOwnerName as String] as? String, bounds: bounds)
        }
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        if let hit = windows.first(where: { $0.bounds.contains(centre) }) { return hit }
        return windows.max { area($0.bounds.intersection(rect)) < area($1.bounds.intersection(rect)) }
            .flatMap { area($0.bounds.intersection(rect)) > 0 ? $0 : nil }
    }

    private static func area(_ r: CGRect) -> CGFloat { r.isNull ? 0 : r.width * r.height }

    private static func matchingWindow(of app: AXUIElement, frame: CGRect) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return nil }
        return windows.min { distance(attributes(of: $0).frame, frame) < distance(attributes(of: $1).frame, frame) }
    }

    private static func distance(_ a: CGRect?, _ b: CGRect) -> CGFloat {
        guard let a else { return .greatestFiniteMagnitude }
        return abs(a.minX - b.minX) + abs(a.minY - b.minY) + abs(a.width - b.width) + abs(a.height - b.height)
    }

    private struct Attrs { var role, subrole, title: String?; var frame: CGRect?; var children: [AXUIElement] = [] }

    private static let names: [String] = [kAXRoleAttribute, kAXSubroleAttribute, kAXTitleAttribute, kAXDescriptionAttribute,
                                kAXPositionAttribute, kAXSizeAttribute, kAXChildrenAttribute]

    /// One IPC round trip per element instead of seven.
    private static func attributes(of el: AXUIElement) -> Attrs {
        var out: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(el, names as CFArray, AXCopyMultipleAttributeOptions(rawValue: 0), &out) == .success,
              let values = out as? [AnyObject], values.count == 7 else { return Attrs() }
        func string(_ i: Int) -> String? { (values[i] as? String).flatMap { $0.isEmpty ? nil : $0 } }
        func axValue<T>(_ i: Int, _ type: AXValueType, _ empty: T) -> T? {
            let v = values[i]
            guard CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
            var result = empty
            return AXValueGetValue(v as! AXValue, type, &result) ? result : nil
        }
        var a = Attrs()
        a.role = string(0)
        a.subrole = string(1)
        a.title = string(2) ?? string(3)
        if let p = axValue(4, .cgPoint, CGPoint.zero), let s = axValue(5, .cgSize, CGSize.zero) {
            a.frame = CGRect(origin: p, size: s)
        }
        a.children = values[6] as? [AXUIElement] ?? []
        return a
    }
}
