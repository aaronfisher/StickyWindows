import AppKit
import SwiftUI

/// Keeps one `TabPanel` per tab (a single parked window, or a group of them sharing a tab), lays them out
/// along their edges without overlap, and turns tab input into parking actions.
@MainActor
final class TabPresenter {
    /// One tab: a single window, or a stacked group.
    struct TabItem {
        let id: UUID
        let windows: [ParkedWindow]
        var lead: ParkedWindow { windows[0] }
        var isGroup: Bool { windows.count > 1 }
    }

    private unowned let manager: ParkingManager
    private var panels: [UUID: TabPanel] = [:]
    /// Window IDs each panel was built for, so a group's panel is rebuilt when its members change.
    private var panelMembers: [UUID: [UUID]] = [:]
    private var grabOffset: CGFloat = 0
    /// Tabs are hidden while a full-screen app is in front.
    private var isSuppressed = false
    private let gap: CGFloat = 6
    /// How far a tab must be pulled from its edge before letting go releases it.
    private let pullAwayDistance: CGFloat = 80
    private lazy var groupList = GroupListPanel(manager: manager)

    init(manager: ParkingManager) {
        self.manager = manager
        NotificationCenter.default.addObserver(forName: .stickyTabLayoutChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.panels.values.forEach(self.applySpacesBehavior)
                self.layout()
            }
        }
    }

    func setSuppressed(_ suppressed: Bool) {
        guard suppressed != isSuppressed else { return }
        isSuppressed = suppressed
        if suppressed {
            panels.values.forEach { $0.orderOut(nil) }
            groupList.close()
        } else {
            layout()
        }
    }

    private func applySpacesBehavior(to panel: TabPanel) {
        panel.collectionBehavior = manager.settings.tabsOnAllSpaces
            ? [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            : [.managed, .ignoresCycle, .fullScreenAuxiliary]
    }

    func items() -> [TabItem] {
        var order: [UUID] = []
        var members: [UUID: [ParkedWindow]] = [:]
        for parkedWindow in manager.parked {
            let key = parkedWindow.groupID ?? parkedWindow.id
            if members[key] == nil { order.append(key) }
            members[key, default: []].append(parkedWindow)
        }
        return order.map { TabItem(id: $0, windows: members[$0]!) }
    }

    func sync() {
        let current = items()
        let live = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0.windows.map(\.id)) })
        for (id, panel) in panels where live[id] != panelMembers[id] {
            panel.orderOut(nil)
            panels[id] = nil
            panelMembers[id] = nil
        }
        for item in current where panels[item.id] == nil {
            panels[item.id] = makePanel(for: item)
            panelMembers[item.id] = item.windows.map(\.id)
        }
        groupList.refresh(items: current)
        layout()
    }

    /// The tab's current frame in AX coordinates (a group member reports its group's tab).
    func frame(of parkedWindow: ParkedWindow) -> CGRect? {
        panels[parkedWindow.groupID ?? parkedWindow.id].map { ScreenGeometry.flip($0.frame) }
    }

    /// The tab under a drop zone's cursor position, for dropping a window onto it to form a group.
    func tabTarget(at zone: EdgeZone) -> (lead: ParkedWindow, frame: CGRect)? {
        let displayID = ScreenGeometry.displayID(of: zone.screen)
        for item in items() where item.lead.edge == zone.edge && item.lead.displayID == displayID {
            guard let frame = frame(of: item.lead) else { continue }
            let span = zone.edge.isVertical ? (frame.minY...frame.maxY) : (frame.minX...frame.maxX)
            if span.contains(zone.offset) { return (item.lead, frame) }
        }
        return nil
    }

    // MARK: Layout

    func layout(animated: Bool = false) {
        guard !isSuppressed else { return }
        let groups = Dictionary(grouping: items()) { GroupKey(displayID: $0.lead.displayID, edge: $0.lead.edge) }
        for (key, items) in groups {
            guard let screen = ScreenGeometry.screen(withDisplayID: key.displayID) else { continue }
            layout(items, on: screen, edge: key.edge, animated: animated)
        }
    }

    private func layout(_ items: [TabItem], on screen: NSScreen, edge: Edge, animated: Bool) {
        let visible = ScreenGeometry.axVisibleFrame(of: screen)
        let length = manager.settings.tabMetrics.length
        let (lower, upper) = edge.isVertical ? (visible.minY, visible.maxY) : (visible.minX, visible.maxX)

        // Each tab starts centered on its preferred spot, then gets pushed along to avoid the one before it.
        let sorted = items.sorted { $0.lead.desiredOffset < $1.lead.desiredOffset }
        var starts: [CGFloat] = []
        for item in sorted {
            let wanted = item.lead.desiredOffset - length / 2
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

        let reduceMotion = manager.settings.reduceMotion
        for (item, start) in zip(sorted, starts) {
            // A tab being dragged follows the cursor instead.
            guard !item.lead.isDragging, let panel = panels[item.id] else { continue }
            let frame = ScreenGeometry.flip(tabRect(edge: edge, screen: screen, start: start))
            if animated, !reduceMotion, panel.isVisible, panel.frame != frame {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.15
                    panel.animator().setFrame(frame, display: true)
                }
            } else {
                panel.setFrame(frame, display: true)
            }
            panel.hostingView.toolTip = item.isGroup
                ? "\(item.windows.count) windows: " + item.windows.map(\.title).joined(separator: ", ")
                : "\(item.lead.appName) — \(item.lead.title)"
            panel.orderFrontRegardless()
        }
    }

    /// A tab's rect in AX coordinates, `start` points along the edge.
    func tabRect(edge: Edge, screen: NSScreen, start: CGFloat) -> CGRect {
        let full = ScreenGeometry.axFrame(of: screen)
        let visible = ScreenGeometry.axVisibleFrame(of: screen)
        let thickness = manager.settings.tabMetrics.thickness
        let length = manager.settings.tabMetrics.length
        return switch edge {
        case .right: CGRect(x: full.maxX - thickness, y: start, width: thickness, height: length)
        case .left: CGRect(x: full.minX, y: start, width: thickness, height: length)
        case .bottom: CGRect(x: start, y: visible.maxY - thickness, width: length, height: thickness)
        }
    }

    // MARK: Input

    private func makePanel(for item: TabItem) -> TabPanel {
        let windows = item.windows
        let lead = item.lead
        let panel: TabPanel
        if item.isGroup {
            panel = TabPanel(rootView: GroupTabView(windows: windows, settings: manager.settings))
        } else {
            panel = TabPanel(rootView: EdgeTabView(parkedWindow: lead, settings: manager.settings))
        }
        applySpacesBehavior(to: panel)

        let view = panel.hostingView
        if item.isGroup {
            view.onClick = { [weak self] in self?.toggleGroupList(for: item.id) }
            view.onHover = { hovering in windows.forEach { $0.isHovered = hovering } }
            view.menuProvider = { [weak self] in self?.groupMenu(for: windows) }
        } else {
            view.onClick = { [weak manager] in
                guard let manager else { return }
                Task { await manager.tabClicked(lead) }
            }
            view.onHover = { [weak manager] in manager?.tabHoverChanged(lead, isHovering: $0) }
            view.menuProvider = { [weak self] in self?.contextMenu(for: lead) }
        }
        view.onDragBegan = { [weak self] in self?.dragBegan(windows, at: $0) }
        view.onDragChanged = { [weak self] in self?.dragChanged(windows, panelID: item.id, to: $0) }
        view.onDragEnded = { [weak self] _ in self?.dragEnded(windows) }
        return panel
    }

    private func toggleGroupList(for itemID: UUID) {
        guard let item = items().first(where: { $0.id == itemID }), let frame = frame(of: item.lead) else { return }
        groupList.toggle(item: item, beside: frame)
    }

    private func along(_ point: CGPoint, _ edge: Edge) -> CGFloat {
        edge.isVertical ? point.y : point.x
    }

    private func dragBegan(_ windows: [ParkedWindow], at location: CGPoint) {
        groupList.close()
        windows.forEach {
            manager.cancelHover($0)
            $0.isDragging = true
        }
        guard let lead = windows.first, let frame = frame(of: lead) else { return }
        let center = lead.edge.isVertical ? frame.midY : frame.midX
        grabOffset = along(ScreenGeometry.axPoint(fromAppKit: location), lead.edge) - center
    }

    private func dragChanged(_ windows: [ParkedWindow], panelID: UUID, to location: CGPoint) {
        guard let lead = windows.first, let panel = panels[panelID],
              let screen = ScreenGeometry.screen(withDisplayID: lead.displayID) else { return }
        let full = ScreenGeometry.axFrame(of: screen)
        let visible = ScreenGeometry.axVisibleFrame(of: screen)
        let mouse = ScreenGeometry.axPoint(fromAppKit: location)
        let edge = lead.edge

        let distanceFromEdge: CGFloat = switch edge {
        case .right: full.maxX - mouse.x
        case .left: mouse.x - full.minX
        case .bottom: full.maxY - mouse.y
        }
        let pulledAway = distanceFromEdge > pullAwayDistance
        windows.forEach { $0.isPulledAway = pulledAway }

        let length = manager.settings.tabMetrics.length
        let rect: CGRect
        if pulledAway {
            // Free-floating under the cursor: letting go here releases the window(s).
            let size = tabRect(edge: edge, screen: screen, start: 0).size
            rect = CGRect(x: mouse.x - size.width / 2, y: mouse.y - size.height / 2, width: size.width, height: size.height)
        } else {
            // Slide along the edge; neighbors make room as it passes them.
            let center = along(mouse, edge) - grabOffset
            let (lower, upper) = edge.isVertical ? (visible.minY, visible.maxY) : (visible.minX, visible.maxX)
            let start = min(max(center - length / 2, lower), upper - length)
            windows.forEach { manager.reorder($0, to: start + length / 2) }
            rect = tabRect(edge: edge, screen: screen, start: start)
            layout(animated: true)
        }
        panel.setFrame(ScreenGeometry.flip(rect), display: true)
    }

    private func dragEnded(_ windows: [ParkedWindow]) {
        windows.forEach { $0.isDragging = false }
        if windows.first?.isPulledAway == true {
            windows.forEach {
                $0.isPulledAway = false
                manager.release($0)
            }
        } else {
            layout(animated: true)
        }
    }

    // MARK: Menus

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

        menu.addItem(edgeMenuItem(current: parkedWindow.edge) { edge in
            Task { await manager.move(parkedWindow, to: edge) }
        })

        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Release") { manager.release(parkedWindow) })
        menu.addItem(ClosureMenuItem("Close Window") { manager.closeWindow(parkedWindow) })
        return menu
    }

    private func groupMenu(for windows: [ParkedWindow]) -> NSMenu {
        let manager = manager
        let menu = NSMenu()
        let header = NSMenuItem(title: "Group of \(windows.count) windows", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        for window in windows {
            let item = ClosureMenuItem("\(window.appName) — \(window.title)", state: window.isRevealed ? .on : .off) {
                Task { await manager.tabClicked(window) }
            }
            item.image = window.icon.map { icon in
                let copy = icon.copy() as! NSImage  // swiftlint:disable:this force_cast
                copy.size = NSSize(width: 16, height: 16)
                return copy
            }
            menu.addItem(item)
        }
        menu.addItem(.separator())
        if let lead = windows.first {
            menu.addItem(edgeMenuItem(current: lead.edge) { edge in
                Task { await manager.moveGroup(windows, to: edge) }
            })
        }
        menu.addItem(ClosureMenuItem("Ungroup") { manager.ungroup(windows) })
        menu.addItem(ClosureMenuItem("Release All") { windows.forEach(manager.release) })
        return menu
    }

    private func edgeMenuItem(current: Edge, action: @escaping @MainActor (Edge) -> Void) -> NSMenuItem {
        let edgeMenu = NSMenu()
        edgeMenu.autoenablesItems = false
        for edge in Edge.allCases {
            let item = ClosureMenuItem(edge.displayName, state: current == edge ? .on : .off) { action(edge) }
            item.isEnabled = edge != current
            edgeMenu.addItem(item)
        }
        let edgeItem = NSMenuItem(title: "Move to Edge", action: nil, keyEquivalent: "")
        edgeItem.submenu = edgeMenu
        return edgeItem
    }

    private struct GroupKey: Hashable {
        let displayID: CGDirectDisplayID?
        let edge: Edge
    }
}
