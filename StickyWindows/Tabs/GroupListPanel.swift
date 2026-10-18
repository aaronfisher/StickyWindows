import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class GroupListModel {
    var windows: [ParkedWindow] = []
}

/// The mini list a group tab expands into: click a row to show/hide that window.
@MainActor
final class GroupListPanel {
    private unowned let manager: ParkingManager
    private let model = GroupListModel()
    private var itemID: UUID?
    private var monitors: [Any] = []
    private lazy var panel: NSPanel = {
        let panel = ListPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        let view = GroupListView(model: model, manager: manager) { [weak self] in self?.close() }
        panel.contentView = FirstMouseHostingView(rootView: view)
        return panel
    }()

    init(manager: ParkingManager) {
        self.manager = manager
    }

    var isOpen: Bool { itemID != nil }

    func toggle(item: TabPresenter.TabItem, beside tabFrame: CGRect) {
        if itemID == item.id { return close() }
        itemID = item.id
        model.windows = item.windows

        let rowHeight: CGFloat = 30
        let size = CGSize(width: 260, height: CGFloat(item.windows.count) * rowHeight + 12)
        let edge = item.lead.edge
        guard let screen = ScreenGeometry.screen(withDisplayID: item.lead.displayID) else { return }
        let visible = ScreenGeometry.axVisibleFrame(of: screen)
        var origin: CGPoint = switch edge {
        case .right: CGPoint(x: tabFrame.minX - 6 - size.width, y: tabFrame.midY - size.height / 2)
        case .left: CGPoint(x: tabFrame.maxX + 6, y: tabFrame.midY - size.height / 2)
        case .bottom: CGPoint(x: tabFrame.midX - size.width / 2, y: tabFrame.minY - 6 - size.height)
        }
        origin.x = min(max(origin.x, visible.minX + 4), visible.maxX - size.width - 4)
        origin.y = min(max(origin.y, visible.minY + 4), visible.maxY - size.height - 4)
        panel.setFrame(ScreenGeometry.flip(CGRect(origin: origin, size: size)), display: true)
        panel.orderFrontRegardless()
        installDismissMonitors()
    }

    /// Keeps an open list in step with group membership; closes it if its group is gone.
    func refresh(items: [TabPresenter.TabItem]) {
        guard let itemID else { return }
        guard let item = items.first(where: { $0.id == itemID }), item.isGroup else { return close() }
        model.windows = item.windows
    }

    func close() {
        itemID = nil
        panel.orderOut(nil)
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    /// Any click outside the list closes it (clicks in other apps arrive via the global monitor).
    private func installDismissMonitors() {
        guard monitors.isEmpty else { return }
        let outside: () -> Void = { [weak self] in
            guard let self else { return }
            if !NSMouseInRect(NSEvent.mouseLocation, self.panel.frame, false) { self.close() }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { _ in
            MainActor.assumeIsolated { outside() }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { event in
            MainActor.assumeIsolated {
                // Clicks on the group's own tab are handled by its toggle.
                if event.window !== self.panel, !(event.window is TabPanel) { outside() }
            }
            return event
        }) {
            monitors.append(local)
        }
    }

    private final class ListPanel: NSPanel {
        override var canBecomeKey: Bool { false }
    }
}

/// Lets rows be clicked on the first try although Sticky Windows never becomes active.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct GroupListView: View {
    let model: GroupListModel
    let manager: ParkingManager
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(model.windows) { window in
                GroupRow(window: window, manager: manager, onDone: onDone)
            }
        }
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.12), lineWidth: 0.5) }
    }
}

private struct GroupRow: View {
    let window: ParkedWindow
    let manager: ParkingManager
    let onDone: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Button {
                onDone()
                Task { await manager.tabClicked(window) }
            } label: {
                HStack(spacing: 8) {
                    Group {
                        if let icon = window.icon {
                            Image(nsImage: icon).resizable()
                        } else {
                            Image(systemName: "macwindow")
                        }
                    }
                    .frame(width: 18, height: 18)
                    Text(window.title).lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 0)
                    if window.isRevealed {
                        Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                    }
                    BadgeView(text: window.badge)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                manager.release(window)
            } label: {
                Image(systemName: "arrow.uturn.backward.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Release: restore this window and take it out of the group")
        }
        .font(.system(size: 12))
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(isHovered ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .onHover { isHovered = $0 }
    }
}
