import AppKit

/// A per-app rule from Settings → Rules.
struct AppRule: Codable, Identifiable, Equatable {
    enum Action: String, Codable, CaseIterable {
        /// Never park this app's windows (drag zones and shortcuts ignore it).
        case exclude
        /// Park the app's windows on this edge when it launches.
        case parkLeft, parkRight, parkBottom

        var edge: Edge? {
            switch self {
            case .exclude: nil
            case .parkLeft: .left
            case .parkRight: .right
            case .parkBottom: .bottom
            }
        }

        var displayName: String {
            switch self {
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

    var id: String { bundleID }

    @MainActor
    var icon: NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) }
    }
}
