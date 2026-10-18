import AppKit
import ApplicationServices

/// Reads and presses an app's menu-bar commands through Accessibility.
@MainActor
enum AppMenu {
    /// A command as [menu title, item title], e.g. ["Window", "Message Viewer"].
    typealias Path = [String]

    /// Titles that usually bring back an app's main window, best first.
    private static let mainWindowTitles = [
        "Message Viewer", "Main Window", "Show Main Window", "Library", "Show Library",
        "New Viewer Window", "New Finder Window", "New Window",
    ]

    /// Enabled commands in the app's menus (the Apple menu and separators skipped).
    static func commands(pid: pid_t) -> [Path] {
        menus(pid: pid).flatMap { menuTitle, items in
            items.compactMap { item -> Path? in
                guard let title = string(item, kAXTitleAttribute), !title.isEmpty, bool(item, kAXEnabledAttribute) != false
                else { return nil }
                return [menuTitle, title]
            }
        }
    }

    /// The best guess at the command that shows the app's main window.
    static func automaticMainWindowCommand(pid: pid_t) -> Path? {
        let available = commands(pid: pid)
        for title in mainWindowTitles {
            if let match = available.first(where: { $0.last?.caseInsensitiveCompare(title) == .orderedSame }) {
                return match
            }
        }
        return nil
    }

    @discardableResult
    static func press(_ path: Path, pid: pid_t) -> Bool {
        guard path.count == 2,
              let items = menus(pid: pid).first(where: { $0.title == path[0] })?.items,
              let item = items.first(where: { string($0, kAXTitleAttribute) == path[1] }) else { return false }
        return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
    }

    // MARK: AX plumbing

    private static func menus(pid: pid_t) -> [(title: String, items: [AXUIElement])] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        guard let menuBar = element(app, kAXMenuBarAttribute) else { return [] }
        // The first menu-bar item is the Apple menu.
        return children(menuBar).dropFirst().compactMap { barItem in
            guard let title = string(barItem, kAXTitleAttribute), let menu = children(barItem).first else { return nil }
            return (title, children(menu))
        }
    }

    private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)  // swiftlint:disable:this force_cast
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? Bool
    }
}
