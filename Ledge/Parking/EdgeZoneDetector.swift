import AppKit

/// A screen edge the cursor is pressed against.
@MainActor
struct EdgeZone {
    let edge: Edge
    let screen: NSScreen
    /// Cursor position along the edge in AX coordinates (y for side edges, x for the bottom).
    let offset: CGFloat

    /// Same edge of the same display, regardless of where along it.
    func isSameZone(as other: EdgeZone?) -> Bool {
        guard let other else { return false }
        return edge == other.edge && screen == other.screen
    }
}

/// Hit-tests the cursor against the left, right, and bottom edges of every display.
@MainActor
struct EdgeZoneDetector {
    var band: CGFloat = 8
    var enabledEdges: Set<Edge> = Set(Edge.allCases)

    /// `point` is in AppKit coordinates (`NSEvent.mouseLocation`).
    func zone(at point: CGPoint) -> EdgeZone? {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) else { return nil }
        let frame = screen.frame
        // Side edges stop below the menu bar (and notch) so the top corners stay free.
        let menuBarHeight = frame.maxY - screen.visibleFrame.maxY
        let belowMenuBar = point.y < frame.maxY - menuBarHeight

        var candidates: [(edge: Edge, distance: CGFloat)] = []
        let left = point.x - frame.minX
        if left <= band, belowMenuBar, !hasNeighbor(of: screen, at: CGPoint(x: frame.minX - 2, y: point.y)) {
            candidates.append((.left, left))
        }
        // The cursor tops out one point short of maxX.
        let right = frame.maxX - 1 - point.x
        if right <= band, belowMenuBar, !hasNeighbor(of: screen, at: CGPoint(x: frame.maxX + 1, y: point.y)) {
            candidates.append((.right, right))
        }
        let bottom = point.y - frame.minY
        if bottom <= band, !hasNeighbor(of: screen, at: CGPoint(x: point.x, y: frame.minY - 2)) {
            candidates.append((.bottom, bottom))
        }

        guard let best = candidates.filter({ enabledEdges.contains($0.edge) }).min(by: { $0.distance < $1.distance })
        else { return nil }
        let axPoint = ScreenGeometry.axPoint(fromAppKit: point)
        return EdgeZone(edge: best.edge, screen: screen, offset: best.edge.isVertical ? axPoint.y : axPoint.x)
    }

    /// An edge shared with another display isn't an edge: the cursor just passes through it.
    private func hasNeighbor(of screen: NSScreen, at point: CGPoint) -> Bool {
        NSScreen.screens.contains { $0 != screen && NSMouseInRect(point, $0.frame, false) }
    }
}
