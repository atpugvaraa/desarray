import CoreGraphics
import Foundation
import ScreenCaptureKit

public enum ScreenGrabError: Error, CustomStringConvertible, Sendable {
    case notAuthorized
    case displayUnavailable
    case failed(String)

    public var description: String {
        switch self {
        case .notAuthorized: "Screen Recording permission is off for desarray. Turn it on in System Settings › Privacy & Security › Screen & System Audio Recording, then capture again."
        case .displayUnavailable: "That display is no longer available."
        case .failed(let s): "Capture failed: \(s)"
        }
    }
}

public enum ScreenGrab {
    /// One-shot capture of `rect` (global top-left points) on display `displayID`, excluding every
    /// window owned by `excludingPID` (desarray's overlay/HUD). Asks for permission only if `prompt`.
    public static func capture(rect: CGRect, displayID: CGDirectDisplayID, displayOrigin: CGPoint, scale: CGFloat,
                               excludingPID: pid_t, prompt: Bool) async -> Result<CGImage, ScreenGrabError> {
        guard CGPreflightScreenCaptureAccess() else {
            if prompt { CGRequestScreenCaptureAccess() }
            return .failure(.notAuthorized)
        }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                return .failure(.displayUnavailable)
            }
            let ours = content.applications.filter { $0.processID == excludingPID }
            let filter = SCContentFilter(display: display, excludingApplications: ours, exceptingWindows: [])
            let config = SCStreamConfiguration()
            config.sourceRect = rect.offsetBy(dx: -displayOrigin.x, dy: -displayOrigin.y) // display-local points
            config.width = Int((rect.width * scale).rounded())
            config.height = Int((rect.height * scale).rounded())
            config.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            return .success(image)
        } catch {
            return .failure(.failed(error.localizedDescription))
        }
    }
}
