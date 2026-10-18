import AppKit
import KeyboardShortcuts

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let permission = AccessibilityPermission()
    let settings = SettingsStore()
    lazy var parking = ParkingManager(settings: settings)
    let tilingOverride = TilingOverride()
    let launchAtLogin = LaunchAtLogin()
    let license = LicenseManager()
    private lazy var windowObserver = WindowObserver(settings: settings)
    private var statusItemController: StatusItemController?
    private var onboarding: OnboardingWindowController?
    private var settingsWindow: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        tilingOverride.restoreOnLaunch()
        parking.onNeedsPermission = { [weak self] in self?.showOnboarding() }
        parking.isLicensed = { [license] in license.isActive }
        parking.onNeedsLicense = { [weak self] in self?.showSettings(pane: .license) }
        windowObserver.isEnabled = { [license] in license.isActive }
        license.addObserver { [weak self] state in
            // Parking stops when the trial ends or a license goes bad; parked windows come back.
            guard let self, !self.license.isActive else { return }
            self.parking.releaseAll()
            self.showSettings(pane: .license)
        }
        license.start()
        statusItemController = StatusItemController(
            permission: permission,
            parking: parking,
            tilingOverride: tilingOverride,
            showOnboarding: { [weak self] in self?.showOnboarding() },
            showSettings: { [weak self] in self?.showSettings() },
            license: license
        )

        for (name, edge) in KeyboardShortcuts.Name.parkShortcuts {
            KeyboardShortcuts.onKeyUp(for: name) { [weak self] in
                guard let parking = self?.parking else { return }
                Task { await parking.parkFrontmostWindow(to: edge) }
            }
        }

        windowObserver.onDrop = { [weak self] drop in
            guard let parking = self?.parking else { return }
            Task {
                await parking.park(
                    drop.window, edge: drop.zone.edge, screen: drop.zone.screen,
                    offset: drop.zone.offset, restoreFrame: drop.startFrame, joining: drop.joining,
                    settleDelay: MacOSTiling.isEdgeDragTilingEnabled ? .milliseconds(350) : .milliseconds(50))
            }
        }
        windowObserver.tabTarget = { [weak self] zone in self?.parking.tabTarget(at: zone) }
        windowObserver.onWindowMoved = { [weak self] window, start in
            self?.parking.windowWasDragged(window, from: start)
        }
        windowObserver.start()

        // Re-parks windows from the last run once Accessibility is available (housekeeping retries until then).
        parking.restoreSavedIfNeeded()
        // After the restore has had a chance to claim windows, so rules don't double-park them.
        Task { [parking] in
            try? await Task.sleep(for: .seconds(3))
            parking.applyAutoParkRulesToRunningApps()
        }

        if !permission.isTrusted {
            showOnboarding()
        } else if !license.isActive {
            showSettings(pane: .license)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        parking.prepareForTermination()
        tilingOverride.restoreOnQuit()
    }

    func showOnboarding() {
        if onboarding == nil {
            onboarding = OnboardingWindowController(permission: permission, tilingOverride: tilingOverride)
        }
        onboarding?.show()
    }

    func showSettings(pane: SettingsPane? = nil) {
        if let pane {
            UserDefaults.standard.set(pane.rawValue, forKey: "settingsPane")
        }
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(rootView: SettingsView(
                settings: settings, tilingOverride: tilingOverride, permission: permission, launchAtLogin: launchAtLogin,
                license: license))
        }
        settingsWindow?.show()
    }
}
