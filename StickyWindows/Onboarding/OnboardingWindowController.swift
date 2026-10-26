import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController {
    private let window: NSWindow

    init(permission: AccessibilityPermission, screenRecording: ScreenRecordingPermission, tilingOverride: TilingOverride, settings: SettingsStore) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 700),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: OnboardingView(permission: permission, screenRecording: screenRecording, tilingOverride: tilingOverride, settings: settings) { [weak window] in
            window?.close()
        })
        window.center()
    }

    func show() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
