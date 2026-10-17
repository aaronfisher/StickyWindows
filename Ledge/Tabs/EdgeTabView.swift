import SwiftUI

struct EdgeTabView: View {
    let parkedWindow: ParkedWindow
    let settings: SettingsStore

    static let thickness: CGFloat = 30
    static let length: CGFloat = 124

    var body: some View {
        let shape = Self.shape(for: parkedWindow.edge)

        content
            .frame(width: size.width, height: size.height)
            .background(.regularMaterial, in: shape)
            .overlay { shape.fill(Color.accentColor.opacity(highlight)) }
            .overlay { shape.strokeBorder(.primary.opacity(0.12), lineWidth: 0.5) }
            .overlay(alignment: .bottom) { peekMarker }
            .opacity(parkedWindow.isPulledAway ? 0.55 : 1)
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
    private var peekMarker: some View {
        if (parkedWindow.mode ?? settings.defaultRevealMode) == .peek {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 4, height: 4)
                .padding(4)
        }
    }

    private var size: CGSize {
        parkedWindow.edge.isVertical
            ? CGSize(width: Self.thickness, height: Self.length)
            : CGSize(width: Self.length, height: Self.thickness)
    }

    @ViewBuilder
    private var content: some View {
        let iconSize: CGFloat = 20
        let textLength = Self.length - iconSize - 22
        let title = Text(parkedWindow.title)
            .font(.system(size: 11, weight: .medium))
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundStyle(.primary)

        if parkedWindow.edge.isVertical {
            VStack(spacing: 6) {
                icon.frame(width: iconSize, height: iconSize)
                title
                    .frame(width: textLength, height: Self.thickness)
                    .rotationEffect(.degrees(parkedWindow.edge == .right ? 90 : -90))
                    .frame(width: Self.thickness, height: textLength)
            }
        } else {
            HStack(spacing: 6) {
                icon.frame(width: iconSize, height: iconSize)
                title.frame(width: textLength, alignment: .leading)
            }
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
