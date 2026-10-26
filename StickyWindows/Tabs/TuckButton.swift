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
    /// The panel holds the handle with room to grow on hover; the bottom `overlap` points sit on the window.
    private let panelSize = CGSize(width: 56, height: 22)
    private let overlap: CGFloat = 3

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

    /// A handle on the window's top edge, centered above the traffic lights, in AX coordinates. Outside the
    /// window, so it never collides with toolbars or tabs an app draws beside its lights. Overlaps the window
    /// by a few points so it reads as attached. Nil when there's no room above (window against the menu bar).
    private func buttonFrame(for window: ParkedWindow) -> CGRect? {
        guard let windowFrame = window.window.frame else { return nil }
        let centerX: CGFloat
        if let close = window.window.closeButtonFrame, let zoom = window.window.zoomButtonFrame, zoom.width > 0 {
            centerX = (close.minX + zoom.maxX) / 2
        } else {
            centerX = windowFrame.minX + 38
        }
        let rect = CGRect(x: centerX - panelSize.width / 2, y: windowFrame.minY - panelSize.height + overlap,
                          width: panelSize.width, height: panelSize.height)
        guard let screen = ScreenGeometry.screen(containing: windowFrame) else { return nil }
        let visible = ScreenGeometry.axVisibleFrame(of: screen)
        guard rect.minY >= visible.minY - 1 else { return nil }
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

/// The handle: a small amber pull-tab with rounded top corners and a chevron toward the parked edge,
/// drawn at the bottom of its panel so it sits on the window's top edge.
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
        let width: CGFloat = model.isHovered ? 44 : 36
        let height: CGFloat = model.isHovered ? 15 : 12
        let shape = UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6, style: .continuous)
        VStack {
            Spacer(minLength: 0)
            ZStack {
                shape.fill(amber)
                    .overlay(shape.strokeBorder(Color(red: 0.82, green: 0.55, blue: 0.1), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.18), radius: 2, y: -1)
                    .shadow(color: amber.opacity(model.isHovered ? 0.5 : 0), radius: 5)
                Image(systemName: chevron)
                    .font(.system(size: model.isHovered ? 9 : 8, weight: .black))
                    .foregroundStyle(Color(red: 0.35, green: 0.2, blue: 0))
                    .opacity(model.isHovered ? 1 : 0.85)
            }
            .frame(width: width, height: height)
        }
        .frame(width: 56, height: 22)
        .contentShape(Rectangle())
        .animation(settings.reduceMotion ? nil : .easeOut(duration: 0.12), value: model.isHovered)
    }
}

/// A small static drawing of a window corner with the handle above its traffic lights, for onboarding and Settings.
struct TuckButtonIllustration: View {
    var body: some View {
        let amber = Color(red: 1, green: 0.71, blue: 0.23)
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                Color.clear.frame(height: 10)
                HStack(spacing: 8) {
                    Circle().fill(Color(red: 1, green: 0.37, blue: 0.34)).frame(width: 12, height: 12)
                    Circle().fill(Color(red: 1, green: 0.74, blue: 0.18)).frame(width: 12, height: 12)
                    Circle().fill(Color(red: 0.16, green: 0.78, blue: 0.25)).frame(width: 12, height: 12)
                    Text("Window title").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.leading, 24)
                }
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(Color(nsColor: .windowBackgroundColor), in: UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8))
                .overlay(UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8).strokeBorder(.primary.opacity(0.15), lineWidth: 0.5))
            }
            // The handle, centered above the three lights, overlapping the window's top edge.
            ZStack {
                UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6, style: .continuous).fill(amber)
                Image(systemName: "chevron.right").font(.system(size: 8, weight: .black))
                    .foregroundStyle(Color(red: 0.35, green: 0.2, blue: 0))
            }
            .frame(width: 36, height: 12)
            .offset(x: 12 + 26 - 18, y: 1)
        }
        .frame(height: 44)
    }
}
