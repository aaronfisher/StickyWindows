import ApplicationServices
import Foundation
import os

/// Applies window moves on a background queue, always to the newest requested position. A busy app then
/// just skips stale positions instead of stalling Sticky Windows' main thread (and every later frame) on each move.
final class AXWindowMover: @unchecked Sendable {
    struct Stats {
        var moves = 0
        var axTotal: Double = 0
        var axMax: Double = 0
    }

    private struct State {
        var pending: CGPoint?
        var inFlight = false
        var stats = Stats()
    }

    // AXUIElement isn't Sendable, but it's only ever touched on `queue`.
    private let element: AXUIElement
    private let queue = DispatchQueue(label: "\(AppIdentity.id).window-mover", qos: .userInteractive)
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(element: AXUIElement) {
        self.element = element
    }

    func move(to point: CGPoint) {
        let shouldStart = state.withLock { state -> Bool in
            state.pending = point
            guard !state.inFlight else { return false }
            state.inFlight = true
            return true
        }
        if shouldStart {
            queue.async { self.drain() }
        }
    }

    /// Resumes once every requested move has been applied.
    func flush() async {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume() }
        }
    }

    var stats: Stats { state.withLock { $0.stats } }

    private func drain() {
        while let point = nextPoint() {
            var point = point
            let start = CFAbsoluteTimeGetCurrent()
            if let value = AXValueCreate(.cgPoint, &point) {
                AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
            }
            let duration = CFAbsoluteTimeGetCurrent() - start
            state.withLock {
                $0.stats.moves += 1
                $0.stats.axTotal += duration
                $0.stats.axMax = max($0.stats.axMax, duration)
            }
        }
    }

    /// Takes the newest pending point, or marks the mover idle when there's none (atomically, so a move
    /// arriving in between is never lost).
    private func nextPoint() -> CGPoint? {
        state.withLock { state in
            guard let point = state.pending else {
                state.inFlight = false
                return nil
            }
            state.pending = nil
            return point
        }
    }
}
