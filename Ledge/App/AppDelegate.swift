import AppKit
import KeyboardShortcuts

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let permission = AccessibilityPermission()
    let settings = SettingsStore()
    lazy var parking = ParkingManager(settings: settings)
    let tilingOverride = TilingOverride()
    private let windowObserver = WindowObserver()
    private var statusItemController: StatusItemController?
    private var onboarding: OnboardingWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        tilingOverride.restoreOnLaunch()
        parking.onNeedsPermission = { [weak self] in self?.showOnboarding() }
        statusItemController = StatusItemController(
            permission: permission,
            parking: parking,
            tilingOverride: tilingOverride,
            showOnboarding: { [weak self] in self?.showOnboarding() }
        )

        KeyboardShortcuts.onKeyUp(for: .parkFrontmostRight) { [weak self] in
            guard let parking = self?.parking else { return }
            Task { await parking.parkFrontmostWindow(to: .right) }
        }

        windowObserver.onDrop = { [weak self] drop in
            guard let parking = self?.parking else { return }
            Task {
                await parking.park(
                    drop.window, edge: drop.zone.edge, screen: drop.zone.screen,
                    offset: drop.zone.offset, restoreFrame: drop.startFrame,
                    settleDelay: MacOSTiling.isEdgeDragTilingEnabled ? .milliseconds(350) : .milliseconds(50))
            }
        }
        windowObserver.onWindowMoved = { [weak self] window, start in
            self?.parking.windowWasDragged(window, from: start)
        }
        windowObserver.start()

        if !permission.isTrusted {
            showOnboarding()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        parking.releaseAll()
        tilingOverride.restoreOnQuit()
    }

    func showOnboarding() {
        if onboarding == nil {
            onboarding = OnboardingWindowController(permission: permission, tilingOverride: tilingOverride)
        }
        onboarding?.show()
    }
}
