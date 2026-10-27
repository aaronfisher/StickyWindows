import AppKit
import ApplicationServices
import OSLog

/// One of a window's own tabs (a browser tab, a Finder or Terminal tab, …) as the app exposes it to Accessibility.
struct WindowTab: Identifiable {
    let id: Int
    let element: AXUIElement
    let title: String
    let isSelected: Bool
}

/// Reads the tabs inside a window through the Accessibility API.
///
/// Safari, Chrome and the other Chromium browsers, Firefox, Finder, Terminal and most tabbed Mac apps expose
/// their tab strip as an `AXTabGroup` whose children are `AXRadioButton`s (one per tab, the selected one
/// has value 1). Pressing one switches to that tab. This works while the app is hidden, which is how parked
/// windows are stored, so the list can be read before the window is brought back.
@MainActor
enum WindowTabReader {
    /// How many elements of a window's tree to look at before giving up. Tab strips sit near the top of the
    /// tree; web content and document views are skipped, so this is plenty.
    private static let visitLimit = 250
    /// Subtrees that never contain a tab strip and can be huge.
    private static let log = Logger(subsystem: AppIdentity.id, category: "windowTabs")
    private static let skippedRoles: Set<String> = [
        "AXWebArea", "AXTable", "AXOutline", "AXList", "AXTextArea", "AXMenuBar",
    ]

    /// The window's tabs in strip order; empty when the app doesn't expose any.
    static func tabs(of window: WindowController) -> [WindowTab] {
        // A slow or hung app must not stall the hover; the app element's timeout covers all its elements.
        let app = AXUIElementCreateApplication(window.pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        defer { AXUIElementSetMessagingTimeout(app, 0) }

        var visited = 0
        let clock = Date()
        guard let group = findTabGroup(in: window.element, depth: 0, visited: &visited) else {
            log.debug("[window tabs] pid \(window.pid) no tab strip after \(visited) elements, \(Int(Date().timeIntervalSince(clock) * 1000))ms")
            log.debug("[window tabs] tree:\n\(dump(window.element), privacy: .public)")
            return []
        }
        let children = elements(of: group, kAXChildrenAttribute)
        var tabs: [WindowTab] = []
        for (index, child) in children.enumerated() {
            guard role(of: child) == kAXRadioButtonRole else { continue }
            let title = string(of: child, kAXTitleAttribute) ?? string(of: child, kAXDescriptionAttribute) ?? ""
            var value: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXValueAttribute as CFString, &value)
            let selected = (value as? Int) == 1 || (value as? Bool) == true
            tabs.append(WindowTab(id: index, element: child, title: title.isEmpty ? "Untitled" : title, isSelected: selected))
        }
        log.debug("[window tabs] pid \(window.pid) \(tabs.count) tabs after \(visited) elements, \(Int(Date().timeIntervalSince(clock) * 1000))ms")
        return tabs
    }

    /// Switches the window to `tab`, as if it were clicked. Returns false when the app refused.
    @discardableResult
    static func select(_ tab: WindowTab) -> Bool {
        AXUIElementPerformAction(tab.element, kAXPressAction as CFString) == .success
    }

    /// The top of the window's tree, for diagnosing apps whose tab strip isn't found.
    private static func dump(_ element: AXUIElement, depth: Int = 0, lines: inout [String]) {
        guard depth < 6, lines.count < 80 else { return }
        let role = role(of: element) ?? "?"
        let subrole = string(of: element, kAXSubroleAttribute).map { "(\($0))" } ?? ""
        let title = string(of: element, kAXTitleAttribute) ?? string(of: element, kAXDescriptionAttribute) ?? ""
        let children = elements(of: element, kAXChildrenAttribute)
        lines.append(String(repeating: "  ", count: depth) + "\(role)\(subrole) '\(title.prefix(40))' ×\(children.count)")
        if role == "AXWebArea" { return }
        for child in children { dump(child, depth: depth + 1, lines: &lines) }
    }

    private static func dump(_ element: AXUIElement) -> String {
        var lines: [String] = []
        dump(element, lines: &lines)
        return lines.joined(separator: "\n")
    }

    // MARK: Tree walk

    private static func findTabGroup(in element: AXUIElement, depth: Int, visited: inout Int) -> AXUIElement? {
        guard depth < 8, visited < visitLimit else { return nil }
        visited += 1
        let role = role(of: element)
        if role == kAXTabGroupRole {
            // Only a strip with real tabs counts; some apps use AXTabGroup for a lone content pane.
            if elements(of: element, kAXChildrenAttribute).contains(where: { self.role(of: $0) == kAXRadioButtonRole }) {
                return element
            }
            return nil
        }
        if let role, skippedRoles.contains(role) { return nil }
        for child in elements(of: element, kAXChildrenAttribute) {
            if let found = findTabGroup(in: child, depth: depth + 1, visited: &visited) { return found }
            if visited >= visitLimit { break }
        }
        return nil
    }

    private static func role(of element: AXUIElement) -> String? {
        string(of: element, kAXRoleAttribute)
    }

    private static func string(of element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func elements(of element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let array = value as? [AXUIElement] else { return [] }
        return array
    }
}
