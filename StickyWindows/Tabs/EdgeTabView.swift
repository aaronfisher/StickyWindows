import SwiftUI

struct EdgeTabView: View {
    let parkedWindow: ParkedWindow
    let settings: SettingsStore

    var body: some View {
        let shape = Self.shape(for: parkedWindow.edge)
        let accent = settings.accentColor

        content
            .frame(width: size.width, height: size.height)
            .background(settings.tabMaterial.material, in: shape)
            .overlay { shape.fill(accent.opacity(highlight)) }
            .overlay { shape.strokeBorder(.primary.opacity(0.12), lineWidth: 0.5) }
            .overlay(alignment: parkedWindow.edge.isVertical ? .bottom : .trailing) { peekMarker(accent) }
            .overlay(alignment: badgeAlignment) { BadgeView(text: parkedWindow.badge) }
            .opacity((parkedWindow.isPulledAway ? 0.55 : 1) * settings.tabOpacity)
            .scaleEffect(parkedWindow.isPulledAway ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: parkedWindow.isHovered)
            .animation(.easeOut(duration: 0.12), value: parkedWindow.isRevealed)
            .animation(.easeOut(duration: 0.12), value: parkedWindow.isPulledAway)
    }

    private var highlight: Double {
        if parkedWindow.isRevealed { return 0.28 }
        if parkedWindow.isHovered || parkedWindow.isDragging { return 0.12 }
        return 0
    }

    /// Small dot marking tabs that auto-tuck (Peek), so the two modes are tellable apart at a glance.
    @ViewBuilder
    private func peekMarker(_ accent: Color) -> some View {
        if (parkedWindow.mode ?? settings.defaultRevealMode) == .peek {
            Circle()
                .fill(accent)
                .frame(width: 4, height: 4)
                .padding(4)
        }
    }

    /// Top corner on the inward side, where it can't be clipped by the screen edge.
    private var badgeAlignment: Alignment {
        switch parkedWindow.edge {
        case .right: .topLeading
        case .left: .topTrailing
        case .bottom: .topTrailing
        }
    }

    private var metrics: TabMetrics { settings.tabMetrics }

    private var size: CGSize {
        parkedWindow.edge.isVertical
            ? CGSize(width: metrics.thickness, height: metrics.length)
            : CGSize(width: metrics.length, height: metrics.thickness)
    }

    @ViewBuilder
    private var content: some View {
        let iconSize = (metrics.thickness * 0.66).rounded()
        if settings.showTitles {
            let textLength = metrics.length - iconSize - 22
            let title = Text(parkedWindow.displayTitle)
                .font(.system(size: metrics.thickness >= 34 ? 12 : 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.primary)

            if parkedWindow.edge.isVertical {
                VStack(spacing: 6) {
                    icon.frame(width: iconSize, height: iconSize)
                    title
                        .frame(width: textLength, height: metrics.thickness)
                        .rotationEffect(.degrees(parkedWindow.edge == .right ? 90 : -90))
                        .frame(width: metrics.thickness, height: textLength)
                }
            } else {
                HStack(spacing: 6) {
                    icon.frame(width: iconSize, height: iconSize)
                    title.frame(width: textLength, alignment: .leading)
                }
            }
        } else {
            icon.frame(width: iconSize, height: iconSize)
        }
    }

    @ViewBuilder
    private var icon: some View {
        if let image = parkedWindow.icon {
            Image(nsImage: image).resizable().interpolation(.high)
        } else {
            Image(systemName: "macwindow")
        }
    }

    /// Rounded on the inward side only, flush against the screen edge.
    static func shape(for edge: Edge) -> UnevenRoundedRectangle {
        let r: CGFloat = 9
        return switch edge {
        case .right: UnevenRoundedRectangle(topLeadingRadius: r, bottomLeadingRadius: r)
        case .left: UnevenRoundedRectangle(bottomTrailingRadius: r, topTrailingRadius: r)
        case .bottom: UnevenRoundedRectangle(topLeadingRadius: r, topTrailingRadius: r)
        }
    }
}

/// Red Dock-style badge capsule.
struct BadgeView: View {
    let text: String?

    var body: some View {
        if let text, !text.isEmpty {
            Text(text.count > 3 ? "99+" : text)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .frame(minWidth: 15, minHeight: 15)
                .background(Color.red, in: Capsule())
                .padding(2)
                .transition(.scale.combined(with: .opacity))
        }
    }
}
