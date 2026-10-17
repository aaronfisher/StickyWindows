import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController {
    private let window: NSWindow

    init(permission: AccessibilityPermission) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 400),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: OnboardingView(permission: permission) { [weak window] in
            window?.close()
        })
        window.center()
    }

    func show() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
