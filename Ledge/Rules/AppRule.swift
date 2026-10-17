import AppKit

/// A per-app rule from Settings → Rules.
struct AppRule: Codable, Identifiable, Equatable {
    enum Action: String, Codable, CaseIterable {
        /// No parking rule (the rule exists for its other options).
        case noParking = "none"
        /// Never park this app's windows (drag zones and shortcuts ignore it).
        case exclude
        /// Park the app's windows on this edge when it launches.
        case parkLeft, parkRight, parkBottom

        var edge: Edge? {
            switch self {
            case .noParking, .exclude: nil
            case .parkLeft: .left
            case .parkRight: .right
            case .parkBottom: .bottom
            }
        }

        var displayName: String {
            switch self {
            case .noParking: "No parking rule"
            case .exclude: "Never park"
            case .parkLeft: "Park on left edge at launch"
            case .parkRight: "Park on right edge at launch"
            case .parkBottom: "Park on bottom edge at launch"
            }
        }
    }

    var bundleID: String
    var name: String
    var action: Action
    /// For apps that stay open without windows (Mail): when you bring the app forward yourself and its only
    /// windows are parked, show its main window instead of nothing. Also keeps Ledge from hiding the whole
    /// app, so a Dock click can't bring parked windows back.
    var dockClickShowsMainWindow = false
    /// The menu command that shows the main window, as [menu, item]; nil picks one automatically.
    var mainWindowCommand: AppMenu.Path?

    var id: String { bundleID }

    init(bundleID: String, name: String, action: Action) {
        self.bundleID = bundleID
        self.name = name
        self.action = action
    }

    // Rules saved before these options existed decode with defaults.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bundleID = try container.decode(String.self, forKey: .bundleID)
        name = try container.decode(String.self, forKey: .name)
        action = try container.decode(Action.self, forKey: .action)
        dockClickShowsMainWindow = try container.decodeIfPresent(Bool.self, forKey: .dockClickShowsMainWindow) ?? false
        mainWindowCommand = try container.decodeIfPresent(AppMenu.Path.self, forKey: .mainWindowCommand)
    }

    @MainActor
    var icon: NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) }
    }
}
