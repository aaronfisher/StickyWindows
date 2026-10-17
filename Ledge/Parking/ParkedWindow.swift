import AppKit
import Observation

enum Edge: String, Codable, CaseIterable {
    case left, right, bottom

    var isVertical: Bool { self != .bottom }

    var displayName: String {
        switch self {
        case .left: "Left"
        case .right: "Right"
        case .bottom: "Bottom"
        }
    }
}

enum HidingMethod: String, Codable {
    /// Move the window just past the parked edge.
    case offscreen
    /// Minimize to the Dock; used when an app clamps offscreen positions.
    case minimize
}

enum RevealMode: String, Codable, CaseIterable {
    /// Stays out until the tab is clicked again or the window is dragged off.
    case popOut
    /// Tucks itself back when the window loses focus or the cursor leaves it.
    case peek

    var displayName: String {
        switch self {
        case .popOut: "Pop-out"
        case .peek: "Peek"
        }
    }
}

/// How a revealed window came out, which decides when it goes back.
struct RevealSession {
    enum Trigger {
        case click
        case hover
    }

    var trigger: Trigger
    let revealedAt = Date()
    /// Cursor-leave only counts once the cursor has actually been over the window.
    var cursorEnteredWindow = false
    var cursorOutsideSince: Date?
    /// App to hand focus back to after a hover peek.
    var previousApp: NSRunningApplication?
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
    var edge: Edge
    var displayID: CGDirectDisplayID?

    /// Where the window goes when revealed, in AX coordinates. Updated when it's tucked away again.
    var storedFrame: CGRect
    /// Preferred tab position along the edge, in AX coordinates (y for side edges, x for bottom).
    var desiredOffset: CGFloat
    var hiddenBy: HidingMethod?
    var isRevealed: Bool { hiddenBy == nil }

    /// Per-tab override; nil follows the global default.
    var mode: RevealMode?
    var session: RevealSession?
    /// Set while a tuck is in flight so it isn't started twice.
    var isTransitioning = false

    // Tab UI state.
    var isHovered = false
    var isDragging = false
    var isPulledAway = false

    init(
        window: WindowController, app: NSRunningApplication?, frame: CGRect, edge: Edge, screen: NSScreen?,
        offset: CGFloat? = nil
    ) {
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
