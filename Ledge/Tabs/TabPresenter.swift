import AppKit
import SwiftUI

/// Keeps one `TabPanel` per parked window, lays them out along their edges without overlap,
/// and turns tab input into parking actions.
@MainActor
final class TabPresenter {
    private unowned let manager: ParkingManager
    private var panels: [UUID: TabPanel] = [:]
    private var grabOffset: CGFloat = 0
    private let gap: CGFloat = 6
    /// How far a tab must be pulled from its edge before letting go releases it.
    private let pullAwayDistance: CGFloat = 80

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
            panels[parkedWindow.id] = makePanel(for: parkedWindow)
        }
        layout()
    }

    /// The tab's current frame in AX coordinates.
    func frame(of parkedWindow: ParkedWindow) -> CGRect? {
        panels[parkedWindow.id].map { ScreenGeometry.flip($0.frame) }
    }

    // MARK: Layout

    func layout(animated: Bool = false) {
        let groups = Dictionary(grouping: manager.parked) { GroupKey(displayID: $0.displayID, edge: $0.edge) }
        for (key, windows) in groups {
            guard let screen = ScreenGeometry.screen(withDisplayID: key.displayID) else { continue }
            layout(windows, on: screen, edge: key.edge, animated: animated)
        }
    }

    private func layout(_ windows: [ParkedWindow], on screen: NSScreen, edge: Edge, animated: Bool) {
        let visible = ScreenGeometry.axVisibleFrame(of: screen)
        let length = EdgeTabView.length
        let (lower, upper) = edge.isVertical ? (visible.minY, visible.maxY) : (visible.minX, visible.maxX)

        // Each tab starts centered on its preferred spot, then gets pushed along to avoid the one before it.
        let sorted = windows.sorted { $0.desiredOffset < $1.desiredOffset }
        var starts: [CGFloat] = []
        for window in sorted {
            let wanted = window.desiredOffset - length / 2
            let afterPrevious = starts.last.map { $0 + length + gap } ?? lower
            starts.append(max(wanted, afterPrevious, lower))
        }
        // If the stack runs off the end, slide the tail back.
        if let last = starts.last, last + length > upper {
            var limit = upper - length
            for index in starts.indices.reversed() where starts[index] > limit {
                starts[index] = max(limit, lower)
                limit -= length + gap
            }
        }

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        for (window, start) in zip(sorted, starts) {
            // A tab being dragged follows the cursor instead.
            guard !window.isDragging, let panel = panels[window.id] else { continue }
            let frame = ScreenGeometry.flip(Self.tabRect(edge: edge, screen: screen, start: start))
            if animated, !reduceMotion, panel.isVisible, panel.frame != frame {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.15
                    panel.animator().setFrame(frame, display: true)
                }
            } else {
                panel.setFrame(frame, display: true)
            }
            panel.hostingView.toolTip = "\(window.appName) — \(window.title)"
            panel.orderFrontRegardless()
        }
    }

    /// A tab's rect in AX coordinates, `start` points along the edge.
    static func tabRect(edge: Edge, screen: NSScreen, start: CGFloat) -> CGRect {
        let full = ScreenGeometry.axFrame(of: screen)
        let visible = ScreenGeometry.axVisibleFrame(of: screen)
        let thickness = EdgeTabView.thickness
        let length = EdgeTabView.length
        return switch edge {
        case .right: CGRect(x: full.maxX - thickness, y: start, width: thickness, height: length)
        case .left: CGRect(x: full.minX, y: start, width: thickness, height: length)
        case .bottom: CGRect(x: start, y: visible.maxY - thickness, width: length, height: thickness)
        }
    }

    // MARK: Input

    private func makePanel(for parkedWindow: ParkedWindow) -> TabPanel {
        let panel = TabPanel(rootView: EdgeTabView(parkedWindow: parkedWindow, settings: manager.settings))
        let view = panel.hostingView
        view.onClick = { [weak manager] in
            guard let manager else { return }
            Task { await manager.tabClicked(parkedWindow) }
        }
        view.onHover = { [weak manager] in manager?.tabHoverChanged(parkedWindow, isHovering: $0) }
        view.onDragBegan = { [weak self] in self?.dragBegan(parkedWindow, at: $0) }
        view.onDragChanged = { [weak self] in self?.dragChanged(parkedWindow, to: $0) }
        view.onDragEnded = { [weak self] _ in self?.dragEnded(parkedWindow) }
        view.menuProvider = { [weak self] in self?.contextMenu(for: parkedWindow) }
        return panel
    }

    private func along(_ point: CGPoint, _ edge: Edge) -> CGFloat {
        edge.isVertical ? point.y : point.x
    }

    private func dragBegan(_ parkedWindow: ParkedWindow, at location: CGPoint) {
        manager.cancelHover(parkedWindow)
        parkedWindow.isDragging = true
        guard let frame = frame(of: parkedWindow) else { return }
        let center = parkedWindow.edge.isVertical ? frame.midY : frame.midX
        grabOffset = along(ScreenGeometry.axPoint(fromAppKit: location), parkedWindow.edge) - center
    }

    private func dragChanged(_ parkedWindow: ParkedWindow, to location: CGPoint) {
        guard let panel = panels[parkedWindow.id],
              let screen = ScreenGeometry.screen(withDisplayID: parkedWindow.displayID) else { return }
        let full = ScreenGeometry.axFrame(of: screen)
        let visible = ScreenGeometry.axVisibleFrame(of: screen)
        let mouse = ScreenGeometry.axPoint(fromAppKit: location)
        let edge = parkedWindow.edge

        let distanceFromEdge: CGFloat = switch edge {
        case .right: full.maxX - mouse.x
        case .left: mouse.x - full.minX
        case .bottom: full.maxY - mouse.y
        }
        parkedWindow.isPulledAway = distanceFromEdge > pullAwayDistance

        let length = EdgeTabView.length
        let rect: CGRect
        if parkedWindow.isPulledAway {
            // Free-floating under the cursor: letting go here releases the window.
            let size = Self.tabRect(edge: edge, screen: screen, start: 0).size
            rect = CGRect(x: mouse.x - size.width / 2, y: mouse.y - size.height / 2, width: size.width, height: size.height)
        } else {
            // Slide along the edge; neighbors make room as it passes them.
            let center = along(mouse, edge) - grabOffset
            let (lower, upper) = edge.isVertical ? (visible.minY, visible.maxY) : (visible.minX, visible.maxX)
            let start = min(max(center - length / 2, lower), upper - length)
            manager.reorder(parkedWindow, to: start + length / 2)
            rect = Self.tabRect(edge: edge, screen: screen, start: start)
            layout(animated: true)
        }
        panel.setFrame(ScreenGeometry.flip(rect), display: true)
    }

    private func dragEnded(_ parkedWindow: ParkedWindow) {
        parkedWindow.isDragging = false
        if parkedWindow.isPulledAway {
            parkedWindow.isPulledAway = false
            manager.release(parkedWindow)
        } else {
            layout(animated: true)
        }
    }

    private func contextMenu(for parkedWindow: ParkedWindow) -> NSMenu {
        let manager = manager
        let menu = NSMenu()

        let header = NSMenuItem(title: "\(parkedWindow.appName) — \(parkedWindow.title)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        if parkedWindow.isRevealed {
            menu.addItem(ClosureMenuItem("Hide") { Task { await manager.tuck(parkedWindow) } })
        } else {
            menu.addItem(ClosureMenuItem("Show") { manager.reveal(parkedWindow) })
        }

        let modeMenu = NSMenu()
        for mode in RevealMode.allCases {
            modeMenu.addItem(ClosureMenuItem(mode.displayName, state: parkedWindow.mode == mode ? .on : .off) {
                manager.setMode(mode, for: parkedWindow)
            })
        }
        modeMenu.addItem(.separator())
        let defaultName = manager.settings.defaultRevealMode.displayName
        modeMenu.addItem(ClosureMenuItem("Use Default (\(defaultName))", state: parkedWindow.mode == nil ? .on : .off) {
            manager.setMode(nil, for: parkedWindow)
        })
        let modeItem = NSMenuItem(title: "Mode: \(manager.effectiveMode(of: parkedWindow).displayName)", action: nil, keyEquivalent: "")
        modeItem.submenu = modeMenu
        menu.addItem(modeItem)

        let edgeMenu = NSMenu()
        for edge in Edge.allCases {
            let item = ClosureMenuItem(edge.displayName, state: parkedWindow.edge == edge ? .on : .off) {
                Task { await manager.move(parkedWindow, to: edge) }
            }
            item.isEnabled = edge != parkedWindow.edge
            edgeMenu.addItem(item)
        }
        edgeMenu.autoenablesItems = false
        let edgeItem = NSMenuItem(title: "Move to Edge", action: nil, keyEquivalent: "")
        edgeItem.submenu = edgeMenu
        menu.addItem(edgeItem)

        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Release") { manager.release(parkedWindow) })
        menu.addItem(ClosureMenuItem("Close Window") { manager.closeWindow(parkedWindow) })
        return menu
    }

    private struct GroupKey: Hashable {
        let displayID: CGDirectDisplayID?
        let edge: Edge
    }
}
