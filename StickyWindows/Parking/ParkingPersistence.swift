import Foundation
import os

/// What's saved about a parked window so it can be re-identified (bundle ID + exact title) after a restart.
struct ParkedRecord: Codable, Equatable {
    var bundleID: String
    var title: String
    var edge: Edge
    var displayID: UInt32?
    var desiredOffset: Double
    var mode: RevealMode?
    var storedFrame: CGRect
    var groupID: UUID?

    @MainActor
    init?(_ parkedWindow: ParkedWindow) {
        guard let bundleID = parkedWindow.bundleID else { return nil }
        self.bundleID = bundleID
        title = parkedWindow.title
        edge = parkedWindow.edge
        displayID = parkedWindow.displayID
        desiredOffset = parkedWindow.desiredOffset
        mode = parkedWindow.mode
        storedFrame = parkedWindow.storedFrame
        groupID = parkedWindow.groupID
    }
}

/// JSON file in Application Support. Written often (about once a second when something changed) so a crash
/// loses little; on the next launch the windows are found and re-parked from their saved frames.
@MainActor
final class ParkingPersistence {
    private let url: URL
    private let log = Logger(subsystem: AppIdentity.id, category: "persistence")

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = support.appending(path: AppIdentity.id, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        url = folder.appending(path: "parked.json")
    }

    func load() -> [ParkedRecord] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        do {
            return try JSONDecoder().decode([ParkedRecord].self, from: data)
        } catch {
            log.error("Couldn't read parked windows: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func save(_ records: [ParkedRecord]) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(records).write(to: url, options: .atomic)
        } catch {
            log.error("Couldn't save parked windows: \(error.localizedDescription, privacy: .public)")
        }
    }
}
