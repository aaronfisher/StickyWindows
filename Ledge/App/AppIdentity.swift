import Foundation

enum AppIdentity {
    /// Bundle ID; also the logging subsystem and the Application Support folder name.
    static let id = "vc.theshirleycompany.Ledge"
    /// Ledge's bundle ID before it moved to The Shirley Company team.
    static let legacyID = "vc.start.Ledge"
}

/// One-time move of settings and saved parked windows from the old bundle ID, so changing identity doesn't
/// reset rules, shortcuts, appearance, or the macOS-tiling value Ledge must restore on quit.
enum LegacyMigration {
    private static let doneKey = "migratedFromLegacyBundleID"

    static func run() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }

        // UserDefaults: only if this identity has nothing of its own yet.
        let current = defaults.persistentDomain(forName: AppIdentity.id) ?? [:]
        if current.isEmpty, let legacy = defaults.persistentDomain(forName: AppIdentity.legacyID), !legacy.isEmpty {
            defaults.setPersistentDomain(legacy, forName: AppIdentity.id)
        }

        // Saved parked windows.
        let fileManager = FileManager.default
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let oldFile = support.appending(path: "\(AppIdentity.legacyID)/parked.json")
        let newFolder = support.appending(path: AppIdentity.id, directoryHint: .isDirectory)
        let newFile = newFolder.appending(path: "parked.json")
        if fileManager.fileExists(atPath: oldFile.path), !fileManager.fileExists(atPath: newFile.path) {
            try? fileManager.createDirectory(at: newFolder, withIntermediateDirectories: true)
            try? fileManager.copyItem(at: oldFile, to: newFile)
        }

        defaults.set(true, forKey: doneKey)
    }
}
