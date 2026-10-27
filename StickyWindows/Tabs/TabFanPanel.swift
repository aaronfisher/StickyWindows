import AppKit
import Observation
import SwiftUI

/// What a fan shows: one card per window in the tab (or group), optionally followed by a "+" slot.
@MainActor
@Observable
final class TabFanModel {
    struct Item: Identifiable {
        let id: UUID
        let title: String
        let appName: String
        let icon: NSImage?
        let thumbnail: NSImage?
        let isRevealed: Bool
    }

    /// One of the window's own tabs (browser tabs, Finder tabs, …), for the tab-list fan.
    struct WindowTabItem: Identifiable {
        let id: Int
        let title: String
        let isSelected: Bool
    }

    enum DragPhase { case began, changed, ended }

    var edge: Edge = .right
    var items: [Item] = []
    /// When set, the fan lists a single window's tabs under a header card instead of showing window cards.
    var windowTabs: [WindowTabItem] = []
    var showsWindowTabs = false
    var header: Item?
    var headerImageHeight: CGFloat = 0
    /// Tabs past the list's cap, shown as "and N more".
    var hiddenTabCount = 0
    var hoveredTabID: Int?
    /// Dropping onto the fan adds the dragged window: show the big "+" and highlight the whole fan.
    var isDropTarget = false
    var isOpen = false
    var hoveredID: UUID?
}

/// A panel that springs open from a tab, showing previews of the windows inside it.
/// Used both as the drop target while a window is dragged over a tab, and on hover over a group tab.
@MainActor
final class TabFanPanel {
    let model = TabFanModel()
    var onSelect: (UUID) -> Void = { _ in }
    /// A tab in the window-tab list was clicked.
    var onSelectWindowTab: (Int) -> Void = { _ in }
    /// A card being dragged out of the fan; the point is the cursor in AppKit screen coordinates.
    var onCardDrag: (UUID, TabFanModel.DragPhase, CGPoint) -> Void = { _, _, _ in }
    /// Reports when the cursor enters/leaves the fan, so hover fans can close once it's left.
    var onHoverChange: (Bool) -> Void = { _ in }

    private let settings: SettingsStore
    private lazy var panel: TabPanel = {
        let panel = TabPanel(rootView: TabFanView(
            model: model, settings: settings,
            onSelect: { [weak self] in self?.onSelect($0) },
            onSelectWindowTab: { [weak self] in self?.onSelectWindowTab($0) },
            onCardDrag: { [weak self] id, phase, point in self?.onCardDrag(id, phase, point) }))
        panel.hostingView.onHover = { [weak self] in self?.onHoverChange($0) }
        panel.level = .popUpMenu
        panel.hasShadow = true
        return panel
    }()

    init(settings: SettingsStore) {
        self.settings = settings
    }

    /// Card size: about twice the tab's thickness across, a bit longer along the edge.
    static func cardSize(for metrics: TabMetrics) -> CGSize {
        CGSize(width: metrics.thickness * 2.2, height: metrics.thickness * 2.2)
    }

    var frame: CGRect? { panel.isVisible ? ScreenGeometry.flip(panel.frame) : nil }
    var isVisible: Bool { panel.isVisible }
    var showsWindowTabs: Bool { panel.isVisible && model.showsWindowTabs }

    static let listWidth: CGFloat = 260
    static let listRowHeight: CGFloat = 26
    static let maxListedTabs = 12

    /// Shows the fan growing inward from `tabFrame` (AX coordinates) on `screen`.
    func show(items: [TabFanModel.Item], edge: Edge, tabFrame: CGRect, screen: NSScreen, dropTarget: Bool) {
        let metrics = settings.tabMetrics
        let card = Self.cardSize(for: metrics)
        let gap: CGFloat = 8
        let padding: CGFloat = 10
        let count = items.count + (dropTarget ? 1 : 0)
        let along = CGFloat(count) * card.width + CGFloat(max(count - 1, 0)) * gap + padding * 2
        let across = card.height + padding * 2 + 18  // room for the title under each card

        let visible = ScreenGeometry.axVisibleFrame(of: screen)
        var rect: CGRect
        switch edge {
        case .right:
            rect = CGRect(x: tabFrame.minX - across, y: tabFrame.midY - along / 2, width: across, height: along)
            rect.origin.y = min(max(rect.minY, visible.minY + 4), visible.maxY - along - 4)
        case .left:
            rect = CGRect(x: tabFrame.maxX, y: tabFrame.midY - along / 2, width: across, height: along)
            rect.origin.y = min(max(rect.minY, visible.minY + 4), visible.maxY - along - 4)
        case .bottom:
            rect = CGRect(x: tabFrame.midX - along / 2, y: tabFrame.minY - across, width: along, height: across)
            rect.origin.x = min(max(rect.minX, visible.minX + 4), visible.maxX - along - 4)
        }

        model.edge = edge
        model.items = items
        model.isDropTarget = dropTarget
        model.showsWindowTabs = false
        present(rect)
    }

    /// Shows the window's own tabs as a list beside its edge tab: a header card (preview, if there is one,
    /// and the window's title), then one row per tab with the selected one marked.
    func showWindowTabs(_ tabs: [WindowTab], of parkedWindow: ParkedWindow, tabFrame: CGRect, screen: NSScreen) {
        let padding: CGFloat = 10
        let inner = Self.listWidth - padding * 2
        let thumbnail = parkedWindow.isRevealed ? nil : parkedWindow.thumbnail
        var imageHeight: CGFloat = 0
        if let thumbnail, thumbnail.size.width > 0 {
            imageHeight = min(140, (inner * thumbnail.size.height / thumbnail.size.width).rounded())
        }
        let listed = Array(tabs.prefix(Self.maxListedTabs))
        let hidden = tabs.count - listed.count
        // Keep in step with WindowTabListView's layout.
        var across = padding * 2 + 20 + 6 + CGFloat(listed.count) * Self.listRowHeight
        if imageHeight > 0 { across += imageHeight + 6 }
        if hidden > 0 { across += 6 + 22 }
        let along = Self.listWidth

        let visible = ScreenGeometry.axVisibleFrame(of: screen)
        var rect: CGRect
        switch parkedWindow.edge {
        case .right:
            rect = CGRect(x: tabFrame.minX - along, y: tabFrame.midY - across / 2, width: along, height: across)
            rect.origin.y = min(max(rect.minY, visible.minY + 4), visible.maxY - across - 4)
        case .left:
            rect = CGRect(x: tabFrame.maxX, y: tabFrame.midY - across / 2, width: along, height: across)
            rect.origin.y = min(max(rect.minY, visible.minY + 4), visible.maxY - across - 4)
        case .bottom:
            rect = CGRect(x: tabFrame.midX - along / 2, y: tabFrame.minY - across, width: along, height: across)
            rect.origin.x = min(max(rect.minX, visible.minX + 4), visible.maxX - along - 4)
        }

        model.edge = parkedWindow.edge
        model.items = []
        model.isDropTarget = false
        model.header = TabFanModel.Item(
            id: parkedWindow.id, title: parkedWindow.displayTitle, appName: parkedWindow.appName,
            icon: parkedWindow.icon, thumbnail: thumbnail, isRevealed: parkedWindow.isRevealed)
        model.headerImageHeight = imageHeight
        model.windowTabs = listed.map { TabFanModel.WindowTabItem(id: $0.id, title: $0.title, isSelected: $0.isSelected) }
        model.hiddenTabCount = hidden
        model.hoveredTabID = nil
        model.showsWindowTabs = true
        present(rect)
    }

    private func present(_ rect: CGRect) {
        let wasOpen = model.isOpen && panel.isVisible
        panel.setFrame(ScreenGeometry.flip(rect), display: true)
        panel.orderFrontRegardless()
        if !wasOpen {
            model.isOpen = false
            // Next run loop turn, so the spring animates from closed.
            DispatchQueue.main.async { [model] in
                withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) { model.isOpen = true }
            }
        }
    }

    func hide() {
        guard panel.isVisible else { return }
        withAnimation(.easeIn(duration: 0.12)) { model.isOpen = false }
        model.hoveredID = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.13) { [panel, model] in
            if !model.isOpen { panel.orderOut(nil) }
        }
    }
}

private struct TabFanView: View {
    let model: TabFanModel
    let settings: SettingsStore
    let onSelect: (UUID) -> Void
    let onSelectWindowTab: (Int) -> Void
    let onCardDrag: (UUID, TabFanModel.DragPhase, CGPoint) -> Void
    @State private var draggingID: UUID?

    var body: some View {
        let metrics = settings.tabMetrics
        let card = TabFanPanel.cardSize(for: metrics)
        let accent = settings.accentColor
        let vertical = model.edge.isVertical

        Group {
            if model.showsWindowTabs {
                WindowTabListView(model: model, accent: accent, onSelect: onSelectWindowTab)
            } else if vertical {
                VStack(spacing: 8) { cards(card, accent) }
            } else {
                HStack(spacing: 8) { cards(card, accent) }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(settings.tabMaterial.material, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(model.isDropTarget ? accent.opacity(0.9) : Color.primary.opacity(0.12), lineWidth: model.isDropTarget ? 2 : 0.5)
        }
        // Grows out of the tab: anchored on the edge side, scaled from nothing.
        .scaleEffect(model.isOpen ? 1 : 0.2, anchor: anchor)
        .opacity(model.isOpen ? 1 : 0)
    }

    @ViewBuilder
    private func cards(_ card: CGSize, _ accent: Color) -> some View {
        ForEach(model.items) { item in
            FanCard(item: item, size: card, accent: accent, hovered: model.hoveredID == item.id)
                .opacity(draggingID == item.id ? 0.35 : 1)
                .onHover { model.hoveredID = $0 ? item.id : (model.hoveredID == item.id ? nil : model.hoveredID) }
                .onTapGesture { onSelect(item.id) }
                .gesture(
                    DragGesture(minimumDistance: 6)
                        .onChanged { _ in
                            // Screen coordinates come from AppKit; the gesture only tells us that movement happened.
                            if draggingID != item.id {
                                draggingID = item.id
                                onCardDrag(item.id, .began, NSEvent.mouseLocation)
                            }
                            onCardDrag(item.id, .changed, NSEvent.mouseLocation)
                        }
                        .onEnded { _ in
                            if draggingID == item.id {
                                draggingID = nil
                                onCardDrag(item.id, .ended, NSEvent.mouseLocation)
                            }
                        })
        }
        if model.isDropTarget {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(accent, style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(accent.opacity(0.12)))
                    Image(systemName: "plus")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(accent)
                }
                .frame(width: card.width, height: card.height)
                Text("Add to group")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var anchor: UnitPoint {
        switch model.edge {
        case .right: .trailing
        case .left: .leading
        case .bottom: .bottom
        }
    }
}

private struct FanCard: View {
    let item: TabFanModel.Item
    let size: CGSize
    let accent: Color
    let hovered: Bool

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(hovered ? 0.14 : 0.07))
                if let thumbnail = item.thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .padding(6)
                } else if let icon = item.icon {
                    Image(nsImage: icon).resizable().interpolation(.high)
                        .frame(width: size.width * 0.5, height: size.width * 0.5)
                } else {
                    Image(systemName: "macwindow").font(.system(size: 24))
                }
                if item.isRevealed {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(accent, lineWidth: 2)
                }
                if let icon = item.icon, item.thumbnail != nil {
                    // App badge in the corner of a live preview.
                    Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(5)
                }
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            Text(item.title)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: size.width)
        }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }
}

/// The window-tab list: header card, then a row per tab. Heights match `TabFanPanel.showWindowTabs`.
private struct WindowTabListView: View {
    let model: TabFanModel
    let accent: Color
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let header = model.header {
                if let thumbnail = header.thumbnail, model.headerImageHeight > 0 {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: TabFanPanel.listWidth - 20, height: model.headerImageHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                HStack(spacing: 6) {
                    if let icon = header.icon {
                        Image(nsImage: icon).resizable().interpolation(.high).frame(width: 16, height: 16)
                    }
                    Text(header.title)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    Text("\(model.windowTabs.count + model.hiddenTabCount) tabs")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .frame(height: 20)
            }
            VStack(spacing: 0) {
                ForEach(model.windowTabs) { tab in
                    let hovered = model.hoveredTabID == tab.id
                    HStack(spacing: 8) {
                        Circle()
                            .fill(tab.isSelected ? accent : Color.clear)
                            .frame(width: 6, height: 6)
                        Text(tab.title)
                            .font(.system(size: 11, weight: tab.isSelected ? .semibold : .regular))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: TabFanPanel.listRowHeight)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(hovered ? Color.primary.opacity(0.12) : (tab.isSelected ? accent.opacity(0.12) : Color.clear)))
                    .contentShape(Rectangle())
                    .onHover { model.hoveredTabID = $0 ? tab.id : (model.hoveredTabID == tab.id ? nil : model.hoveredTabID) }
                    .onTapGesture { onSelect(tab.id) }
                }
            }
            if model.hiddenTabCount > 0 {
                Text("and \(model.hiddenTabCount) more")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
            }
        }
        .frame(width: TabFanPanel.listWidth - 20, alignment: .leading)
    }
}
