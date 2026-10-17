import Foundation
import Observation

/// App-wide preferences backed by UserDefaults. The settings window that edits these arrives in M5.
@MainActor
@Observable
final class SettingsStore {
    var defaultRevealMode: RevealMode {
        didSet { defaults.set(defaultRevealMode.rawValue, forKey: Key.defaultRevealMode) }
    }
    var hoverToPeek: Bool {
        didSet { defaults.set(hoverToPeek, forKey: Key.hoverToPeek) }
    }
    var hoverDelay: TimeInterval {
        didSet { defaults.set(hoverDelay, forKey: Key.hoverDelay) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    private enum Key {
        static let defaultRevealMode = "defaultRevealMode"
        static let hoverToPeek = "hoverToPeek"
        static let hoverDelay = "hoverDelay"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaultRevealMode = defaults.string(forKey: Key.defaultRevealMode).flatMap(RevealMode.init) ?? .popOut
        hoverToPeek = defaults.bool(forKey: Key.hoverToPeek)
        hoverDelay = defaults.object(forKey: Key.hoverDelay) as? TimeInterval ?? 0.35
    }
}
