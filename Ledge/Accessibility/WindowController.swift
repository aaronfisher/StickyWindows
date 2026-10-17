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
    var isValid: Bool {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value)
        return error != .invalidUIElement && error != .cannotComplete
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
    func raise() {
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        NSRunningApplication(processIdentifier: pid)?.activate()
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
        // A hung app shouldn't stall Ledge's main thread on every click.
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
