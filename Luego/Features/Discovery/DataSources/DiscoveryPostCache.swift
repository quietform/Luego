import Foundation

nonisolated struct DiscoveryPostSnapshot: Codable, Equatable, Sendable {
    let posts: [DiscoveryPost]
    let fetchedAt: Date
}

@MainActor
protocol DiscoveryPostCacheProtocol: Sendable {
    func load() async -> DiscoveryPostSnapshot?
    func save(_ snapshot: DiscoveryPostSnapshot) async
}

@MainActor
final class DiscoveryPostCache: DiscoveryPostCacheProtocol {
    private let storage: FileCache
    private let fileURL: URL
    private let formatVersion: Int

    init(storage: FileCache = FileCache(), directory: URL? = nil, formatVersion: Int = 1) {
        self.storage = storage
        self.formatVersion = formatVersion
        let directory = directory ?? (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory).appendingPathComponent("Discovery")
        fileURL = directory.appendingPathComponent("river.json")
    }

    func load() async -> DiscoveryPostSnapshot? {
        guard let stored = await storage.readJSON(StoredSnapshot.self, from: fileURL),
              stored.formatVersion == formatVersion else { return nil }
        return stored.snapshot
    }

    func save(_ snapshot: DiscoveryPostSnapshot) async {
        await storage.writeJSON(StoredSnapshot(formatVersion: formatVersion, snapshot: snapshot), to: fileURL)
    }
}

private nonisolated struct StoredSnapshot: Codable, Sendable {
    let formatVersion: Int
    let snapshot: DiscoveryPostSnapshot
}
