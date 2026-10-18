import AppKit

/// Converts between AppKit screen space (bottom-left origin) and AX/CG space (top-left origin of the primary display).
@MainActor
enum ScreenGeometry {
    private static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    /// Flips a rect between AppKit and AX coordinates. The flip is its own inverse.
    static func flip(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static func axPoint(fromAppKit point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }

    static func axFrame(of screen: NSScreen) -> CGRect { flip(screen.frame) }
    static func axVisibleFrame(of screen: NSScreen) -> CGRect { flip(screen.visibleFrame) }

    /// The screen showing the largest part of an AX-space rect.
    static func screen(containing axRect: CGRect) -> NSScreen? {
        let best = NSScreen.screens.max { area(axFrame(of: $0).intersection(axRect)) < area(axFrame(of: $1).intersection(axRect)) }
        if let best, area(axFrame(of: best).intersection(axRect)) > 0 { return best }
        return NSScreen.main ?? NSScreen.screens.first
    }

    /// Whether any meaningful part of an AX-space rect is on a display.
    static func isVisible(_ axRect: CGRect, minimumOverlap: CGFloat = 20) -> Bool {
        NSScreen.screens.contains { screen in
            let overlap = axFrame(of: screen).intersection(axRect)
            return !overlap.isNull && overlap.width >= minimumOverlap && overlap.height >= minimumOverlap
        }
    }

    /// Whether no more than a sliver (`tolerance` points in either direction) of an AX-space rect is on any display.
    static func isEssentiallyOffscreen(_ axRect: CGRect, tolerance: CGFloat = 4) -> Bool {
        NSScreen.screens.allSatisfy { screen in
            let overlap = axFrame(of: screen).intersection(axRect)
            return overlap.isNull || overlap.width <= tolerance || overlap.height <= tolerance
        }
    }

    /// The frame itself if a usable part of it is on a display; otherwise the same size centered on the main display.
    static func fitted(_ axRect: CGRect) -> CGRect {
        if isVisible(axRect, minimumOverlap: 60) { return axRect }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return axRect }
        let visible = axVisibleFrame(of: screen)
        let size = CGSize(width: min(axRect.width, visible.width), height: min(axRect.height, visible.height))
        return CGRect(
            x: visible.midX - size.width / 2, y: visible.midY - size.height / 2, width: size.width, height: size.height)
    }

    static func intersectsAnyScreen(_ axRect: CGRect) -> Bool {
        NSScreen.screens.contains { area(axFrame(of: $0).intersection(axRect)) > 0 }
    }

    static var axUnion: CGRect {
        NSScreen.screens.map(axFrame(of:)).reduce(CGRect.null) { $0.union($1) }
    }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    static func screen(withDisplayID id: CGDirectDisplayID?) -> NSScreen? {
        NSScreen.screens.first { displayID(of: $0) == id } ?? NSScreen.main ?? NSScreen.screens.first
    }

    private static func area(_ rect: CGRect) -> CGFloat {
        rect.isNull ? 0 : rect.width * rect.height
    }
}
