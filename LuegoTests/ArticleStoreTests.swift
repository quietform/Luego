import CloudKit
import Foundation
import GRDB
import Testing

@MainActor
struct ArticleStoreTests {
    @Test
    func remoteTombstonesPreserveSyncFieldsWithoutEnqueueing() throws {
        let store = GRDBArticleStore(database: try AppDatabase(DatabaseQueue()))
        let sync = TestSyncEngine()
        store.syncEngineManager = sync
        let id = UUID()
        let deletedAt = Date(timeIntervalSince1970: 123)
        let fields = ArticleRecord.encodeSystemFields(CKRecord(recordType: "Article", recordID: ArticleRecord.makeRecordID(for: id.uuidString)))
        let record = ArticleRecord(id: id.uuidString, url: URL(string: "https://example.com/deleted")!, title: "Deleted", author: "Author", cloudKitSystemFields: fields, deletedAt: deletedAt)

        let records: ArticleRecordStoreProtocol = store
        try records.saveRecord(record)

        let saved = try #require(try store.fetchRecord(id: id))
        #expect(saved.deletedAt == deletedAt)
        #expect(saved.author == "Author")
        #expect(saved.cloudKitSystemFields == fields)
        #expect(try store.fetchArticle(id: id) == nil)
        #expect(try store.countArticles() == 0)
        #expect(sync.savedRecordIDs.isEmpty)
    }

    @Test
    func savingDeletedURLRevivesItsIdentityAndEnqueuesSync() async throws {
        let store = GRDBArticleStore(database: try AppDatabase(DatabaseQueue()))
        let sync = TestSyncEngine()
        store.syncEngineManager = sync
        let id = UUID()
        let url = URL(string: "https://example.com/revive")!
        let fields = Data([1, 2, 3])
        try store.saveRecord(ArticleRecord(id: id.uuidString, url: url, title: "Deleted", author: "Author", cloudKitSystemFields: fields, deletedAt: Date()))
        let service = ArticleService(articleStore: store, contentDataSource: TestContentDataSource(), syncEngineManager: sync)

        let result = try await service.addArticle(url: url, savedDate: Date(timeIntervalSince1970: 200))

        #expect(result.isNew)
        #expect(result.article.id == id)
        let saved = try #require(try store.fetchRecord(id: id))
        #expect(saved.deletedAt == nil)
        #expect(saved.author == "Author")
        #expect(saved.cloudKitSystemFields == fields)
        #expect(saved.savedDate == Date(timeIntervalSince1970: 200))
        #expect(sync.savedRecordIDs.map(\.recordName) == [id.uuidString])
    }

    @Test
    func localMembershipChangesPreserveSyncFields() async throws {
        let store = GRDBArticleStore(database: try AppDatabase(DatabaseQueue()))
        let sync = TestSyncEngine()
        store.syncEngineManager = sync
        let id = UUID()
        let fields = Data([1, 2, 3])
        try store.saveRecord(ArticleRecord(id: id.uuidString, url: URL(string: "https://example.com/article")!, title: "Article", author: "Author", cloudKitSystemFields: fields))
        let service = ArticleService(articleStore: store, contentDataSource: TestContentDataSource(), syncEngineManager: sync)

        try await service.toggleFavorite(id: id)
        #expect(try store.fetchArticle(id: id)?.isFavorite == true)
        try await service.toggleArchive(id: id)
        let saved = try #require(try store.fetchRecord(id: id))
        #expect(saved.isArchived)
        #expect(!saved.isFavorite)
        #expect(saved.author == "Author")
        #expect(saved.cloudKitSystemFields == fields)
        #expect(sync.savedRecordIDs.count == 2)
    }

    @Test
    func legacyMigrationRunsOnceWithoutRevivingDeletedURLs() throws {
        let database = try AppDatabase(DatabaseQueue())
        let store = GRDBArticleStore(database: database)
        let sync = TestSyncEngine()
        let deleted = Article(url: URL(string: "https://example.com/deleted")!, title: "Deleted")
        var record = ArticleRecord(deleted)
        record.deletedAt = Date()
        try store.saveRecord(record)
        let imported = Article(url: URL(string: "https://example.com/imported")!, title: "Imported")
        let migration = LegacySwiftDataArticleMigration(database: database, store: store, syncEngineManager: sync)

        #expect(try migration.migrate([deleted, imported]) == 1)
        #expect(try migration.migrate([deleted, imported]) == 0)
        #expect(try store.fetchArticle(id: deleted.id) == nil)
        #expect(try store.fetchArticle(id: imported.id)?.title == "Imported")
        #expect(sync.savedRecordIDs.count == 2)
    }
}
