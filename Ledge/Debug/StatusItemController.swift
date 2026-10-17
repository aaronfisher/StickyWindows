import AppKit

/// Owns the menu-bar item. The menu is rebuilt every time it opens so the debug window list is live.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let permission: AccessibilityPermission
    private let parking: ParkingManager
    private let tilingOverride: TilingOverride
    private let showOnboarding: () -> Void
    private var windowsByTag: [Int: WindowInfo] = [:]

    init(permission: AccessibilityPermission, parking: ParkingManager, tilingOverride: TilingOverride,
         showOnboarding: @escaping () -> Void) {
        self.permission = permission
        self.parking = parking
        self.tilingOverride = tilingOverride
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
        let park = item("Park Frontmost Window on Right Edge", action: #selector(parkFrontmost))
        park.keyEquivalent = String(Character(UnicodeScalar(NSRightArrowFunctionKey)!))
        park.keyEquivalentModifierMask = [.control, .option, .command]
        park.isEnabled = permission.isTrusted
        menu.addItem(park)

        menu.addItem(disabled("Or drag any window to the left, right, or bottom edge"))
        let modeMenu = NSMenu()
        for mode in RevealMode.allCases {
            let entry = ClosureMenuItem(mode.displayName, state: parking.settings.defaultRevealMode == mode ? .on : .off) {
                [parking] in parking.settings.defaultRevealMode = mode
            }
            entry.toolTip = mode == .popOut
                ? "Stays out until you click the tab again."
                : "Tucks back when the window loses focus or the cursor leaves it."
            modeMenu.addItem(entry)
        }
        let modeItem = NSMenuItem(title: "Default Reveal Mode", action: nil, keyEquivalent: "")
        modeItem.submenu = modeMenu
        menu.addItem(modeItem)
        menu.addItem(ClosureMenuItem("Hover Tabs to Peek", state: parking.settings.hoverToPeek ? .on : .off) {
            [parking] in parking.settings.hoverToPeek.toggle()
        })

        let override = item("Let Ledge Handle Left/Right Edge Drags", action: #selector(toggleTilingOverride))
        override.state = tilingOverride.isEnabled ? .on : .off
        override.toolTip = "Turns off macOS \"Drag windows to left or right edge of screen to tile\" while Ledge runs, and restores your setting when Ledge quits."
        menu.addItem(override)
        if MacOSTiling.isEdgeDragTilingEnabled {
            let hint = item("macOS edge tiling is on and may fight left/right drops…", action: #selector(openTilingSettings))
            hint.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
            hint.toolTip = "System Settings → Desktop & Dock → \"Drag windows to left or right edge of screen to tile\"."
            menu.addItem(hint)
        }

        if !parking.parked.isEmpty {
            menu.addItem(disabled("Parked (\(parking.parked.count))"))
            for parkedWindow in parking.parked {
                let entry = item("\(parkedWindow.appName) — \(truncate(parkedWindow.title, limit: 40))",
                                 action: #selector(releaseParked(_:)))
                entry.representedObject = parkedWindow.id
                entry.image = parkedWindow.icon.map(Self.menuIcon)
                entry.toolTip = "Release: restore the window and remove its tab. Hidden by \(parkedWindow.hiddenBy?.rawValue ?? "— (revealed)")."
                entry.indentationLevel = 1
                menu.addItem(entry)
            }
            menu.addItem(item("Release All", action: #selector(releaseAll)))
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
        menu.addItem(item("Recover Off-Screen Windows", action: #selector(recoverOffscreen)))
        menu.addItem(item("Reset Per-App Hiding Strategies", action: #selector(resetStrategies)))
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

    @objc private func parkFrontmost() {
        // Ledge never activates for its menu, so the frontmost app is still the user's.
        Task { await parking.parkFrontmostWindow(to: .right) }
    }

    @objc private func toggleTilingOverride() {
        tilingOverride.setEnabled(!tilingOverride.isEnabled)
    }

    @objc private func openTilingSettings() {
        MacOSTiling.openSettings()
    }

    @objc private func releaseParked(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let parkedWindow = parking.parked.first(where: { $0.id == id }) else { return }
        parking.release(parkedWindow)
    }

    @objc private func releaseAll() {
        parking.releaseAll()
    }

    @objc private func recoverOffscreen() {
        let count = WindowInventory.recoverOffscreenWindows(excluding: parking.isParked)
        let alert = NSAlert()
        alert.messageText = count == 0 ? "No stranded windows found" : "Moved \(count) window\(count == 1 ? "" : "s") back on screen"
        NSApp.activate()
        alert.runModal()
    }

    @objc private func resetStrategies() {
        parking.strategies.reset()
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
