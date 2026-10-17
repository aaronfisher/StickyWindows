import AppKit

/// macOS 15's own window tiling, which also reacts to windows dragged to the left/right screen edges.
enum MacOSTiling {
    /// Reads the "Drag windows to left or right edge of screen to tile" setting. Defaults to on when unset.
    static var isEdgeDragTilingEnabled: Bool {
        let value = CFPreferencesCopyAppValue("EnableTilingByEdgeDrag" as CFString, "com.apple.WindowManager" as CFString)
        return (value as? Bool) ?? true
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
