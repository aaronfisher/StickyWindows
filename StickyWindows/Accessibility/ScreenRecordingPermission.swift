import AppKit
import Observation

/// Screen Recording access, which live hover previews need. Optional: without it previews show icon + title.
@MainActor
@Observable
final class ScreenRecordingPermission {
    private(set) var isGranted = CGPreflightScreenCaptureAccess()
    /// macOS applies a new Screen Recording grant only to a fresh launch of the app.
    private(set) var needsRelaunch = false
    private var pollTimer: Timer?
    private let grantedAtLaunch = CGPreflightScreenCaptureAccess()

    /// Shows the system prompt the first time; afterwards macOS only offers System Settings.
    func request() {
        let granted = CGRequestScreenCaptureAccess()
        refresh(granted: granted)
        if !granted { openSystemSettings() }
        startPolling()
    }

    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        startPolling()
    }

    func startPolling() {
        guard pollTimer == nil, !isGranted else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            MainActor.assumeIsolated { [weak self] in self?.refresh() }
        }
    }

    func refresh(granted: Bool? = nil) {
        isGranted = granted ?? CGPreflightScreenCaptureAccess()
        needsRelaunch = isGranted && !grantedAtLaunch
        if isGranted {
            pollTimer?.invalidate()
            pollTimer = nil
        }
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
