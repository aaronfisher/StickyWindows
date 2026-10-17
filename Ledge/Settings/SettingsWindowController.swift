import AppKit
import SwiftUI

/// Hosts the settings in a plain window: the SwiftUI `Settings` scene can't be opened reliably from an
/// agent (menu-bar-only) app.
@MainActor
final class SettingsWindowController {
    private let window: NSWindow

    init(rootView: SettingsView) {
        let controller = NSHostingController(rootView: rootView)
        window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        // A unified toolbar gives the split view its System Settings look: title beside the sidebar.
        window.toolbar = NSToolbar(identifier: "LedgeSettings")
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 760, height: 560))
        // Reopen where the user left it; first time, centered.
        if !window.setFrameUsingName("LedgeSettingsWindow") {
            window.center()
        }
        window.setFrameAutosaveName("LedgeSettingsWindow")
    }

    func show() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
