import AppKit
import ApplicationServices

/// Thin wrapper over an `AXUIElement` window. Per-app quirks will accumulate here (see QUIRKS.md).
@MainActor
struct WindowController {
    let element: AXUIElement
    let pid: pid_t

    var title: String? { attribute(kAXTitleAttribute) as String? }
    var isMinimized: Bool { attribute(kAXMinimizedAttribute) as Bool? ?? false }
    var subrole: String? { attribute(kAXSubroleAttribute) as String? }
    var isFullScreen: Bool { attribute("AXFullScreen") as Bool? ?? false }

    /// False once the window has been closed or its app has quit.
    ///
    /// Only a definitive "invalid element" counts. A timed-out or failed request (`.cannotComplete`) means the
    /// app is busy or still waking up, not that the window is gone; treating it as gone dropped tabs after sleep.
    var isValid: Bool {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value)
        return error != .invalidUIElement
    }

    /// True when the app answered the last request; false while it's unresponsive (e.g. right after wake).
    var isResponding: Bool {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) != .cannotComplete
    }

    func isSameWindow(as other: WindowController) -> Bool {
        CFEqual(element, other.element)
    }

    /// Frame in global top-left-origin coordinates (same space as CGWindowList bounds).
    var frame: CGRect? {
        guard let position = axValue(kAXPositionAttribute, type: .cgPoint, as: CGPoint.self),
              let size = axValue(kAXSizeAttribute, type: .cgSize, as: CGSize.self) else { return nil }
        return CGRect(origin: position, size: size)
    }

    /// Brings the window to the front and activates its app.
    /// Frame of the zoom (green) button in AX coordinates, used to place the tuck button beside the lights.
    var zoomButtonFrame: CGRect? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXZoomButtonAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        // swiftlint:disable:next force_cast
        let button = WindowController(element: value as! AXUIElement, pid: pid)
        return button.frame
    }

    /// Brings the window to the front. Without `activating`, its app isn't made active, which avoids the
    /// app's activation work (tens of ms in Xcode) landing in the middle of an animation.
    func raise(activating: Bool = true) {
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        if activating {
            NSRunningApplication(processIdentifier: pid)?.activate()
        }
    }

    @discardableResult
    func setPosition(_ point: CGPoint) -> Bool {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else { return false }
        return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value) == .success
    }

    @discardableResult
    func setSize(_ size: CGSize) -> Bool {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value) == .success
    }

    /// Position, size, then position again: moving across displays can resize before the move lands.
    func setFrame(_ frame: CGRect) {
        setPosition(frame.origin)
        setSize(frame.size)
        setPosition(frame.origin)
    }

    /// Presses the window's close button, as if the user clicked it. Returns false if there isn't one.
    @discardableResult
    func close() -> Bool {
        var button: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXCloseButtonAttribute as CFString, &button) == .success,
              let button, CFGetTypeID(button) == AXUIElementGetTypeID() else { return false }
        // swiftlint:disable:next force_cast
        return AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString) == .success
    }

    func setMinimized(_ minimized: Bool) {
        AXUIElementSetAttributeValue(
            element, kAXMinimizedAttribute as CFString, minimized ? kCFBooleanTrue : kCFBooleanFalse)
    }

    static func focusedWindow(forPID pid: pid_t) -> WindowController? {
        let app = AXUIElementCreateApplication(pid)
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(app, attribute as CFString, &value) == .success,
               let value, CFGetTypeID(value) == AXUIElementGetTypeID() {
                // swiftlint:disable:next force_cast
                return WindowController(element: value as! AXUIElement, pid: pid)
            }
        }
        return nil
    }

    /// The window under a point in AX coordinates, if any.
    static func window(at point: CGPoint) -> WindowController? {
        let systemWide = AXUIElementCreateSystemWide()
        // A hung app shouldn't stall Sticky Windows' main thread on every click.
        AXUIElementSetMessagingTimeout(systemWide, 0.25)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &hit) == .success,
              let hit else { return nil }
        var pid: pid_t = 0
        AXUIElementGetPid(hit, &pid)

        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(hit, kAXRoleAttribute as CFString, &role)
        if role as? String == kAXWindowRole {
            return WindowController(element: hit, pid: pid)
        }
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(hit, kAXWindowAttribute as CFString, &window) == .success,
              let window, CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        // swiftlint:disable:next force_cast
        return WindowController(element: window as! AXUIElement, pid: pid)
    }

    static func windows(forPID pid: pid_t) -> [WindowController] {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let elements = value as? [AXUIElement] else { return [] }
        return elements.map { WindowController(element: $0, pid: pid) }
    }

    private func attribute<T>(_ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    private func axValue<T>(_ name: String, type: AXValueType, as: T.Type) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { pointer.deallocate() }
        // swiftlint:disable:next force_cast
        guard AXValueGetValue(value as! AXValue, type, pointer) else { return nil }
        return pointer.pointee
    }
}
