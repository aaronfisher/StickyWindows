import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class PreviewModel {
    var image: NSImage?
    var title = ""
    var appName = ""
    var icon: NSImage?
}

/// Floating window preview shown beside a hovered tab.
@MainActor
final class PreviewPanel {
    private let model = PreviewModel()
    private lazy var panel: TabPanel = {
        let panel = TabPanel(rootView: PreviewView(model: model))
        panel.ignoresMouseEvents = true
        panel.level = .popUpMenu
        return panel
    }()
    private let maxSize = CGSize(width: 280, height: 180)
    private let gap: CGFloat = 8

    func show(for parkedWindow: ParkedWindow, image: NSImage?, beside tabFrame: CGRect) {
        model.image = image
        model.title = parkedWindow.title
        model.appName = parkedWindow.appName
        model.icon = parkedWindow.icon

        // Aspect-fit the window into the preview box; without an image, a small icon + title card.
        let windowSize = parkedWindow.storedFrame.size
        let scale = min(maxSize.width / max(windowSize.width, 1), maxSize.height / max(windowSize.height, 1))
        let imageSize = image == nil ? CGSize(width: 200, height: 0) : CGSize(width: windowSize.width * scale, height: windowSize.height * scale)
        let size = CGSize(width: max(imageSize.width, 160) + 16, height: imageSize.height + (image == nil ? 52 : 44))

        guard let screen = ScreenGeometry.screen(withDisplayID: parkedWindow.displayID) else { return }
        let visible = ScreenGeometry.axVisibleFrame(of: screen)
        var origin: CGPoint = switch parkedWindow.edge {
        case .right: CGPoint(x: tabFrame.minX - gap - size.width, y: tabFrame.midY - size.height / 2)
        case .left: CGPoint(x: tabFrame.maxX + gap, y: tabFrame.midY - size.height / 2)
        case .bottom: CGPoint(x: tabFrame.midX - size.width / 2, y: tabFrame.minY - gap - size.height)
        }
        origin.x = min(max(origin.x, visible.minX + 4), visible.maxX - size.width - 4)
        origin.y = min(max(origin.y, visible.minY + 4), visible.maxY - size.height - 4)

        panel.setFrame(ScreenGeometry.flip(CGRect(origin: origin, size: size)), display: true)
        panel.orderFrontRegardless()
    }

    func update(image: NSImage?) {
        if let image { model.image = image }
    }

    func hide() {
        panel.orderOut(nil)
    }
}

private struct PreviewView: View {
    let model: PreviewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let image = model.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack(spacing: 6) {
                if let icon = model.icon {
                    Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(model.title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                    if model.image == nil {
                        Text(model.appName).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.12), lineWidth: 0.5) }
    }
}
