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

    /// A tab the user is dragging a window toward.
    struct DropTarget {
        let item: TabItem
        let frame: CGRect
        let screen: NSScreen
    }

    private unowned let manager: ParkingManager
    private var panels: [UUID: TabPanel] = [:]
    private var groupModels: [UUID: GroupTabModel] = [:]
    private var grabOffset: CGFloat = 0
    /// Tabs are hidden while a full-screen app is in front.
    private var isSuppressed = false
    private let gap: CGFloat = 6
    /// How far a tab must be pulled from its edge before letting go releases it.
    private let pullAwayDistance: CGFloat = 80

    private lazy var fan = TabFanPanel(settings: manager.settings)
    private var fanItemID: UUID?
    private var fanIsDropTarget = false
    private var hoverCloseTask: Task<Void, Never>?
    private var hoverOpenTask: Task<Void, Never>?
    private var fanHovered = false
    private var currentDropTarget: DropTarget?
    /// A window being dragged out of a group's fan: its ghost tab and whether it's far enough out to release.
    private var cardDrag: (window: ParkedWindow, ghost: TabPanel, pulledAway: Bool)?

    init(manager: ParkingManager) {
        self.manager = manager
        NotificationCenter.default.addObserver(forName: .stickyTabLayoutChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.panels.values.forEach(self.applySpacesBehavior)
                self.layout()
            }
        }
        fan.onSelect = { [weak self] id in
            guard let self, let window = self.manager.parked.first(where: { $0.id == id }) else { return }
            Task { await self.manager.tabClicked(window) }
        }
        fan.onCardDrag = { [weak self] id, phase, point in self?.cardDrag(id, phase, point) }
        fan.onHoverChange = { [weak self] inside in
            guard let self else { return }
            self.fanHovered = inside
            if inside { self.hoverCloseTask?.cancel() } else { self.scheduleFanClose() }
        }
    }

    func setSuppressed(_ suppressed: Bool) {
        guard suppressed != isSuppressed else { return }
        isSuppressed = suppressed
        if suppressed {
            panels.values.forEach { $0.orderOut(nil) }
            closeFan()
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
        let live = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        // Drop panels whose tab is gone, or whose kind changed (single <-> group).
        for (id, panel) in panels {
            let item = live[id]
            if item == nil || (item!.isGroup != (groupModels[id] != nil)) {
                panel.orderOut(nil)
                panels[id] = nil
                groupModels[id] = nil
            }
        }
        for item in current {
            if panels[item.id] == nil {
                panels[item.id] = makePanel(for: item)
            } else if let model = groupModels[item.id], model.windows.map(\.id) != item.windows.map(\.id) {
                // Membership changed: update in place, so the tab doesn't flash or jump.
                model.windows = item.windows
            }
        }
        if let fanItemID, live[fanItemID] == nil { closeFan() } else if let fanItemID, !fanIsDropTarget, let item = live[fanItemID] { refreshFan(for: item) }
        layout()
    }

    /// The tab's current frame in AX coordinates (a group member reports its group's tab).
    func frame(of parkedWindow: ParkedWindow) -> CGRect? {
        panels[parkedWindow.groupID ?? parkedWindow.id].map { ScreenGeometry.flip($0.frame) }
    }

    // MARK: Drop targeting

    /// The tab a window dragged to `point` (AX coordinates) would be dropped onto. Generous: the cursor can be
    /// a couple of tab-thicknesses in from the edge, and once a target is acquired it sticks until the cursor
    /// leaves the tab-plus-fan area, so the fan doesn't flicker while the drag wobbles.
    func dropTarget(at point: CGPoint, excluding dragged: WindowController) -> DropTarget? {
        let metrics = manager.settings.tabMetrics
        if let current = currentDropTarget {
            var keep = current.frame.insetBy(dx: -metrics.thickness, dy: -metrics.thickness)
            if let fanFrame = fan.frame { keep = keep.union(fanFrame.insetBy(dx: -12, dy: -12)) }
            if keep.contains(point), !current.item.windows.contains(where: { $0.window.isSameWindow(as: dragged) }) {
                return current
            }
        }
        for item in items() {
            guard let frame = frame(of: item.lead),
                  let screen = ScreenGeometry.screen(withDisplayID: item.lead.displayID),
                  !item.windows.contains(where: { $0.window.isSameWindow(as: dragged) }) else { continue }
            // Reach: 2.5 tab thicknesses in from the edge, and a bit past each end of the tab.
            let reach = metrics.thickness * 2.5
            let hit: CGRect = switch item.lead.edge {
            case .right: CGRect(x: frame.minX - reach, y: frame.minY - 12, width: frame.width + reach, height: frame.height + 24)
            case .left: CGRect(x: frame.minX, y: frame.minY - 12, width: frame.width + reach, height: frame.height + 24)
            case .bottom: CGRect(x: frame.minX - 12, y: frame.minY - reach, width: frame.width + 24, height: frame.height + reach)
            }
            if hit.contains(point) { return DropTarget(item: item, frame: frame, screen: screen) }
        }
        return nil
    }

    /// Shows the fan for a drop target (previews of its windows plus the "+" slot), or hides it.
    func setDropTarget(_ target: DropTarget?) {
        let unchanged = target?.item.id == currentDropTarget?.item.id
        currentDropTarget = target
        guard let target else {
            if fanIsDropTarget { closeFan() }
            return
        }
        // Same tab as last move and the fan is already up: nothing to redraw.
        if unchanged, fanIsDropTarget, fan.isVisible { return }
        hoverOpenTask?.cancel(); hoverCloseTask?.cancel()
        fanIsDropTarget = true
        fanItemID = target.item.id
        fan.show(items: fanItems(target.item), edge: target.item.lead.edge, tabFrame: target.frame, screen: target.screen, dropTarget: true)
    }

    private func fanItems(_ item: TabItem) -> [TabFanModel.Item] {
        item.windows.map {
            TabFanModel.Item(id: $0.id, title: $0.displayTitle, appName: $0.appName, icon: $0.icon, thumbnail: $0.thumbnail, isRevealed: $0.isRevealed)
        }
    }

    // MARK: Dragging a window out of a group

    private func cardDrag(_ id: UUID, _ phase: TabFanModel.DragPhase, _ location: CGPoint) {
        switch phase {
        case .began:
            guard let window = manager.parked.first(where: { $0.id == id }),
                  let screen = ScreenGeometry.screen(withDisplayID: window.displayID) else { return }
            closeFan()
            manager.cancelHover(window)
            window.isDragging = true
            let ghost = TabPanel(rootView: EdgeTabView(parkedWindow: window, settings: manager.settings))
            applySpacesBehavior(to: ghost)
            ghost.alphaValue = 0.9
            let size = tabRect(edge: window.edge, screen: screen, start: 0).size
            let mouse = ScreenGeometry.axPoint(fromAppKit: location)
            ghost.setFrame(ScreenGeometry.flip(CGRect(x: mouse.x - size.width / 2, y: mouse.y - size.height / 2, width: size.width, height: size.height)), display: true)
            ghost.orderFrontRegardless()
            cardDrag = (window, ghost, false)
        case .changed:
            guard let drag = cardDrag, drag.window.id == id,
                  let screen = ScreenGeometry.screen(withDisplayID: drag.window.displayID) else { return }
            let full = ScreenGeometry.axFrame(of: screen)
            let visible = ScreenGeometry.axVisibleFrame(of: screen)
            let mouse = ScreenGeometry.axPoint(fromAppKit: location)
            let edge = drag.window.edge
            let distanceFromEdge: CGFloat = switch edge {
            case .right: full.maxX - mouse.x
            case .left: mouse.x - full.minX
            case .bottom: full.maxY - mouse.y
            }
            let pulledAway = distanceFromEdge > pullAwayDistance
            drag.window.isPulledAway = pulledAway
            cardDrag?.pulledAway = pulledAway
            let size = tabRect(edge: edge, screen: screen, start: 0).size
            let rect: CGRect
            if pulledAway {
                rect = CGRect(x: mouse.x - size.width / 2, y: mouse.y - size.height / 2, width: size.width, height: size.height)
            } else {
                // Snapped to the edge at the cursor's position, where it will become a tab.
                let length = manager.settings.tabMetrics.length
                let (lower, upper) = edge.isVertical ? (visible.minY, visible.maxY) : (visible.minX, visible.maxX)
                let start = min(max(along(mouse, edge) - length / 2, lower), upper - length)
                rect = tabRect(edge: edge, screen: screen, start: start)
            }
            drag.ghost.setFrame(ScreenGeometry.flip(rect), display: true)
        case .ended:
            guard let drag = cardDrag, drag.window.id == id else { return }
            cardDrag = nil
            drag.ghost.orderOut(nil)
            drag.window.isDragging = false
            drag.window.isPulledAway = false
            if drag.pulledAway {
                manager.release(drag.window)
            } else {
                let mouse = ScreenGeometry.axPoint(fromAppKit: location)
                manager.detach(drag.window, toOffset: along(mouse, drag.window.edge))
            }
        }
    }

    // MARK: Hover fan (group tabs)

    private func openFan(for item: TabItem) {
        guard let frame = frame(of: item.lead), let screen = ScreenGeometry.screen(withDisplayID: item.lead.displayID) else { return }
        fanIsDropTarget = false
        fanItemID = item.id
        fan.show(items: fanItems(item), edge: item.lead.edge, tabFrame: frame, screen: screen, dropTarget: false)
    }

    private func refreshFan(for item: TabItem) {
        guard fan.isVisible, let frame = frame(of: item.lead), let screen = ScreenGeometry.screen(withDisplayID: item.lead.displayID) else { return }
        fan.show(items: fanItems(item), edge: item.lead.edge, tabFrame: frame, screen: screen, dropTarget: false)
    }

    private func closeFan() {
        hoverOpenTask?.cancel(); hoverCloseTask?.cancel()
        fanItemID = nil
        fanIsDropTarget = false
        fan.hide()
    }

    private func scheduleFanClose() {
        guard !fanIsDropTarget else { return }
        hoverCloseTask?.cancel()
        hoverCloseTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled, !self.fanHovered else { return }
            self.closeFan()
        }
    }

    private func groupTabHover(_ item: TabItem, _ hovering: Bool) {
        item.windows.forEach { $0.isHovered = hovering }
        if hovering {
            hoverCloseTask?.cancel()
            guard !fanIsDropTarget, fanItemID != item.id else { return }
            hoverOpenTask?.cancel()
            hoverOpenTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(150))
                guard let self, !Task.isCancelled, item.windows.contains(where: \.isHovered) else { return }
                self.openFan(for: self.items().first { $0.id == item.id } ?? item)
            }
        } else {
            hoverOpenTask?.cancel()
            scheduleFanClose()
        }
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
                ? (item.lead.groupName.map { $0 + ": " } ?? "\(item.windows.count) windows: ") + item.windows.map(\.displayTitle).joined(separator: ", ")
                : "\(item.lead.appName) — \(item.lead.displayTitle)"
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
            let model = GroupTabModel(windows: windows)
            groupModels[item.id] = model
            panel = TabPanel(rootView: GroupTabView(model: model, settings: manager.settings))
        } else {
            panel = TabPanel(rootView: EdgeTabView(parkedWindow: lead, settings: manager.settings))
        }
        applySpacesBehavior(to: panel)

        let view = panel.hostingView
        let itemID = item.id
        if item.isGroup {
            // Click opens the fan (for people who don't hover); the fan's cards reveal windows.
            view.onClick = { [weak self] in
                guard let self, let current = self.items().first(where: { $0.id == itemID }) else { return }
                if self.fanItemID == itemID, !self.fanIsDropTarget { self.closeFan() } else { self.openFan(for: current) }
            }
            view.onHover = { [weak self] hovering in
                guard let self, let current = self.items().first(where: { $0.id == itemID }) else { return }
                self.groupTabHover(current, hovering)
            }
            view.menuProvider = { [weak self] in
                guard let self, let current = self.items().first(where: { $0.id == itemID }) else { return nil }
                return self.groupMenu(for: current.windows)
            }
        } else {
            view.onClick = { [weak manager] in
                guard let manager else { return }
                Task { await manager.tabClicked(lead) }
            }
            view.onHover = { [weak manager] in manager?.tabHoverChanged(lead, isHovering: $0) }
            view.menuProvider = { [weak self] in self?.contextMenu(for: lead) }
        }
        view.onDragBegan = { [weak self] in self?.dragBegan(itemID, at: $0) }
        view.onDragChanged = { [weak self] in self?.dragChanged(itemID, to: $0) }
        view.onDragEnded = { [weak self] _ in self?.dragEnded(itemID) }
        return panel
    }

    private func windows(of itemID: UUID) -> [ParkedWindow] {
        items().first { $0.id == itemID }?.windows ?? []
    }

    private func along(_ point: CGPoint, _ edge: Edge) -> CGFloat {
        edge.isVertical ? point.y : point.x
    }

    private func dragBegan(_ itemID: UUID, at location: CGPoint) {
        let windows = windows(of: itemID)
        closeFan()
        windows.forEach {
            manager.cancelHover($0)
            $0.isDragging = true
        }
        guard let lead = windows.first, let frame = frame(of: lead) else { return }
        let center = lead.edge.isVertical ? frame.midY : frame.midX
        grabOffset = along(ScreenGeometry.axPoint(fromAppKit: location), lead.edge) - center
    }

    private func dragChanged(_ itemID: UUID, to location: CGPoint) {
        let windows = windows(of: itemID)
        guard let lead = windows.first, let panel = panels[itemID],
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

    private func dragEnded(_ itemID: UUID) {
        let windows = windows(of: itemID)
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

        let header = NSMenuItem(title: "\(parkedWindow.appName) — \(parkedWindow.displayTitle)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        menu.addItem(ClosureMenuItem("Rename Tab…") { [weak self] in
            guard let self, let name = self.promptForName(
                title: "Rename Tab", message: "Shown on the tab instead of the window's title. Leave empty to use the title.",
                current: parkedWindow.customTitle ?? parkedWindow.title) else { return }
            manager.rename(parkedWindow, to: name)
        })
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
        let groupName = windows.first?.groupName
        let header = NSMenuItem(title: groupName.map { "\($0) (\(windows.count) windows)" } ?? "Group of \(windows.count) windows", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        menu.addItem(ClosureMenuItem("Rename Group…") { [weak self] in
            guard let self, let name = self.promptForName(
                title: "Rename Group", message: "Shown on the group's tab. Leave empty to show just the icons and count.",
                current: groupName ?? "") else { return }
            manager.renameGroup(windows, to: name)
        })
        menu.addItem(.separator())

        for window in windows {
            let item = ClosureMenuItem("\(window.appName) — \(window.displayTitle)", state: window.isRevealed ? .on : .off) {
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

    /// A small native prompt for a name. Returns nil when cancelled; an empty string clears the name.
    private func promptForName(title: String, message: String, current: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = current
        field.placeholderString = "Name"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        NSApp.activate()
        field.selectText(nil)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue
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
