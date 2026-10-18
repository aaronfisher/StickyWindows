import Foundation

enum AppIdentity {
    /// Bundle ID; also the logging subsystem, the Keychain service, and the Application Support folder name.
    static let id = "vc.theshirleycompany.StickyWindows"
    /// Earlier identities, newest first. The app was called Ledge until October 2026.
    static let legacyIDs = ["vc.theshirleycompany.Ledge", "vc.start.Ledge"]
}

/// One-time move of settings, license/trial, and saved parked windows from an earlier identity, so a rename
/// doesn't reset rules, shortcuts, appearance, the trial clock, or the macOS-tiling value that must be restored.
enum LegacyMigration {
    private static let doneKey = "migratedToIdentity"

    static func run() {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: doneKey) != AppIdentity.id else { return }

        // UserDefaults: only if this identity has nothing of its own yet; take the newest legacy domain with data.
        let current = defaults.persistentDomain(forName: AppIdentity.id) ?? [:]
        if current.isEmpty,
           let legacy = AppIdentity.legacyIDs.lazy.compactMap({ defaults.persistentDomain(forName: $0) }).first(where: { !$0.isEmpty }) {
            var copy = legacy
            copy[doneKey] = nil
            defaults.setPersistentDomain(copy, forName: AppIdentity.id)
        }

        // Keychain: license and trial start.
        for account in ["license", "trialStart"] where Keychain.string(for: account) == nil {
            if let legacyService = AppIdentity.legacyIDs.first(where: { Keychain.string(for: account, service: $0) != nil }),
               let value = Keychain.string(for: account, service: legacyService) {
                Keychain.set(value, for: account)
            }
        }

        // Saved parked windows.
        let fileManager = FileManager.default
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let newFolder = support.appending(path: AppIdentity.id, directoryHint: .isDirectory)
        let newFile = newFolder.appending(path: "parked.json")
        if !fileManager.fileExists(atPath: newFile.path) {
            for legacy in AppIdentity.legacyIDs {
                let oldFile = support.appending(path: "\(legacy)/parked.json")
                guard fileManager.fileExists(atPath: oldFile.path) else { continue }
                try? fileManager.createDirectory(at: newFolder, withIntermediateDirectories: true)
                try? fileManager.copyItem(at: oldFile, to: newFile)
                break
            }
        }

        defaults.set(AppIdentity.id, forKey: doneKey)
    }
}
