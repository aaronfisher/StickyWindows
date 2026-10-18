import SwiftUI

@main
struct StickyWindowsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Before AppDelegate (and its SettingsStore) reads any settings.
        LegacyMigration.run()
    }

    var body: some Scene {
        // Sticky Windows lives in the menu bar and opens its own settings window (SettingsWindowController);
        // SwiftUI just needs a scene.
        Settings {
            Text("Open Settings from the Sticky Windows menu bar icon.")
                .padding(40)
        }
    }
}
