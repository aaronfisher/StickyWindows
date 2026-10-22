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

    var edge: Edge = .right
    var items: [Item] = []
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
    /// Reports when the cursor enters/leaves the fan, so hover fans can close once it's left.
    var onHoverChange: (Bool) -> Void = { _ in }

    private let settings: SettingsStore
    private lazy var panel: TabPanel = {
        let panel = TabPanel(rootView: TabFanView(model: model, settings: settings, onSelect: { [weak self] in self?.onSelect($0) }))
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

        let wasOpen = model.isOpen && panel.isVisible
        model.edge = edge
        model.items = items
        model.isDropTarget = dropTarget
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

    var body: some View {
        let metrics = settings.tabMetrics
        let card = TabFanPanel.cardSize(for: metrics)
        let accent = settings.accentColor
        let vertical = model.edge.isVertical

        Group {
            if vertical {
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
                .onHover { model.hoveredID = $0 ? item.id : (model.hoveredID == item.id ? nil : model.hoveredID) }
                .onTapGesture { onSelect(item.id) }
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
