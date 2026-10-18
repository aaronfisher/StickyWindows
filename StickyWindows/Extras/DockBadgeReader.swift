import AppKit
import ApplicationServices

/// Reads Dock badges (unread counts and the like) from the Dock's accessibility tree:
/// each Dock item exposes its app URL (`AXURL`) and badge text (`AXStatusLabel`).
@MainActor
final class DockBadgeReader {
    private var bundleIDsByURL: [URL: String] = [:]

    /// Badge text by bundle ID, for apps that currently show one.
    func badges() -> [String: String] {
        guard AXIsProcessTrusted(),
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return [:] }
        let dockElement = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(dockElement, 0.2)

        var result: [String: String] = [:]
        for list in children(of: dockElement) where role(of: list) == kAXListRole {
            for item in children(of: list) {
                guard let label = string(item, "AXStatusLabel"), !label.isEmpty,
                      let url = url(item, kAXURLAttribute), let bundleID = bundleID(for: url) else { continue }
                result[bundleID] = label
            }
        }
        return result
    }

    private func bundleID(for url: URL) -> String? {
        if let cached = bundleIDsByURL[url] { return cached }
        let bundleID = Bundle(url: url)?.bundleIdentifier
        bundleIDsByURL[url] = bundleID
        return bundleID
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    private func role(of element: AXUIElement) -> String? {
        string(element, kAXRoleAttribute)
    }

    private func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func url(_ element: AXUIElement, _ attribute: String) -> URL? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? URL
    }
}
