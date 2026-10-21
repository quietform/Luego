import Foundation
import GRDB

nonisolated struct AppDatabase: Sendable {
    let writer: any DatabaseWriter

    var reader: any DatabaseReader {
        writer
    }

    init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    static var databaseConfiguration: Configuration {
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        return configuration
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "articles") { table in
                table.column("id", .text).primaryKey()
                table.column("url", .text).notNull().unique(onConflict: .abort)
                table.column("title", .text).notNull()
                table.column("content", .text)
                table.column("savedDate", .datetime).notNull()
                table.column("thumbnailURL", .text)
                table.column("publishedDate", .datetime)
                table.column("readPosition", .double).notNull().defaults(to: 0)
                table.column("isFavorite", .boolean).notNull().defaults(to: false)
                table.column("isArchived", .boolean).notNull().defaults(to: false)
                table.column("author", .text)
                table.column("wordCount", .integer)
                table.column("cloudKitSystemFields", .blob)
            }

            try db.create(table: "syncState") { table in
                table.column("id", .integer).primaryKey().check { $0 == 1 }
                table.column("data", .blob).notNull()
            }

            try db.create(table: "migrationState") { table in
                table.column("key", .text).primaryKey()
                table.column("value", .text).notNull()
            }
        }
        migrator.registerMigration("v2") { db in
            try db.alter(table: "articles") { table in
                table.add(column: "deletedAt", .datetime)
            }
        }
        return migrator
    }

    @concurrent
    static func makeDefault() async throws -> AppDatabase {
        try make(at: databaseURL())
    }

    static func makeTemporary() throws -> AppDatabase {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        return try make(at: url)
    }

    static func make(at url: URL) throws -> AppDatabase {
        let pool = try DatabasePool(path: url.path, configuration: databaseConfiguration)
        return try AppDatabase(pool)
    }

    private static func databaseURL() throws -> URL {
        let baseURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let appDirectory = baseURL.appendingPathComponent("Luego", isDirectory: true)
        try FileManager.default.createDirectory(
            at: appDirectory,
            withIntermediateDirectories: true
        )

        return appDirectory.appendingPathComponent("luego.sqlite")
    }
}

extension AppDatabase {
    func syncEngineStatePayload() async throws -> SyncEngineStatePayload? {
        try await reader.read { db in
            try Self.syncEngineStatePayload(in: db)
        }
    }

    func updateSyncEngineStatePayload(_ update: @Sendable @escaping (inout SyncEngineStatePayload) -> Void) async throws {
        try await writer.write { db in
            var payload = try Self.syncEngineStatePayload(in: db) ?? SyncEngineStatePayload()
            update(&payload)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(payload)
            try db.execute(sql: "INSERT OR REPLACE INTO syncState (id, data) VALUES (1, ?)", arguments: [data])
        }
    }

    private nonisolated static func syncEngineStatePayload(in db: Database) throws -> SyncEngineStatePayload? {
        guard let row = try Row.fetchOne(db, sql: "SELECT data FROM syncState WHERE id = 1") else { return nil }
        let data: Data = row["data"]
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SyncEngineStatePayload.self, from: data)
    }

    func migrationValue(for key: String) async throws -> String? {
        try await reader.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT value FROM migrationState WHERE key = ?",
                arguments: [key]
            )
        }
    }

    func saveMigrationValue(_ value: String, for key: String) async throws {
        try await writer.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO migrationState (key, value) VALUES (?, ?)",
                arguments: [key, value]
            )
        }
    }
}
