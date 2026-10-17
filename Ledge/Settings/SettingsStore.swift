import AppKit
import Observation
import SwiftUI

extension Notification.Name {
    /// Posted when a setting that affects tab geometry or panel behavior changes, so tabs can re-lay out.
    static let ledgeTabLayoutChanged = Notification.Name("LedgeTabLayoutChanged")
}

enum TabSize: String, CaseIterable, Identifiable {
    case small, medium, large
    var id: Self { self }
    var displayName: String { rawValue.capitalized }
}

enum TabMaterial: String, CaseIterable, Identifiable {
    case ultraThin, thin, regular, thick
    var id: Self { self }

    var displayName: String {
        switch self {
        case .ultraThin: "Ultra Thin"
        case .thin: "Thin"
        case .regular: "Regular"
        case .thick: "Thick"
        }
    }

    var material: Material {
        switch self {
        case .ultraThin: .ultraThinMaterial
        case .thin: .thinMaterial
        case .regular: .regularMaterial
        case .thick: .thickMaterial
        }
    }
}

/// Tab dimensions in points: `thickness` across the edge, `length` along it.
struct TabMetrics {
    let thickness: CGFloat
    let length: CGFloat
}

/// App-wide preferences backed by UserDefaults.
@MainActor
@Observable
final class SettingsStore {
    // MARK: General

    var enabledEdges: Set<Edge> {
        didSet { defaults.set(enabledEdges.map(\.rawValue).sorted(), forKey: Key.enabledEdges) }
    }
    /// How long a dragged window must rest in an edge zone before a drop is armed.
    var dwellTime: TimeInterval {
        didSet { defaults.set(dwellTime, forKey: Key.dwellTime) }
    }
    var defaultRevealMode: RevealMode {
        didSet { defaults.set(defaultRevealMode.rawValue, forKey: Key.defaultRevealMode) }
    }
    var hoverToPeek: Bool {
        didSet { defaults.set(hoverToPeek, forKey: Key.hoverToPeek) }
    }
    var hoverDelay: TimeInterval {
        didSet { defaults.set(hoverDelay, forKey: Key.hoverDelay) }
    }
    /// Slide windows in and out. Reduce Motion always wins.
    var animateWindows: Bool {
        didSet { defaults.set(animateWindows, forKey: Key.animateWindows) }
    }

    // MARK: Spaces

    var tabsOnAllSpaces: Bool {
        didSet { save(tabsOnAllSpaces, Key.tabsOnAllSpaces, relayout: true) }
    }
    var hideTabsInFullScreen: Bool {
        didSet { save(hideTabsInFullScreen, Key.hideTabsInFullScreen, relayout: true) }
    }

    // MARK: Appearance

    var tabSize: TabSize {
        didSet { save(tabSize.rawValue, Key.tabSize, relayout: true) }
    }
    var tabOpacity: Double {
        didSet { defaults.set(tabOpacity, forKey: Key.tabOpacity) }
    }
    var tabMaterial: TabMaterial {
        didSet { defaults.set(tabMaterial.rawValue, forKey: Key.tabMaterial) }
    }
    /// nil follows the system accent color.
    var customAccent: Color? {
        didSet { defaults.set(customAccent.flatMap(Self.hex(from:)), forKey: Key.customAccent) }
    }
    var showTitles: Bool {
        didSet { save(showTitles, Key.showTitles, relayout: true) }
    }

    // MARK: Extras (M6)

    /// Show the app's Dock badge (unread count, etc.) on its tab.
    var showBadges: Bool {
        didSet { defaults.set(showBadges, forKey: Key.showBadges) }
    }
    /// Show a live window preview when hovering a tab (needs Screen Recording; ignored without it).
    var showThumbnails: Bool {
        didSet { defaults.set(showThumbnails, forKey: Key.showThumbnails) }
    }
    var appRules: [AppRule] {
        didSet { defaults.set(try? JSONEncoder().encode(appRules), forKey: Key.appRules) }
    }

    func rule(for bundleID: String?) -> AppRule.Action? {
        guard let bundleID else { return nil }
        return appRules.first { $0.bundleID == bundleID }?.action
    }

    func isExcluded(_ bundleID: String?) -> Bool {
        rule(for: bundleID) == .exclude
    }

    var accentColor: Color { customAccent ?? .accentColor }

    var tabMetrics: TabMetrics {
        let (thickness, length): (CGFloat, CGFloat) = switch tabSize {
        case .small: (26, 104)
        case .medium: (30, 124)
        case .large: (36, 150)
        }
        // Icon-only tabs shrink to just fit the icon.
        return TabMetrics(thickness: thickness, length: showTitles ? length : thickness + 18)
    }

    var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    var shouldAnimateWindows: Bool { animateWindows && !reduceMotion }

    @ObservationIgnored private let defaults: UserDefaults

    private enum Key {
        static let enabledEdges = "enabledEdges"
        static let dwellTime = "dwellTime"
        static let defaultRevealMode = "defaultRevealMode"
        static let hoverToPeek = "hoverToPeek"
        static let hoverDelay = "hoverDelay"
        static let animateWindows = "animateWindows"
        static let tabsOnAllSpaces = "tabsOnAllSpaces"
        static let hideTabsInFullScreen = "hideTabsInFullScreen"
        static let tabSize = "tabSize"
        static let tabOpacity = "tabOpacity"
        static let tabMaterial = "tabMaterial"
        static let customAccent = "customAccent"
        static let showTitles = "showTitles"
        static let showBadges = "showBadges"
        static let showThumbnails = "showThumbnails"
        static let appRules = "appRules"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func value<T>(_ key: String, default fallback: T) -> T { defaults.object(forKey: key) as? T ?? fallback }

        enabledEdges = (defaults.stringArray(forKey: Key.enabledEdges)?.compactMap(Edge.init)).map(Set.init) ?? Set(Edge.allCases)
        dwellTime = value(Key.dwellTime, default: 0.25)
        defaultRevealMode = defaults.string(forKey: Key.defaultRevealMode).flatMap(RevealMode.init) ?? .popOut
        hoverToPeek = value(Key.hoverToPeek, default: false)
        hoverDelay = value(Key.hoverDelay, default: 0.35)
        animateWindows = value(Key.animateWindows, default: true)
        tabsOnAllSpaces = value(Key.tabsOnAllSpaces, default: true)
        hideTabsInFullScreen = value(Key.hideTabsInFullScreen, default: true)
        tabSize = defaults.string(forKey: Key.tabSize).flatMap(TabSize.init) ?? .medium
        tabOpacity = value(Key.tabOpacity, default: 1.0)
        tabMaterial = defaults.string(forKey: Key.tabMaterial).flatMap(TabMaterial.init) ?? .regular
        customAccent = defaults.string(forKey: Key.customAccent).flatMap(Self.color(fromHex:))
        showTitles = value(Key.showTitles, default: true)
        showBadges = value(Key.showBadges, default: true)
        showThumbnails = value(Key.showThumbnails, default: true)
        appRules = defaults.data(forKey: Key.appRules).flatMap { try? JSONDecoder().decode([AppRule].self, from: $0) } ?? []
    }

    private func save(_ value: Any, _ key: String, relayout: Bool) {
        defaults.set(value, forKey: key)
        if relayout { NotificationCenter.default.post(name: .ledgeTabLayoutChanged, object: self) }
    }

    // MARK: Color storage

    private static func hex(from color: Color) -> String? {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        return String(format: "#%02X%02X%02X", Int(rgb.redComponent * 255), Int(rgb.greenComponent * 255), Int(rgb.blueComponent * 255))
    }

    private static func color(fromHex hex: String) -> Color? {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard digits.count == 6, let value = Int(digits, radix: 16) else { return nil }
        return Color(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255)
    }
}
