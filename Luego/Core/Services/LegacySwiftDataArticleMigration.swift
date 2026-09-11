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

    func needsMigration() throws -> Bool {
        try database.migrationValue(for: Self.migrationKey) == nil
    }

    func migrateIfNeeded() throws -> Int {
        guard try needsMigration() else { return 0 }

        let importedCount = try importArticles(legacyArticleDataSource.fetchArticles())
        try database.saveMigrationValue(ISO8601DateFormatter().string(from: Date()), for: Self.migrationKey)
        return importedCount
    }

    func migrate(_ articles: [Article]) throws -> Int {
        guard try needsMigration() else { return 0 }

        let importedCount = try importArticles(articles)
        try database.saveMigrationValue(ISO8601DateFormatter().string(from: Date()), for: Self.migrationKey)
        return importedCount
    }

    private func importArticles(_ articles: [Article]) throws -> Int {
        var importedCount = 0
        for article in articles {
            if let existingRecord = try store.fetchRecord(url: article.url) {
                syncEngineManager.enqueueSave(for: ArticleRecord.makeRecordID(for: existingRecord.id))
                continue
            }

            try store.saveRecord(ArticleRecord(article))
            syncEngineManager.enqueueSave(for: ArticleRecord.makeRecordID(for: article.id.uuidString))
            importedCount += 1
        }

        return importedCount
    }
}
