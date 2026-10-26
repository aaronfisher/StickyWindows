import AppKit
import Observation
import SwiftUI

/// The small amber "fourth light" drawn beside a revealed parked window's traffic lights. Click tucks the
/// window back into its tab; Option-click releases it.
@MainActor
final class TuckButtonController {
    private unowned let manager: ParkingManager
    private var panels: [UUID: TabPanel] = [:]
    private var models: [UUID: TuckButtonModel] = [:]
    /// Windows that moved recently: the button hides during a drag and comes back once it settles.
    private var settleTasks: [UUID: Task<Void, Never>] = [:]
    private var hiddenWhileMoving: Set<UUID> = []
    /// The size of the panel; the dot is drawn inside with room to grow on hover.
    private let panelSize: CGFloat = 22

    init(manager: ParkingManager) {
        self.manager = manager
    }

    /// Re-evaluates every revealed window: shown only for the active app's focused window.
    func refresh() {
        let settings = manager.settings
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        var wanted: [UUID: ParkedWindow] = [:]
        if settings.showTuckButton, let frontPID, let focused = WindowController.focusedWindow(forPID: frontPID) {
            for window in manager.parked
            where window.isRevealed && !window.isTransitioning && !hiddenWhileMoving.contains(window.id)
                && window.window.pid == frontPID && window.window.isSameWindow(as: focused) {
                wanted[window.id] = window
            }
        }
        for (id, panel) in panels where wanted[id] == nil {
            panel.orderOut(nil)
            panels[id] = nil
            models[id] = nil
        }
        for (id, window) in wanted {
            guard let frame = buttonFrame(for: window) else {
                panels[id]?.orderOut(nil)
                continue
            }
            let panel = panels[id] ?? makePanel(for: window)
            models[id]?.edge = window.edge
            panel.setFrame(ScreenGeometry.flip(frame), display: true)
            panel.orderFrontRegardless()
        }
    }

    /// The window moved or resized: hide until it has been still for a moment.
    func windowMoved(_ window: ParkedWindow) {
        guard window.isRevealed else { return }
        hiddenWhileMoving.insert(window.id)
        panels[window.id]?.orderOut(nil)
        settleTasks[window.id]?.cancel()
        settleTasks[window.id] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, !Task.isCancelled else { return }
            self.hiddenWhileMoving.remove(window.id)
            self.refresh()
        }
    }

    /// Just right of the zoom (green) button, in AX coordinates; falls back to the window's top-left corner.
    private func buttonFrame(for window: ParkedWindow) -> CGRect? {
        guard let windowFrame = window.window.frame else { return nil }
        let anchor: CGPoint
        if let zoom = window.window.zoomButtonFrame, zoom.width > 0 {
            anchor = CGPoint(x: zoom.maxX + 8, y: zoom.midY)
        } else {
            anchor = CGPoint(x: windowFrame.minX + 72, y: windowFrame.minY + 18)
        }
        // Keep it on the window and on a screen.
        let rect = CGRect(x: anchor.x, y: anchor.y - panelSize / 2, width: panelSize, height: panelSize)
        guard windowFrame.intersects(rect), ScreenGeometry.intersectsAnyScreen(rect) else { return nil }
        return rect
    }

    private func makePanel(for window: ParkedWindow) -> TabPanel {
        let model = TuckButtonModel(edge: window.edge)
        models[window.id] = model
        let panel = TabPanel(rootView: TuckButtonView(model: model, settings: manager.settings))
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = manager.settings.tabsOnAllSpaces
            ? [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            : [.managed, .ignoresCycle, .fullScreenAuxiliary]
        let view = panel.hostingView
        view.toolTip = "Tuck to \(window.edge.displayName.lowercased()) edge  ·  ⌥-click to release"
        view.onHover = { model.isHovered = $0 }
        view.onClick = { [weak self] in
            guard let self else { return }
            if NSEvent.modifierFlags.contains(.option) {
                self.manager.release(window)
            } else {
                Task { await self.manager.tuck(window) }
            }
        }
        panels[window.id] = panel
        return panel
    }
}

@MainActor
@Observable
final class TuckButtonModel {
    var edge: Edge
    var isHovered = false
    init(edge: Edge) { self.edge = edge }
}

/// Drawn like a traffic light: a 12 pt amber dot with a chevron toward the parked edge.
struct TuckButtonView: View {
    let model: TuckButtonModel
    let settings: SettingsStore

    private var chevron: String {
        switch model.edge {
        case .right: "chevron.right"
        case .left: "chevron.left"
        case .bottom: "chevron.down"
        }
    }

    var body: some View {
        let amber = Color(red: 1, green: 0.71, blue: 0.23)
        let size: CGFloat = model.isHovered ? 14 : 12
        ZStack {
            Circle()
                .fill(amber)
                .overlay(Circle().strokeBorder(Color(red: 0.82, green: 0.55, blue: 0.1), lineWidth: 0.5))
                .frame(width: size, height: size)
                .shadow(color: amber.opacity(model.isHovered ? 0.55 : 0), radius: 4)
            Image(systemName: chevron)
                .font(.system(size: model.isHovered ? 8 : 7, weight: .black))
                .foregroundStyle(Color(red: 0.35, green: 0.2, blue: 0))
                .opacity(model.isHovered ? 1 : 0.85)
        }
        .frame(width: 22, height: 22)
        .contentShape(Rectangle())
        .animation(settings.reduceMotion ? nil : .easeOut(duration: 0.12), value: model.isHovered)
    }
}

/// A small static drawing of the traffic lights plus the tuck button, for onboarding and Settings.
struct TuckButtonIllustration: View {
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(Color(red: 1, green: 0.37, blue: 0.34)).frame(width: 12, height: 12)
            Circle().fill(Color(red: 1, green: 0.74, blue: 0.18)).frame(width: 12, height: 12)
            Circle().fill(Color(red: 0.16, green: 0.78, blue: 0.25)).frame(width: 12, height: 12)
            ZStack {
                Circle().fill(Color(red: 1, green: 0.71, blue: 0.23)).frame(width: 12, height: 12)
                Image(systemName: "chevron.right").font(.system(size: 7, weight: .black))
                    .foregroundStyle(Color(red: 0.35, green: 0.2, blue: 0))
            }
            .padding(.leading, 6)
            Text("Window title").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.leading, 20)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(Color(nsColor: .windowBackgroundColor), in: UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8))
        .overlay(UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8).strokeBorder(.primary.opacity(0.15), lineWidth: 0.5))
    }
}
