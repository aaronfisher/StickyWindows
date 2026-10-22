import AppKit
import Observation
import os

/// Screen Recording access, which live hover previews need. Optional: without it previews show icon + title.
///
/// macOS applies a Screen Recording grant only to a fresh launch, and a running process keeps seeing
/// "not granted" until then, so there is nothing to poll: the flow is request → user turns it on → relaunch.
@MainActor
@Observable
final class ScreenRecordingPermission {
    private(set) var isGranted: Bool
    /// The user asked for it during this run; the answer only shows after a relaunch. Never persisted: a fresh
    /// launch without the grant must offer to ask macOS again.
    private(set) var awaitingRelaunch = false

    /// Set when a request was made, so the checklist reopens after the relaunch to show the result.
    private static let reopenKey = "screenRecordingReopenOnboarding"
    private let log = Logger(subsystem: AppIdentity.id, category: "permissions")

    init() {
        isGranted = CGPreflightScreenCaptureAccess()
    }

    /// True right after a relaunch that followed a request: the onboarding should reopen to show the result.
    var shouldReopenOnboarding: Bool {
        UserDefaults.standard.bool(forKey: Self.reopenKey)
    }

    /// Asks macOS. The first time this shows the system prompt and registers the app in the Screen Recording
    /// list; later calls return the stored answer without a prompt, so System Settings is opened as well.
    func request() {
        let granted = CGRequestScreenCaptureAccess()
        log.notice("Screen Recording request returned \(granted, privacy: .public)")
        isGranted = granted
        guard !granted else { return }
        UserDefaults.standard.set(true, forKey: Self.reopenKey)
        awaitingRelaunch = true
        openSystemSettings()
    }

    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func acknowledgeReopen() {
        UserDefaults.standard.removeObject(forKey: Self.reopenKey)
    }

    func refresh() {
        isGranted = CGPreflightScreenCaptureAccess()
        if isGranted { awaitingRelaunch = false }
    }

    /// Starts a new instance of this app and quits this one.
    func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
