import Foundation

/// Remembers per app whether offscreen parking works, so known clampers skip straight to the fallbacks.
@MainActor
final class HidingStrategyStore {
    private let defaults: UserDefaults
    private let key = "hidingStrategies"

    /// Bump to discard strategies learned by an older, buggier offscreen check.
    private let version = 2
    private let versionKey = "hidingStrategiesVersion"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.integer(forKey: versionKey) < version {
            defaults.removeObject(forKey: key)
            defaults.set(version, forKey: versionKey)
        }
    }

    func method(for bundleID: String?) -> HidingMethod {
        guard let bundleID, let raw = (defaults.dictionary(forKey: key) as? [String: String])?[bundleID] else {
            return .offscreen
        }
        return HidingMethod(rawValue: raw) ?? .offscreen
    }

    func setMethod(_ method: HidingMethod, for bundleID: String?) {
        guard let bundleID else { return }
        var all = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
        all[bundleID] = method.rawValue
        defaults.set(all, forKey: key)
    }

    func reset() {
        defaults.removeObject(forKey: key)
    }
}
