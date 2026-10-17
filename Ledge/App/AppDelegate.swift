import AppKit
import KeyboardShortcuts

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let permission = AccessibilityPermission()
    let parking = ParkingManager()
    private var statusItemController: StatusItemController?
    private var onboarding: OnboardingWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        parking.onNeedsPermission = { [weak self] in self?.showOnboarding() }
        statusItemController = StatusItemController(
            permission: permission,
            parking: parking,
            showOnboarding: { [weak self] in self?.showOnboarding() }
        )

        KeyboardShortcuts.onKeyUp(for: .parkFrontmostRight) { [weak self] in
            guard let parking = self?.parking else { return }
            Task { await parking.parkFrontmostWindow(to: .right) }
        }

        if !permission.isTrusted {
            showOnboarding()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        parking.releaseAll()
    }

    func showOnboarding() {
        if onboarding == nil {
            onboarding = OnboardingWindowController(permission: permission)
        }
        onboarding?.show()
    }
}
