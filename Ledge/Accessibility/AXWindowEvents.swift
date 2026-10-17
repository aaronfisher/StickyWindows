import AppKit
import ApplicationServices

/// AXObserver notifications for parked windows: destroyed, retitled, and app focus changes.
@MainActor
final class AXWindowEvents {
    enum Event {
        case destroyed
        case titleChanged
        case focusedWindowChanged
    }

    var handler: (Event, AXUIElement, pid_t) -> Void = { _, _, _ in }

    private var observers: [pid_t: AXObserver] = [:]
    private var watchCounts: [pid_t: Int] = [:]

    func watch(_ window: WindowController) {
        let pid = window.pid
        guard let observer = observers[pid] ?? makeObserver(for: pid) else { return }
        add(kAXUIElementDestroyedNotification, on: window.element, to: observer)
        add(kAXTitleChangedNotification, on: window.element, to: observer)
        watchCounts[pid, default: 0] += 1
    }

    func unwatch(_ window: WindowController) {
        let pid = window.pid
        guard let observer = observers[pid] else { return }
        AXObserverRemoveNotification(observer, window.element, kAXUIElementDestroyedNotification as CFString)
        AXObserverRemoveNotification(observer, window.element, kAXTitleChangedNotification as CFString)
        watchCounts[pid, default: 1] -= 1
        if watchCounts[pid] == 0 {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
            observers[pid] = nil
            watchCounts[pid] = nil
        }
    }

    /// Drops everything for an app that quit; its elements are dead anyway.
    func forget(pid: pid_t) {
        if let observer = observers[pid] {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observers[pid] = nil
        watchCounts[pid] = nil
    }

    private func makeObserver(for pid: pid_t) -> AXObserver? {
        var observer: AXObserver?
        let callback: AXObserverCallback = { _, element, notification, refcon in
            guard let refcon else { return }
            // Delivered on the main run loop, where the source is installed.
            let events = Unmanaged<AXWindowEvents>.fromOpaque(refcon).takeUnretainedValue()
            let name = notification as String
            nonisolated(unsafe) let element = element
            MainActor.assumeIsolated { events.dispatch(name, element: element) }
        }
        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { return nil }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        add(kAXFocusedWindowChangedNotification, on: AXUIElementCreateApplication(pid), to: observer)
        observers[pid] = observer
        return observer
    }

    private func add(_ notification: String, on element: AXUIElement, to observer: AXObserver) {
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(observer, element, notification as CFString, refcon)
    }

    private func dispatch(_ name: String, element: AXUIElement) {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        let event: Event? = switch name {
        case kAXUIElementDestroyedNotification: .destroyed
        case kAXTitleChangedNotification: .titleChanged
        case kAXFocusedWindowChangedNotification: .focusedWindowChanged
        default: nil
        }
        if let event { handler(event, element, pid) }
    }
}
