import AppKit
import Observation
import os

/// macOS 15's own window tiling, which also reacts to windows dragged to the left/right screen edges.
enum MacOSTiling {
    static var domain: CFString { "com.apple.WindowManager" as CFString }
    static var edgeDragKey: CFString { "EnableTilingByEdgeDrag" as CFString }

    /// Reads the "Drag windows to left or right edge of screen to tile" setting. Defaults to on when unset.
    static var isEdgeDragTilingEnabled: Bool {
        storedEdgeDragValue ?? true
    }

    /// The raw stored value; nil when the user has never changed it (macOS treats that as on).
    static var storedEdgeDragValue: Bool? {
        CFPreferencesAppSynchronize(domain)
        return CFPreferencesCopyAppValue(edgeDragKey, domain) as? Bool
    }

    static func setStoredEdgeDragValue(_ value: Bool?) {
        CFPreferencesSetAppValue(edgeDragKey, value.map { $0 as CFBoolean }, domain)
        CFPreferencesAppSynchronize(domain)
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Opt-in: turns macOS edge-drag tiling off while Sticky Windows runs so left/right drops aren't fought over,
/// and puts the user's own value back when Sticky Windows quits (or on next launch, after a crash).
@MainActor
@Observable
final class TilingOverride {
    private(set) var isEnabled: Bool

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let log = Logger(subsystem: AppIdentity.id, category: "tiling")

    private enum Key {
        static let enabled = "tilingOverrideEnabled"
        /// Present only while the override is applied: the user's value from before ("on", "off", or "unset").
        static let savedValue = "tilingOverrideSavedValue"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Key.enabled)
    }

    /// Call at launch: undo anything a crashed session left behind, then re-apply if opted in.
    func restoreOnLaunch() {
        restoreUserValue()
        if isEnabled { apply() }
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: Key.enabled)
        enabled ? apply() : restoreUserValue()
    }

    /// Call from `applicationWillTerminate`.
    func restoreOnQuit() {
        restoreUserValue()
    }

    private func apply() {
        guard defaults.string(forKey: Key.savedValue) == nil else { return }
        let current = MacOSTiling.storedEdgeDragValue
        defaults.set(current.map { $0 ? "on" : "off" } ?? "unset", forKey: Key.savedValue)
        MacOSTiling.setStoredEdgeDragValue(false)
        log.info("Edge-drag tiling turned off (was \(current.map(String.init) ?? "unset", privacy: .public))")
    }

    private func restoreUserValue() {
        guard let saved = defaults.string(forKey: Key.savedValue) else { return }
        defaults.removeObject(forKey: Key.savedValue)
        // If the user flipped the setting themselves while Sticky Windows was running, theirs wins.
        guard MacOSTiling.storedEdgeDragValue == false else {
            log.info("Edge-drag tiling changed by the user; leaving it")
            return
        }
        let original: Bool? = switch saved {
        case "on": true
        case "off": false
        default: nil
        }
        MacOSTiling.setStoredEdgeDragValue(original)
        log.info("Edge-drag tiling restored to \(saved, privacy: .public)")
    }
}
