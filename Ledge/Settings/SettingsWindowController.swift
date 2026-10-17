import AppKit
import SwiftUI

/// Hosts the settings in a plain window: the SwiftUI `Settings` scene can't be opened reliably from an
/// agent (menu-bar-only) app.
@MainActor
final class SettingsWindowController {
    private let window: NSWindow

    init(rootView: SettingsView) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Ledge Settings"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: rootView)
        window.center()
    }

    func show() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
