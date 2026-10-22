import AppKit
import KeyboardShortcuts
import Sparkle

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let permission = AccessibilityPermission()
    let screenRecording = ScreenRecordingPermission()
    let settings = SettingsStore()
    lazy var parking = ParkingManager(settings: settings)
    let tilingOverride = TilingOverride()
    let launchAtLogin = LaunchAtLogin()
    /// Sparkle. Starts checking on launch per Info.plist (SUFeedURL, SUPublicEDKey, SUEnableAutomaticChecks).
    let updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    private lazy var windowObserver = WindowObserver(settings: settings)
    private var statusItemController: StatusItemController?
    private var onboarding: OnboardingWindowController?
    private var settingsWindow: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if AppIdentity.isDebugBuild {
            // The dev build would otherwise offer to "update" itself to the released version.
            updaterController.updater.automaticallyChecksForUpdates = false
        }
        warnIfOtherCopyIsRunning()
        tilingOverride.restoreOnLaunch()
        parking.onNeedsPermission = { [weak self] in self?.showOnboarding() }

        statusItemController = StatusItemController(
            permission: permission,
            parking: parking,
            tilingOverride: tilingOverride,
            showOnboarding: { [weak self] in self?.showOnboarding() },
            showSettings: { [weak self] in self?.showSettings() },
            screenRecording: screenRecording,
            checkForUpdates: { [weak self] in self?.updaterController.checkForUpdates(nil) }
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
        windowObserver.updateDropTarget = { [weak self] point, window in self?.parking.updateDropTarget(at: point, dragging: window) }
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

        if !permission.isTrusted || screenRecording.justCompletedRequest || screenRecording.awaitingRelaunch {
            // Back from a Screen Recording relaunch (or still mid-way): show the checklist so the result is visible.
            showOnboarding()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        parking.prepareForTermination()
        tilingOverride.restoreOnQuit()
    }

    /// Two copies parking windows at once fight over tabs and the tiling override.
    private func warnIfOtherCopyIsRunning() {
        guard let other = NSRunningApplication.runningApplications(withBundleIdentifier: AppIdentity.siblingID).first else { return }
        let alert = NSAlert()
        alert.messageText = "Another copy of Sticky Windows is running"
        alert.informativeText = """
            \(other.localizedName ?? AppIdentity.siblingID) is already running. Two copies at once will both try to park \
            windows and manage the edge-tiling setting. Quit one of them.
            """
        alert.addButton(withTitle: "Quit This Copy")
        alert.addButton(withTitle: "Quit the Other Copy")
        alert.addButton(withTitle: "Keep Both")
        NSApp.activate()
        switch alert.runModal() {
        case .alertFirstButtonReturn: NSApp.terminate(nil)
        case .alertSecondButtonReturn: other.terminate()
        default: break
        }
    }

    func showOnboarding() {
        if onboarding == nil {
            onboarding = OnboardingWindowController(permission: permission, screenRecording: screenRecording, tilingOverride: tilingOverride)
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
                updater: updaterController.updater, screenRecording: screenRecording))
        }
        settingsWindow?.show()
    }
}
