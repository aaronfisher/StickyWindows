import AppKit

/// Owns the menu-bar item. The menu is rebuilt every time it opens so the debug window list is live.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let permission: AccessibilityPermission
    private let showOnboarding: () -> Void
    private var windowsByTag: [Int: WindowInfo] = [:]

    init(permission: AccessibilityPermission, showOnboarding: @escaping () -> Void) {
        self.permission = permission
        self.showOnboarding = showOnboarding
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "sidebar.right", accessibilityDescription: "Ledge")
            button.image?.isTemplate = true
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        permission.refresh()
        menu.removeAllItems()
        windowsByTag.removeAll()

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        menu.addItem(disabled("Ledge \(version)"))

        if permission.isTrusted {
            menu.addItem(disabled("Accessibility: Granted", symbol: "checkmark.circle.fill"))
        } else {
            menu.addItem(disabled("Accessibility: Not granted", symbol: "exclamationmark.triangle.fill"))
            menu.addItem(item("Grant Accessibility Access…", action: #selector(openOnboarding)))
        }

        menu.addItem(.separator())
        let debugItem = NSMenuItem(title: "Debug", action: nil, keyEquivalent: "")
        debugItem.submenu = buildDebugMenu()
        menu.addItem(debugItem)

        menu.addItem(.separator())
        menu.addItem(item("Show Onboarding…", action: #selector(openOnboarding)))
        let quit = NSMenuItem(title: "Quit Ledge", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func buildDebugMenu() -> NSMenu {
        let menu = NSMenu()
        let windows = WindowInventory.onScreenWindows()

        menu.addItem(disabled("On-Screen Windows (\(windows.count))"))
        if !permission.isTrusted {
            menu.addItem(disabled("Titles need Accessibility access"))
        }

        for (tag, window) in windows.enumerated() {
            windowsByTag[tag] = window
            let size = "\(Int(window.frame.width))×\(Int(window.frame.height))"
            let title = window.title.map { "\(window.appName) — \(truncate($0))" } ?? window.appName
            let entry = item("\(title)  (\(size))", action: #selector(raiseWindow(_:)))
            entry.tag = tag
            entry.image = window.icon.map(Self.menuIcon)
            entry.toolTip = """
                \(window.bundleID ?? "no bundle ID") · pid \(window.pid) · window \(window.id)
                frame \(Int(window.frame.minX)),\(Int(window.frame.minY)) \(size)
                AX match: \(window.controller == nil ? "no" : "yes")
                """
            if window.controller == nil {
                // Without an AX element we can't raise it; keep it visible but inert.
                entry.action = nil
            }
            menu.addItem(entry)
        }

        menu.addItem(.separator())
        menu.addItem(item("Copy Window List", action: #selector(copyWindowList)))
        return menu
    }

    @objc private func raiseWindow(_ sender: NSMenuItem) {
        windowsByTag[sender.tag]?.controller?.raise()
    }

    @objc private func copyWindowList() {
        let lines = WindowInventory.onScreenWindows().map { w in
            let f = w.frame
            return [
                w.appName, w.bundleID ?? "-", "pid \(w.pid)", "win \(w.id)",
                "\(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))x\(Int(f.height))",
                w.controller == nil ? "AX: no" : "AX: yes",
                w.title.map { "\"\($0)\"" } ?? "",
            ].joined(separator: "\t")
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }

    @objc private func openOnboarding() {
        showOnboarding()
    }

    private func item(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func disabled(_ title: String, symbol: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        if let symbol {
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
        return item
    }

    private func truncate(_ s: String, limit: Int = 60) -> String {
        s.count > limit ? String(s.prefix(limit - 1)) + "…" : s
    }

    private static func menuIcon(_ image: NSImage) -> NSImage {
        let copy = image.copy() as! NSImage  // swiftlint:disable:this force_cast
        copy.size = NSSize(width: 16, height: 16)
        return copy
    }
}
