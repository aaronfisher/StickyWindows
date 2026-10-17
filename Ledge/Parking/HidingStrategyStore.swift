import Foundation

/// Remembers per app which hiding method works, so known offscreen-clampers go straight to minimize.
@MainActor
final class HidingStrategyStore {
    private let defaults: UserDefaults
    private let key = "hidingStrategies"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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
