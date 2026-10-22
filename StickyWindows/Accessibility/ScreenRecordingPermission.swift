import AppKit
import Observation

/// Screen Recording access, which live hover previews need. Optional: without it previews show icon + title.
///
/// macOS applies a Screen Recording grant only to a fresh launch, and a running process keeps seeing
/// "not granted" until then, so there is nothing to poll: the flow is request → user turns it on → relaunch.
@MainActor
@Observable
final class ScreenRecordingPermission {
    private(set) var isGranted: Bool
    /// The user asked for it during this run; the answer only shows after a relaunch.
    private(set) var awaitingRelaunch: Bool

    private static let pendingKey = "screenRecordingRequestPending"

    init() {
        let granted = CGPreflightScreenCaptureAccess()
        isGranted = granted
        awaitingRelaunch = UserDefaults.standard.bool(forKey: Self.pendingKey) && !granted
        if granted { UserDefaults.standard.removeObject(forKey: Self.pendingKey) }
    }

    /// True right after a relaunch that completed a request: the onboarding should reopen to show the result.
    var justCompletedRequest: Bool {
        isGranted && UserDefaults.standard.bool(forKey: Self.pendingKey + ".show")
    }

    /// Shows the system prompt the first time; afterwards macOS only offers System Settings.
    func request() {
        let granted = CGRequestScreenCaptureAccess()
        isGranted = granted
        guard !granted else { return }
        UserDefaults.standard.set(true, forKey: Self.pendingKey)
        UserDefaults.standard.set(true, forKey: Self.pendingKey + ".show")
        awaitingRelaunch = true
        openSystemSettings()
    }

    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func acknowledgeCompletion() {
        UserDefaults.standard.removeObject(forKey: Self.pendingKey + ".show")
    }

    func refresh() {
        isGranted = CGPreflightScreenCaptureAccess()
        if isGranted {
            awaitingRelaunch = false
            UserDefaults.standard.removeObject(forKey: Self.pendingKey)
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
