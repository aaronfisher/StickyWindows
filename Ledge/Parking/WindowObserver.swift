import AppKit

/// Watches global mouse events to spot another app's window being dragged into an edge zone.
@MainActor
final class WindowObserver {
    struct Drop {
        let window: WindowController
        let zone: EdgeZone
        /// The window's frame when the drag began; restored when it's revealed.
        let startFrame: CGRect
    }

    var onDrop: (Drop) -> Void = { _ in }
    /// A window drag that ended outside any edge zone: (window, frame when the drag began).
    var onWindowMoved: (WindowController, CGRect) -> Void = { _, _ in }
    private let settings: SettingsStore
    private var detector: EdgeZoneDetector {
        EdgeZoneDetector(enabledEdges: settings.enabledEdges)
    }

    private var monitors: [Any] = []
    private var drag: DragState?
    private var dwellTimer: Timer?
    private let indicator: DropIndicator

    init(settings: SettingsStore) {
        self.settings = settings
        indicator = DropIndicator(settings: settings)
    }

    private struct DragState {
        let window: WindowController
        let startFrame: CGRect
        var isMovingWindow = false
        var lastFrameCheck = Date.distantPast
        var zone: EdgeZone?
        var isArmed = false
    }

    func start() {
        guard monitors.isEmpty else { return }
        let handlers: [(NSEvent.EventTypeMask, (WindowObserver) -> Void)] = [
            (.leftMouseDown, { $0.mouseDown() }),
            (.leftMouseDragged, { $0.mouseDragged() }),
            (.leftMouseUp, { $0.mouseUp() }),
        ]
        for (mask, handler) in handlers {
            if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    handler(self)
                }
            }) {
                monitors.append(monitor)
            }
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        reset()
    }

    // MARK: Events

    private func mouseDown() {
        reset()
        guard AXIsProcessTrusted() else { return }
        let point = ScreenGeometry.axPoint(fromAppKit: NSEvent.mouseLocation)
        guard let window = WindowController.window(at: point),
              window.pid != ProcessInfo.processInfo.processIdentifier,
              let frame = window.frame, !window.isFullScreen else { return }
        drag = DragState(window: window, startFrame: frame)
    }

    private func mouseDragged() {
        guard var state = drag else { return }

        if !state.isMovingWindow {
            // Clicks and drags inside a window (text selection, sliders) also send these; only a moving window counts.
            let now = Date()
            guard now.timeIntervalSince(state.lastFrameCheck) >= 0.04 else { return }
            state.lastFrameCheck = now
            guard let frame = state.window.frame else { return reset() }
            let resized = abs(frame.width - state.startFrame.width) > 1 || abs(frame.height - state.startFrame.height) > 1
            if resized { return reset() }
            let moved = hypot(frame.minX - state.startFrame.minX, frame.minY - state.startFrame.minY)
            state.isMovingWindow = moved > 3
            drag = state
            guard state.isMovingWindow else { return }
        }

        updateZone()
    }

    private func mouseUp() {
        defer { reset() }
        guard let state = drag, state.isMovingWindow else { return }
        if state.isArmed, let zone = detector.zone(at: NSEvent.mouseLocation), zone.isSameZone(as: state.zone) {
            onDrop(Drop(window: state.window, zone: zone, startFrame: state.startFrame))
        } else {
            onWindowMoved(state.window, state.startFrame)
        }
    }

    // MARK: Zones

    private func updateZone() {
        guard var state = drag else { return }
        let zone = detector.zone(at: NSEvent.mouseLocation)

        if let zone, zone.isSameZone(as: state.zone) {
            state.zone = zone
            drag = state
            if state.isArmed { indicator.show(for: zone) }
            return
        }

        // Entered a new zone or left one: start over.
        dwellTimer?.invalidate()
        indicator.hide()
        state.zone = zone
        state.isArmed = false
        drag = state
        guard zone != nil else { return }

        dwellTimer = Timer.scheduledTimer(withTimeInterval: settings.dwellTime, repeats: false) { _ in
            MainActor.assumeIsolated { [weak self] in self?.dwellElapsed() }
        }
    }

    private func dwellElapsed() {
        // The cursor may have rested without new drag events, so re-check where it is now.
        guard var state = drag, state.isMovingWindow,
              let zone = detector.zone(at: NSEvent.mouseLocation), zone.isSameZone(as: state.zone) else { return }
        state.isArmed = true
        state.zone = zone
        drag = state
        indicator.show(for: zone)
    }

    private func reset() {
        dwellTimer?.invalidate()
        dwellTimer = nil
        drag = nil
        indicator.hide()
    }
}
