// Phase 0 spike (throwaway). Run: swift Spikes/coords.swift
// Compares pointer location across AppKit (bottom-left) and CoreGraphics (top-left),
// reports display topology, checks AX trust and screen-capture preflight WITHOUT prompting,
// and, if AX-trusted, hit-tests the element under the pointer.
import AppKit
import ApplicationServices
import CoreGraphics

print("== Display topology ==")
let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
for s in NSScreen.screens {
    let id = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
    let cg = CGDisplayBounds(id)
    print("display \(id) name=\(s.localizedName) cocoaFrame=\(s.frame) cgBounds=\(cg) scale=\(s.backingScaleFactor) rotation=\(CGDisplayRotation(id))")
    // Cross-check: Cocoa frame flipped by primary height should equal CG bounds.
    let flippedY = primaryHeight - s.frame.maxY
    print("  flip check: cocoa->topLeft origin = (\(s.frame.minX), \(flippedY)) vs CG (\(cg.minX), \(cg.minY)) -> \(flippedY == cg.minY && s.frame.minX == cg.minX ? "MATCH" : "MISMATCH")")
}

print("\n== Pointer ==")
let cocoa = NSEvent.mouseLocation
let cgPoint = CGEvent(source: nil)?.location ?? .zero
print("NSEvent.mouseLocation (bottom-left) = \(cocoa)")
print("CGEvent.location (top-left)         = \(cgPoint)")
print("flip(cocoa) = (\(cocoa.x), \(primaryHeight - cocoa.y)) -> \(abs(primaryHeight - cocoa.y - cgPoint.y) < 1 ? "MATCH" : "MISMATCH")")

print("\n== Permissions (no prompt) ==")
let trusted = AXIsProcessTrusted()
print("AXIsProcessTrusted = \(trusted)")
print("CGPreflightScreenCaptureAccess = \(CGPreflightScreenCaptureAccess())")

if trusted {
    print("\n== AX hit-test at CG point ==")
    let sys = AXUIElementCreateSystemWide()
    AXUIElementSetMessagingTimeout(sys, 0.25)
    var el: AXUIElement?
    let t0 = Date()
    let err = AXUIElementCopyElementAtPosition(sys, Float(cgPoint.x), Float(cgPoint.y), &el)
    print("err=\(err.rawValue) in \(Int(Date().timeIntervalSince(t0) * 1000))ms")
    if let el {
        func attr(_ name: String) -> CFTypeRef? { var v: CFTypeRef?; AXUIElementCopyAttributeValue(el, name as CFString, &v); return v }
        var pos = CGPoint.zero, size = CGSize.zero
        if let p = attr(kAXPositionAttribute) { AXValueGetValue(p as! AXValue, .cgPoint, &pos) }
        if let z = attr(kAXSizeAttribute) { AXValueGetValue(z as! AXValue, .cgSize, &size) }
        print("role=\(attr(kAXRoleAttribute) ?? "nil" as CFString) frame=\(CGRect(origin: pos, size: size))")
        print("pointer inside AX frame (top-left space)? \(CGRect(origin: pos, size: size).contains(cgPoint))")
    }
}
