import Foundation

@MainActor
struct LegacySwiftDataArticleMigration {
    private let database: AppDatabase
    private let store: ArticleRecordStoreProtocol
    private let syncEngineManager: SyncEngineManagerProtocol
    private let legacyArticleDataSource: LegacySwiftDataArticleDataSourceProtocol

    private static let migrationKey = "legacy-swiftdata-articles-imported-v1"

    init(
        database: AppDatabase,
        store: ArticleRecordStoreProtocol,
        syncEngineManager: SyncEngineManagerProtocol,
        legacyArticleDataSource: LegacySwiftDataArticleDataSourceProtocol = LegacySwiftDataArticleDataSource()
    ) {
        self.database = database
        self.store = store
        self.syncEngineManager = syncEngineManager
        self.legacyArticleDataSource = legacyArticleDataSource
    }

    func needsMigration() async throws -> Bool {
        try await database.migrationValue(for: Self.migrationKey) == nil
    }

    func migrateIfNeeded() async throws -> Int {
        guard try await needsMigration() else { return 0 }

        let records = try await legacyArticleDataSource.fetchRecords()
        let importedCount = try await importRecords(records)
        try await database.saveMigrationValue(ISO8601DateFormatter().string(from: Date()), for: Self.migrationKey)
        return importedCount
    }

    func migrate(_ articles: [Article]) async throws -> Int {
        guard try await needsMigration() else { return 0 }

        let importedCount = try await importRecords(articles.map { ArticleRecord($0) })
        try await database.saveMigrationValue(ISO8601DateFormatter().string(from: Date()), for: Self.migrationKey)
        return importedCount
    }

    private func importRecords(_ records: [ArticleRecord]) async throws -> Int {
        var importedCount = 0
        for record in records {
            if let existingRecord = try await store.fetchRecord(url: record.url) {
                syncEngineManager.enqueueSave(for: ArticleRecord.makeRecordID(for: existingRecord.id))
                continue
            }

            try await store.saveRecord(record)
            syncEngineManager.enqueueSave(for: ArticleRecord.makeRecordID(for: record.id))
            importedCount += 1
        }

        return importedCount
    }
}
