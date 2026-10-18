import AppKit
import ApplicationServices
import Observation

/// Tracks whether Sticky Windows has been granted Accessibility access, polling while it waits.
@MainActor
@Observable
final class AccessibilityPermission {
    private(set) var isTrusted: Bool = AXIsProcessTrusted()
    private var pollTimer: Timer?

    /// Shows the system prompt (once per app identity) and registers Sticky Windows in the Accessibility list.
    func requestAccess() {
        // Literal key avoids touching the non-Sendable `kAXTrustedCheckOptionPrompt` global under Swift 6.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        isTrusted = AXIsProcessTrustedWithOptions(options)
        startPolling()
    }

    func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
        startPolling()
    }

    func startPolling() {
        guard pollTimer == nil, !isTrusted else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            MainActor.assumeIsolated { [weak self] in self?.refresh() }
        }
    }

    func refresh() {
        isTrusted = AXIsProcessTrusted()
        if isTrusted {
            pollTimer?.invalidate()
            pollTimer = nil
        }
    }
}
