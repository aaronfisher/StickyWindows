import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let permission = AccessibilityPermission()
    private var statusItemController: StatusItemController?
    private var onboarding: OnboardingWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItemController = StatusItemController(
            permission: permission,
            showOnboarding: { [weak self] in self?.showOnboarding() }
        )
        if !permission.isTrusted {
            showOnboarding()
        }
    }

    func showOnboarding() {
        if onboarding == nil {
            onboarding = OnboardingWindowController(permission: permission)
        }
        onboarding?.show()
    }
}
