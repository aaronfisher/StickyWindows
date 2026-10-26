import Observation
import SwiftUI

/// Members of a group tab. Kept as a model so the panel updates in place when membership changes.
@MainActor
@Observable
final class GroupTabModel {
    var windows: [ParkedWindow]
    init(windows: [ParkedWindow]) { self.windows = windows }
}

/// A tab holding several parked windows: overlapping app icons and a count.
struct GroupTabView: View {
    let model: GroupTabModel
    let settings: SettingsStore

    private var windows: [ParkedWindow] { model.windows }
    private var edge: Edge { windows.first?.edge ?? .right }
    private var metrics: TabMetrics { settings.tabMetrics }

    var body: some View {
        let shape = EdgeTabView.shape(for: edge)
        let accent = settings.accentColor
        let anyRevealed = windows.contains(where: \.isRevealed)
        let anyHovered = windows.contains { $0.isHovered || $0.isDragging }
        let pulledAway = windows.first?.isPulledAway == true

        content
            .frame(width: size.width, height: size.height)
            .background(settings.tabMaterial.material, in: shape)
            .overlay { shape.fill(accent.opacity(anyRevealed ? 0.28 : (anyHovered ? 0.12 : 0))) }
            .overlay { shape.strokeBorder(.primary.opacity(0.12), lineWidth: 0.5) }
            .overlay(alignment: edge == .right ? .topLeading : .topTrailing) {
                BadgeView(text: windows.lazy.compactMap(\.badge).first)
            }
            .opacity((pulledAway ? 0.55 : 1) * settings.tabOpacity)
            .scaleEffect(pulledAway ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: anyHovered)
            .animation(.easeOut(duration: 0.12), value: anyRevealed)
            .animation(.easeOut(duration: 0.15), value: windows.count)
    }

    private var size: CGSize {
        edge.isVertical
            ? CGSize(width: metrics.thickness, height: metrics.length)
            : CGSize(width: metrics.length, height: metrics.thickness)
    }

    @ViewBuilder
    private var content: some View {
        let name = windows.first?.groupName
        let iconSize = (metrics.thickness * (name == nil ? 0.6 : 0.5)).rounded()
        let stack = windows.prefix(3)
        let icons = ForEach(Array(stack.enumerated()), id: \.offset) { _, window in
            Group {
                if let icon = window.icon {
                    Image(nsImage: icon).resizable().interpolation(.high)
                } else {
                    Image(systemName: "macwindow")
                }
            }
            .frame(width: iconSize, height: iconSize)
            .shadow(radius: 1, y: 0.5)
        }
        let count = Text("\(windows.count)")
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.primary.opacity(0.12), in: Capsule())

        if let name, settings.showTitles {
            // Named group: icon stack, then the name along the tab, then the count.
            let label = Text(name)
                .font(.system(size: metrics.thickness >= 42 ? 13 : (metrics.thickness >= 34 ? 12 : 11), weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
            let textLength = metrics.length - iconSize * 1.6 - 34
            if edge.isVertical {
                VStack(spacing: 4) {
                    VStack(spacing: -iconSize * 0.45) { icons }
                    label
                        .frame(width: textLength, height: metrics.thickness)
                        .rotationEffect(.degrees(edge == .right ? 90 : -90))
                        .frame(width: metrics.thickness, height: textLength)
                    count
                }
            } else {
                HStack(spacing: 4) {
                    HStack(spacing: -iconSize * 0.45) { icons }
                    label.frame(width: textLength, alignment: .leading)
                    count
                }
            }
        } else if edge.isVertical {
            VStack(spacing: 4) {
                VStack(spacing: -iconSize * 0.45) { icons }
                count
            }
        } else {
            HStack(spacing: 4) {
                HStack(spacing: -iconSize * 0.45) { icons }
                count
            }
        }
    }
}
