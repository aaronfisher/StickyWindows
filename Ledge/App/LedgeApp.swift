import SwiftUI

@main
struct LedgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Ledge lives in the menu bar and opens its own settings window (SettingsWindowController);
        // SwiftUI just needs a scene.
        Settings {
            Text("Open Settings from the Ledge menu bar icon.")
                .padding(40)
        }
    }
}
