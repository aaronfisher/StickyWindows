import Observation
import ServiceManagement

/// Wraps `SMAppService.mainApp` (the system keeps the state; nothing is stored here).
@MainActor
@Observable
final class LaunchAtLogin {
    private(set) var isEnabled = SMAppService.mainApp.status == .enabled
    private(set) var errorMessage: String?

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}
