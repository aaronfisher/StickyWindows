import SwiftUI

struct EdgeTabView: View {
    let parkedWindow: ParkedWindow
    let onClick: () -> Void

    @State private var isHovering = false

    static let thickness: CGFloat = 30
    static let length: CGFloat = 124

    var body: some View {
        let shape = Self.shape(for: parkedWindow.edge)

        content
            .frame(width: size.width, height: size.height)
            .background(.regularMaterial, in: shape)
            .overlay {
                shape.fill(Color.accentColor.opacity(parkedWindow.isRevealed ? 0.28 : (isHovering ? 0.12 : 0)))
            }
            .overlay { shape.strokeBorder(.primary.opacity(0.12), lineWidth: 0.5) }
            .contentShape(shape)
            .onHover { isHovering = $0 }
            .onTapGesture(perform: onClick)
            .help("\(parkedWindow.appName) — \(parkedWindow.title)")
            .animation(.easeOut(duration: 0.12), value: isHovering)
            .animation(.easeOut(duration: 0.12), value: parkedWindow.isRevealed)
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
