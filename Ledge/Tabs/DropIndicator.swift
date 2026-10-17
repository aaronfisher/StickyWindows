import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class DropIndicatorModel {
    var edge: Edge = .right
    /// Ghost tab start along the strip, in points from the strip's top (or left, for the bottom edge).
    var ghostStart: CGFloat = 0
    /// Over an existing tab: the ghost sits on it and shows a "+" (drop to group).
    var isJoining = false
}

/// Translucent strip along an edge with a ghost tab where the drop will land.
@MainActor
final class DropIndicator {
    private let model = DropIndicatorModel()
    private let settings: SettingsStore
    private lazy var panel: NSPanel = {
        let panel = TabPanel(rootView: DropIndicatorView(model: model, settings: settings))
        panel.ignoresMouseEvents = true
        panel.hasShadow = false
        panel.alphaValue = 0
        return panel
    }()
    private var isVisible = false

    init(settings: SettingsStore) {
        self.settings = settings
    }

    /// `joining` is the AX frame of an existing tab the drop would join, if the cursor is over one.
    func show(for zone: EdgeZone, joining targetFrame: CGRect? = nil) {
        let full = ScreenGeometry.axFrame(of: zone.screen)
        let visible = ScreenGeometry.axVisibleFrame(of: zone.screen)
        let thickness = settings.tabMetrics.thickness
        let length = settings.tabMetrics.length

        let strip: CGRect = switch zone.edge {
        case .right: CGRect(x: full.maxX - thickness, y: visible.minY, width: thickness, height: visible.height)
        case .left: CGRect(x: full.minX, y: visible.minY, width: thickness, height: visible.height)
        case .bottom: CGRect(x: visible.minX, y: visible.maxY - thickness, width: visible.width, height: thickness)
        }
        let (stripStart, stripLength) = zone.edge.isVertical ? (strip.minY, strip.height) : (strip.minX, strip.width)
        var start = min(max(zone.offset - length / 2 - stripStart, 0), max(stripLength - length, 0))
        if let targetFrame {
            start = (zone.edge.isVertical ? targetFrame.minY : targetFrame.minX) - stripStart
        }
        model.isJoining = targetFrame != nil

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
            context.duration = settings.reduceMotion ? 0 : 0.12
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = settings.reduceMotion ? 0 : 0.1
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
    let settings: SettingsStore

    var body: some View {
        let vertical = model.edge.isVertical
        let ghost = EdgeTabView.shape(for: model.edge)
        let metrics = settings.tabMetrics
        let accent = settings.accentColor

        ZStack(alignment: alignment) {
            // Glow line hugging the screen edge.
            Rectangle()
                .fill(accent.opacity(0.55))
                .frame(width: vertical ? 3 : nil, height: vertical ? nil : 3)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)

            ghost
                .fill(accent.opacity(model.isJoining ? 0.5 : 0.32))
                .overlay { ghost.strokeBorder(accent.opacity(0.9), lineWidth: model.isJoining ? 2.5 : 1.5) }
                .overlay {
                    if model.isJoining {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white, accent)
                    }
                }
                .frame(
                    width: vertical ? metrics.thickness : metrics.length,
                    height: vertical ? metrics.length : metrics.thickness)
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
