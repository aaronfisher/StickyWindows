import AppKit

/// Tucks auto-tucking windows (Peek mode, or revealed by hover) back when they lose focus or the cursor leaves.
@MainActor
final class PeekMonitor {
    private unowned let manager: ParkingManager
    private var timer: Timer?
    private var ticks = 0

    /// How long the cursor may stray before the window tucks.
    private let leaveGrace: TimeInterval = 0.5
    /// Slack around the window and tab so brushing an edge doesn't count as leaving.
    private let margin: CGFloat = 10

    init(manager: ParkingManager) {
        self.manager = manager
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            MainActor.assumeIsolated { [weak self] in self?.poll() }
        }
    }

    /// Another app came forward: peeking windows of other apps go back.
    func appActivated(pid: pid_t) {
        for parkedWindow in settledCandidates() where parkedWindow.window.pid != pid {
            Task { await manager.tuck(parkedWindow) }
        }
    }

    /// Focus moved to a different window of the same app.
    func focusedWindowChanged(pid: pid_t) {
        guard let focused = WindowController.focusedWindow(forPID: pid) else { return }
        for parkedWindow in settledCandidates() where parkedWindow.window.pid == pid && !parkedWindow.window.isSameWindow(as: focused) {
            Task { await manager.tuck(parkedWindow) }
        }
    }

    private func candidates() -> [ParkedWindow] {
        manager.parked.filter { $0.isRevealed && !$0.isTransitioning && manager.autoTucks($0) }
    }

    /// Revealing activates the window's app, which can briefly report focus on another of its windows.
    private func settledCandidates() -> [ParkedWindow] {
        candidates().filter { Date().timeIntervalSince($0.session?.revealedAt ?? .distantPast) > 0.4 }
    }

    private func poll() {
        // AX reads here would compete with a sliding window for the main thread.
        guard !manager.isAnimating else { return }
        ticks += 1
        if ticks % 10 == 0 {
            manager.housekeeping()
        }

        // Mid-drag or mid-resize isn't "leaving".
        guard NSEvent.pressedMouseButtons == 0 else { return }
        let peeking = candidates()
        guard !peeking.isEmpty else { return }
        let mouse = ScreenGeometry.axPoint(fromAppKit: NSEvent.mouseLocation)
        let now = Date()

        for parkedWindow in peeking {
            guard var session = parkedWindow.session else { continue }
            let inWindow = parkedWindow.window.frame?.insetBy(dx: -margin, dy: -margin).contains(mouse) ?? false
            let inTab = manager.tabFrame(of: parkedWindow)?.insetBy(dx: -margin, dy: -margin).contains(mouse) ?? false

            if inWindow { session.cursorEnteredWindow = true }
            if inWindow || inTab {
                session.cursorOutsideSince = nil
            } else if session.trigger == .hover || session.cursorEnteredWindow {
                let since = session.cursorOutsideSince ?? now
                session.cursorOutsideSince = since
                if now.timeIntervalSince(since) >= leaveGrace {
                    Task { await manager.tuck(parkedWindow) }
                    continue
                }
            }
            parkedWindow.session = session
        }
    }
}
