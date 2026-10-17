import AppKit
import QuartzCore

/// Runs one window slide, stepping exactly once per display refresh (CADisplayLink), so motion is even
/// instead of drifting against the screen's refresh like a timer does.
@MainActor
final class WindowSlideAnimator: NSObject {
    private let duration: CFTimeInterval
    private let step: (Double) -> Void
    private var startTime: CFTimeInterval?
    private var link: CADisplayLink?
    private var continuation: CheckedContinuation<Void, Never>?

    /// `step` gets linear progress 0...1 and is called a final time with exactly 1.
    init(duration: CFTimeInterval, step: @escaping (Double) -> Void) {
        self.duration = duration
        self.step = step
    }

    func run(on screen: NSScreen?) async {
        guard let screen = screen ?? NSScreen.main else {
            step(1)
            return
        }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            let link = screen.displayLink(target: self, selector: #selector(tick(_:)))
            link.add(to: .main, forMode: .common)
            self.link = link
        }
    }

    @objc private func tick(_ link: CADisplayLink) {
        let start = startTime ?? link.timestamp
        startTime = start
        // Aim at when this frame will actually be on screen.
        let t = min(1, max(0, (link.targetTimestamp - start) / duration))
        step(t)
        guard t >= 1 else { return }
        link.invalidate()
        self.link = nil
        continuation?.resume()
        continuation = nil
    }
}
