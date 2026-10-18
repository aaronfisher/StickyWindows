import AppKit
@preconcurrency import ScreenCaptureKit
import os

/// Captures window thumbnails with ScreenCaptureKit. Only works with Screen Recording access; without it
/// everything returns nil and Sticky Windows falls back to icon + title. Never prompts.
@MainActor
final class ThumbnailProvider {
    private let log = Logger(subsystem: AppIdentity.id, category: "thumbnails")
    /// Longest side of a thumbnail, in pixels (Retina-sharp at the preview's ~280 pt).
    private let maxPixels: CGFloat = 640

    var isAvailable: Bool { CGPreflightScreenCaptureAccess() }

    func capture(windowID: CGWindowID) async -> NSImage? {
        guard isAvailable else { return nil }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else { return nil }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            let scale = min(1, maxPixels / max(window.frame.width, window.frame.height)) * 2
            config.width = max(1, Int(window.frame.width * scale))
            config.height = max(1, Int(window.frame.height * scale))
            config.showsCursor = false
            config.ignoreShadowsSingleWindow = true
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            return NSImage(cgImage: image, size: NSSize(width: window.frame.width, height: window.frame.height))
        } catch {
            log.debug("Thumbnail capture failed for \(windowID): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
