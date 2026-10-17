import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class DropIndicatorModel {
    var edge: Edge = .right
    /// Ghost tab start along the strip, in points from the strip's top (or left, for the bottom edge).
    var ghostStart: CGFloat = 0
}

/// Translucent strip along an edge with a ghost tab where the drop will land.
@MainActor
final class DropIndicator {
    private let model = DropIndicatorModel()
    private lazy var panel: NSPanel = {
        let panel = TabPanel(rootView: DropIndicatorView(model: model))
        panel.ignoresMouseEvents = true
        panel.hasShadow = false
        panel.alphaValue = 0
        return panel
    }()
    private var isVisible = false

    func show(for zone: EdgeZone) {
        let full = ScreenGeometry.axFrame(of: zone.screen)
        let visible = ScreenGeometry.axVisibleFrame(of: zone.screen)
        let thickness = EdgeTabView.thickness
        let length = EdgeTabView.length

        let strip: CGRect = switch zone.edge {
        case .right: CGRect(x: full.maxX - thickness, y: visible.minY, width: thickness, height: visible.height)
        case .left: CGRect(x: full.minX, y: visible.minY, width: thickness, height: visible.height)
        case .bottom: CGRect(x: visible.minX, y: visible.maxY - thickness, width: visible.width, height: thickness)
        }
        let (stripStart, stripLength) = zone.edge.isVertical ? (strip.minY, strip.height) : (strip.minX, strip.width)
        let start = min(max(zone.offset - length / 2 - stripStart, 0), max(stripLength - length, 0))

        let edgeChanged = model.edge != zone.edge || !isVisible
        model.edge = zone.edge
        if edgeChanged {
            // Jump straight to the spot when appearing; only animate while following the cursor.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { model.ghostStart = start }
        } else {
            model.ghostStart = start
        }

        panel.setFrame(ScreenGeometry.flip(strip), display: true)
        panel.orderFrontRegardless()
        guard !isVisible else { return }
        isVisible = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.12
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.1
            panel.animator().alphaValue = 0
        } completionHandler: { [panel] in
            MainActor.assumeIsolated {
                if panel.alphaValue == 0 { panel.orderOut(nil) }
            }
        }
    }
}

private struct DropIndicatorView: View {
    let model: DropIndicatorModel

    var body: some View {
        let vertical = model.edge.isVertical
        let ghost = EdgeTabView.shape(for: model.edge)

        ZStack(alignment: alignment) {
            // Glow line hugging the screen edge.
            Rectangle()
                .fill(Color.accentColor.opacity(0.55))
                .frame(width: vertical ? 3 : nil, height: vertical ? nil : 3)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)

            ghost
                .fill(Color.accentColor.opacity(0.32))
                .overlay { ghost.strokeBorder(Color.accentColor.opacity(0.9), lineWidth: 1.5) }
                .frame(
                    width: vertical ? EdgeTabView.thickness : EdgeTabView.length,
                    height: vertical ? EdgeTabView.length : EdgeTabView.thickness)
                .offset(x: vertical ? 0 : model.ghostStart, y: vertical ? model.ghostStart : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .animation(.spring(duration: 0.18), value: model.ghostStart)
    }

    private var alignment: Alignment {
        switch model.edge {
        case .right: .trailing
        case .left: .leading
        case .bottom: .bottom
        }
    }
}
