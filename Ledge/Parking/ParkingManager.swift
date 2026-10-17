import AppKit
import Observation
import os

/// Source of truth for parked windows. Persistence arrives in M5.
@MainActor
@Observable
final class ParkingManager {
    private(set) var parked: [ParkedWindow] = []

    @ObservationIgnored let strategies = HidingStrategyStore()
    @ObservationIgnored var onNeedsPermission: () -> Void = {}
    @ObservationIgnored private lazy var tabs = TabPresenter(manager: self)
    @ObservationIgnored private let log = Logger(subsystem: "vc.start.Ledge", category: "parking")

    init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.tabs.layout() }
        }
    }

    // MARK: Parking

    func parkFrontmostWindow(to edge: Edge = .right) async {
        guard AXIsProcessTrusted() else { return onNeedsPermission() }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let window = WindowController.focusedWindow(forPID: app.processIdentifier),
              let frame = window.frame else {
            log.info("Park: no frontmost window")
            return NSSound.beep()
        }

        if let existing = parked.first(where: { $0.window.isSameWindow(as: window) }) {
            // Hotkey on an already parked, revealed window tucks it away again.
            if existing.isRevealed { await tuck(existing) }
            return
        }
        await park(window, edge: edge, screen: ScreenGeometry.screen(containing: frame))
    }

    /// Parks `window` on `edge` of `screen`.
    /// - Parameters:
    ///   - offset: Where along the edge the tab should sit (AX coordinates); defaults to the window's center.
    ///   - restoreFrame: Frame to reveal the window at; defaults to its current frame.
    ///   - settleDelay: Time to let macOS finish any edge-tiling it starts on mouse-up before hiding.
    func park(
        _ window: WindowController, edge: Edge, screen: NSScreen?,
        offset: CGFloat? = nil, restoreFrame: CGRect? = nil, settleDelay: Duration = .zero
    ) async {
        guard let current = window.frame else { return NSSound.beep() }
        let app = NSRunningApplication(processIdentifier: window.pid)
        guard !window.isFullScreen else {
            log.info("Park: \(app?.bundleIdentifier ?? "?", privacy: .public) window is full screen")
            return NSSound.beep()
        }

        // Re-parking a revealed window (dragged to an edge again) replaces its old tab.
        parked.removeAll { $0.window.isSameWindow(as: window) }

        let parkedWindow = ParkedWindow(
            window: window, app: app, frame: restoreFrame ?? current, edge: edge, screen: screen, offset: offset)
        parkedWindow.hiddenBy = .offscreen  // Tab shows as tucked right away; hide() sets the real method.
        parked.append(parkedWindow)
        tabs.sync()
        if settleDelay > .zero {
            try? await Task.sleep(for: settleDelay)
        }
        await hide(parkedWindow)
    }

    /// Tab click: reveal a tucked window, or tuck a revealed one (pop-out behavior).
    func toggle(_ parkedWindow: ParkedWindow) async {
        guard parkedWindow.window.isValid else { return remove(parkedWindow) }
        if parkedWindow.isRevealed {
            await tuck(parkedWindow)
        } else {
            reveal(parkedWindow)
        }
    }

    func reveal(_ parkedWindow: ParkedWindow) {
        guard parkedWindow.window.isValid else { return remove(parkedWindow) }
        if parkedWindow.hiddenBy == .minimize {
            parkedWindow.window.setMinimized(false)
        }
        parkedWindow.window.setFrame(parkedWindow.storedFrame)
        parkedWindow.window.raise()
        parkedWindow.hiddenBy = nil
    }

    func tuck(_ parkedWindow: ParkedWindow) async {
        guard parkedWindow.window.isValid else { return remove(parkedWindow) }
        // Keep whatever frame the user moved/resized it to while it was out.
        if let frame = parkedWindow.window.frame, ScreenGeometry.isVisible(frame) {
            parkedWindow.storedFrame = frame
        }
        if let title = parkedWindow.window.title, !title.isEmpty {
            parkedWindow.title = title
        }
        await hide(parkedWindow)
    }

    /// Restores the window to its frame and removes the tab.
    func release(_ parkedWindow: ParkedWindow) {
        if parkedWindow.window.isValid {
            if parkedWindow.hiddenBy == .minimize { parkedWindow.window.setMinimized(false) }
            parkedWindow.window.setFrame(parkedWindow.storedFrame)
        }
        remove(parkedWindow)
    }

    /// Synchronous so it can run from `applicationWillTerminate`; never leave windows stranded offscreen.
    func releaseAll() {
        for parkedWindow in parked {
            release(parkedWindow)
        }
    }

    func isParked(_ window: WindowController) -> Bool {
        parked.contains { $0.window.isSameWindow(as: window) }
    }

    private func remove(_ parkedWindow: ParkedWindow) {
        parked.removeAll { $0 === parkedWindow }
        tabs.sync()
    }

    // MARK: Hiding

    private func hide(_ parkedWindow: ParkedWindow) async {
        let window = parkedWindow.window

        if strategies.method(for: parkedWindow.bundleID) == .offscreen,
           let target = offscreenOrigin(for: parkedWindow) {
            // Undo any resize from macOS edge tiling so the offscreen frame matches the stored one.
            window.setSize(parkedWindow.storedFrame.size)
            window.setPosition(target)
            // Some apps re-clamp asynchronously, so check after they've had a moment.
            try? await Task.sleep(for: .milliseconds(150))
            if let frame = window.frame, !ScreenGeometry.isVisible(frame) {
                parkedWindow.hiddenBy = .offscreen
                return
            }
            log.notice("\(parkedWindow.bundleID ?? "?", privacy: .public) clamped offscreen move; using minimize")
            strategies.setMethod(.minimize, for: parkedWindow.bundleID)
            window.setFrame(parkedWindow.storedFrame)
        }

        window.setMinimized(true)
        parkedWindow.hiddenBy = .minimize
    }

    /// Just past the parked edge of the window's display, or past every display if another one sits beyond that edge.
    private func offscreenOrigin(for parkedWindow: ParkedWindow) -> CGPoint? {
        guard let screen = ScreenGeometry.screen(withDisplayID: parkedWindow.displayID) else { return nil }
        let screenFrame = ScreenGeometry.axFrame(of: screen)
        let union = ScreenGeometry.axUnion
        let frame = parkedWindow.storedFrame

        func origin(edgeOf bounds: CGRect) -> CGPoint {
            switch parkedWindow.edge {
            case .right: CGPoint(x: bounds.maxX, y: frame.minY)
            case .left: CGPoint(x: bounds.minX - frame.width, y: frame.minY)
            case .bottom: CGPoint(x: frame.minX, y: bounds.maxY)
            }
        }

        let nearEdge = origin(edgeOf: screenFrame)
        if !ScreenGeometry.intersectsAnyScreen(CGRect(origin: nearEdge, size: frame.size)) {
            return nearEdge
        }
        return origin(edgeOf: union)
    }
}
