import AppKit
import SwiftUI

/// Keeps one `TabPanel` per parked window and lays them out along their edges without overlap.
@MainActor
final class TabPresenter {
    private unowned let manager: ParkingManager
    private var panels: [UUID: TabPanel] = [:]
    private let gap: CGFloat = 6

    init(manager: ParkingManager) {
        self.manager = manager
    }

    func sync() {
        let live = Set(manager.parked.map(\.id))
        for (id, panel) in panels where !live.contains(id) {
            panel.orderOut(nil)
            panels[id] = nil
        }
        for parkedWindow in manager.parked where panels[parkedWindow.id] == nil {
            let view = EdgeTabView(parkedWindow: parkedWindow) { [weak manager] in
                guard let manager else { return }
                Task { await manager.toggle(parkedWindow) }
            }
            panels[parkedWindow.id] = TabPanel(rootView: view)
        }
        layout()
    }

    func layout() {
        let groups = Dictionary(grouping: manager.parked) { GroupKey(displayID: $0.displayID, edge: $0.edge) }
        for (key, windows) in groups {
            guard let screen = ScreenGeometry.screen(withDisplayID: key.displayID) else { continue }
            layout(windows, on: screen, edge: key.edge)
        }
    }

    private func layout(_ windows: [ParkedWindow], on screen: NSScreen, edge: Edge) {
        let full = ScreenGeometry.axFrame(of: screen)
        let visible = ScreenGeometry.axVisibleFrame(of: screen)
        let length = EdgeTabView.length
        let thickness = EdgeTabView.thickness
        let (lower, upper) = edge.isVertical ? (visible.minY, visible.maxY) : (visible.minX, visible.maxX)

        // Each tab starts centered on its window, then gets pushed along to avoid the one before it.
        let sorted = windows.sorted { $0.desiredOffset < $1.desiredOffset }
        var starts: [CGFloat] = []
        for window in sorted {
            let wanted = window.desiredOffset - length / 2
            let afterPrevious = starts.last.map { $0 + length + gap } ?? lower
            starts.append(max(wanted, afterPrevious, lower))
        }
        // If the stack runs off the end, slide the whole tail back.
        if let last = starts.last, last + length > upper {
            var limit = upper - length
            for index in starts.indices.reversed() where starts[index] > limit {
                starts[index] = max(limit, lower)
                limit -= length + gap
            }
        }

        for (window, start) in zip(sorted, starts) {
            let axFrame: CGRect = switch edge {
            case .right: CGRect(x: full.maxX - thickness, y: start, width: thickness, height: length)
            case .left: CGRect(x: full.minX, y: start, width: thickness, height: length)
            case .bottom: CGRect(x: start, y: visible.maxY - thickness, width: length, height: thickness)
            }
            guard let panel = panels[window.id] else { continue }
            panel.setFrame(ScreenGeometry.flip(axFrame), display: true)
            panel.orderFrontRegardless()
        }
    }

    private struct GroupKey: Hashable {
        let displayID: CGDirectDisplayID?
        let edge: Edge
    }
}
