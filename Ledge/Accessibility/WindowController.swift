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
