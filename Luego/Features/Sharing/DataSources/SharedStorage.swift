import Foundation
import GRDB

struct SharedURL: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "sharedURLs"

    let id: String
    let url: URL
    let timestamp: Date

    init(url: URL, timestamp: Date = Date()) {
        self.id = UUID().uuidString
        self.url = url
        self.timestamp = timestamp
    }
}

enum SharedStorageError: LocalizedError, Sendable {
    case appGroupUnavailable
    case sharedQueueDecodeFailed

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            return "Shared storage is unavailable"
        case .sharedQueueDecodeFailed:
            return "Failed to read shared items"
        }
    }
}

@MainActor
protocol SharedStorageDataSourceProtocol: Sendable {
    func saveSharedURL(_ url: URL) async throws
    func getSharedURLs() throws -> [SharedURL]
    func acknowledgeSharedURL(id: String) throws
}

@MainActor
final class SharedStorage: SharedStorageDataSourceProtocol {
    static let shared = SharedStorage()

    private let databaseURL: URL?
    private let legacyDefaults: UserDefaults?
    private var database: DatabaseQueue?

    init(
        databaseURL: URL? = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.esoxjem.Luego")?.appendingPathComponent("SharedURLs.sqlite"),
        legacyDefaults: UserDefaults? = UserDefaults(suiteName: "group.com.esoxjem.Luego")
    ) {
        self.databaseURL = databaseURL
        self.legacyDefaults = legacyDefaults
    }

    func saveSharedURL(_ url: URL) async throws {
        let item = SharedURL(url: url)
        for attempt in 0...20 {
            try Task.checkCancellation()
            do {
                try await openDatabase().write { db in
                    try item.insert(db)
                }
                return
            } catch let error as DatabaseError where error.resultCode == .SQLITE_BUSY && attempt < 20 {
                try await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    func getSharedURLs() throws -> [SharedURL] {
        try openDatabase().read { db in
            try SharedURL.order(Column("timestamp"), Column("id")).fetchAll(db)
        }
    }

    func acknowledgeSharedURL(id: String) throws {
        try openDatabase().write { db in
            _ = try SharedURL.deleteOne(db, key: id)
        }
    }

    private func openDatabase() throws -> DatabaseQueue {
        if let database { return database }
        guard let databaseURL else { throw SharedStorageError.appGroupUnavailable }

        let database = try DatabaseQueue(path: databaseURL.path)
        let legacyData = legacyDefaults?.data(forKey: "sharedURLs")
        var migrator = DatabaseMigrator()
        migrator.registerMigration("sharedURLs-v1") { db in
            try db.create(table: SharedURL.databaseTableName) { table in
                table.column("id", .text).primaryKey()
                table.column("url", .text).notNull()
                table.column("timestamp", .datetime).notNull()
            }
            if let legacyData {
                guard let items = try? JSONDecoder().decode([LegacySharedURL].self, from: legacyData) else {
                    throw SharedStorageError.sharedQueueDecodeFailed
                }
                for item in items {
                    try SharedURL(url: item.url, timestamp: item.timestamp).insert(db)
                }
            }
        }
        try migrator.migrate(database)
        legacyDefaults?.removeObject(forKey: "sharedURLs")
        self.database = database
        return database
    }
}

private struct LegacySharedURL: Decodable {
    let url: URL
    let timestamp: Date
}
