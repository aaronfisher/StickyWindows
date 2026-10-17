import AppKit
import Observation

enum Edge: String, Codable, CaseIterable {
    case left, right, bottom

    var isVertical: Bool { self != .bottom }
}

enum HidingMethod: String, Codable {
    /// Move the window just past the parked edge.
    case offscreen
    /// Minimize to the Dock; used when an app clamps offscreen positions.
    case minimize
}

@MainActor
@Observable
final class ParkedWindow: Identifiable {
    let id = UUID()
    let window: WindowController
    let bundleID: String?
    let appName: String
    let icon: NSImage?
    var title: String
    let edge: Edge
    let displayID: CGDirectDisplayID?

    /// Where the window goes when revealed, in AX coordinates. Updated when it's tucked away again.
    var storedFrame: CGRect
    /// Preferred tab position along the edge, in AX coordinates (y for side edges, x for bottom).
    var desiredOffset: CGFloat
    var hiddenBy: HidingMethod?
    var isRevealed: Bool { hiddenBy == nil }

    init(window: WindowController, app: NSRunningApplication?, frame: CGRect, edge: Edge, screen: NSScreen?, offset: CGFloat? = nil) {
        self.window = window
        bundleID = app?.bundleIdentifier
        appName = app?.localizedName ?? "Window"
        icon = app?.icon
        title = window.title.flatMap { $0.isEmpty ? nil : $0 } ?? appName
        self.edge = edge
        displayID = screen.flatMap(ScreenGeometry.displayID(of:))
        storedFrame = frame
        desiredOffset = offset ?? (edge.isVertical ? frame.midY : frame.midX)
    }
}
