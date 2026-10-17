import SwiftUI

@main
struct LedgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Ledge lives in the menu bar; the real settings window arrives in M5.
        Settings {
            Text("Settings are coming in a later milestone.")
                .padding(40)
        }
    }
}
