import CloudKit
import Foundation
import GRDB
import Testing

@MainActor
struct ArticleStoreTests {
    @Test(arguments: [false, true])
    func contentUpdatesPreserveLocalChangesAndDeletion(deleted: Bool) async throws {
        let store = GRDBArticleStore(database: try AppDatabase(DatabaseQueue()))
        let article = Article(url: URL(string: "https://example.com/content")!, title: "Original")
        _ = try await store.saveArticle(article)
        if deleted { try await store.deleteArticle(id: article.id) }
        let content = ArticleContent(title: "Fetched title", thumbnailURL: URL(string: "https://example.com/image.jpg"), content: "New body", wordCount: 2)
        let update = Task {
            try await store.updateContent(id: article.id, content: content, forceRefresh: true)
        }
        let localEdit = Task {
            try await store.toggleFavorite(id: article.id)
            try await store.updateReadPosition(id: article.id, position: 0.75)
        }
        let updated = try await update.value
        try await localEdit.value

        let record = try #require(try await store.fetchRecord(id: article.id))
        #expect(record.title == "Original")
        if deleted {
            #expect(updated == nil)
            #expect(record.deletedAt != nil)
            #expect(record.content == nil)
        } else {
            #expect(record.content == "New body")
            #expect(record.wordCount == 2)
            #expect(record.thumbnailURL == content.thumbnailURL)
            #expect(record.isFavorite)
            #expect(record.readPosition == 0.75)
        }
    }

    @Test
    func acknowledgingCloudKitFieldsPreservesConcurrentDeletion() async throws {
        let store = GRDBArticleStore(database: try AppDatabase(DatabaseQueue()))
        let sync = TestSyncEngine()
        store.syncEngineManager = sync
        let article = Article(url: URL(string: "https://example.com/acknowledged")!, title: "Original", content: "Original body", readPosition: 0.5, isFavorite: true)
        _ = try await store.saveArticle(article)
        let fields = Data([1, 2, 3])
        let acknowledgement = Task {
            try await store.updateCloudKitSystemFields(recordName: article.id.uuidString, fields: fields)
        }
        let deletion = Task { try await store.deleteArticle(id: article.id) }
        try await acknowledgement.value
        try await deletion.value

        let record = try #require(try await store.fetchRecord(id: article.id))
        #expect(record.deletedAt != nil)
        #expect(record.cloudKitSystemFields == fields)
        #expect(record.content == "Original body")
        #expect(record.isFavorite)
        #expect(record.readPosition == 0.5)
        #expect(sync.savedRecordIDs.count == 2)
    }

    @Test
    func concurrentSavesOfOneURLShareOneIdentity() async throws {
        let store = GRDBArticleStore(database: try AppDatabase(DatabaseQueue()))
        let sync = TestSyncEngine()
        store.syncEngineManager = sync
        let url = URL(string: "https://example.com/same-article")!

        let saves = (0..<8).map { _ in
            Task { try await store.saveArticle(Article(url: url, title: "Article")).article.id }
        }
        var identities = Set<UUID>()
        for save in saves { identities.insert(try await save.value) }

        #expect(identities.count == 1)
        #expect(try await store.countArticles() == 1)
        #expect(sync.savedRecordIDs.count == 1)
    }

    @Test
    func databaseContentionDoesNotBlockMainActor() async throws {
        let database = try AppDatabase(DatabaseQueue())
        let store = GRDBArticleStore(database: database)
        let article = Article(url: URL(string: "https://example.com/contended")!, title: "Article")
        _ = try await store.saveArticle(article)
        let (events, signal) = AsyncStream<Void>.makeStream()
        let competingWrite = Task {
            try await database.writer.write { db in
                try db.execute(sql: "UPDATE articles SET title = title")
                signal.yield(())
                Thread.sleep(forTimeInterval: 0.2)
            }
        }
        var iterator = events.makeAsyncIterator()
        _ = await iterator.next()
        var mainActorRan = false
        let heartbeat = Task { @MainActor in mainActorRan = true }

        try await store.toggleFavorite(id: article.id)
        let progressedWhileSaving = mainActorRan
        await heartbeat.value
        try await competingWrite.value

        #expect(progressedWhileSaving)
        #expect(try await store.fetchArticle(id: article.id)?.isFavorite == true)
    }

    @Test
    func remoteTombstonesPreserveSyncFieldsWithoutEnqueueing() async throws {
        let store = GRDBArticleStore(database: try AppDatabase(DatabaseQueue()))
        let sync = TestSyncEngine()
        store.syncEngineManager = sync
        let id = UUID()
        let deletedAt = Date(timeIntervalSince1970: 123)
        let fields = ArticleRecord.encodeSystemFields(CKRecord(recordType: "Article", recordID: ArticleRecord.makeRecordID(for: id.uuidString)))
        let record = ArticleRecord(id: id.uuidString, url: URL(string: "https://example.com/deleted")!, title: "Deleted", author: "Author", cloudKitSystemFields: fields, deletedAt: deletedAt)

        let records: ArticleRecordStoreProtocol = store
        try await records.saveRecord(record)

        let saved = try #require(try await store.fetchRecord(id: id))
        #expect(saved.deletedAt == deletedAt)
        #expect(saved.author == "Author")
        #expect(saved.cloudKitSystemFields == fields)
        #expect(try await store.fetchArticle(id: id) == nil)
        #expect(try await store.countArticles() == 0)
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
        try await store.saveRecord(ArticleRecord(id: id.uuidString, url: url, title: "Deleted", author: "Author", cloudKitSystemFields: fields, deletedAt: Date()))
        let service = ArticleService(articleStore: store, contentDataSource: TestContentDataSource(), syncEngineManager: sync)

        let result = try await service.addArticle(url: url, savedDate: Date(timeIntervalSince1970: 200))

        #expect(result.isNew)
        #expect(result.article.id == id)
        let saved = try #require(try await store.fetchRecord(id: id))
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
        try await store.saveRecord(ArticleRecord(id: id.uuidString, url: URL(string: "https://example.com/article")!, title: "Article", author: "Author", cloudKitSystemFields: fields))
        let service = ArticleService(articleStore: store, contentDataSource: TestContentDataSource(), syncEngineManager: sync)

        try await service.toggleFavorite(id: id)
        #expect(try await store.fetchArticle(id: id)?.isFavorite == true)
        try await service.toggleArchive(id: id)
        let saved = try #require(try await store.fetchRecord(id: id))
        #expect(saved.isArchived)
        #expect(!saved.isFavorite)
        #expect(saved.author == "Author")
        #expect(saved.cloudKitSystemFields == fields)
        #expect(sync.savedRecordIDs.count == 2)
    }

    @Test
    func legacyMigrationRunsOnceWithoutRevivingDeletedURLs() async throws {
        let database = try AppDatabase(DatabaseQueue())
        let store = GRDBArticleStore(database: database)
        let sync = TestSyncEngine()
        let deleted = Article(url: URL(string: "https://example.com/deleted")!, title: "Deleted")
        var record = ArticleRecord(deleted)
        record.deletedAt = Date()
        try await store.saveRecord(record)
        let imported = Article(url: URL(string: "https://example.com/imported")!, title: "Imported")
        let migration = LegacySwiftDataArticleMigration(database: database, store: store, syncEngineManager: sync)

        #expect(try await migration.migrate([deleted, imported]) == 1)
        #expect(try await migration.migrate([deleted, imported]) == 0)
        #expect(try await store.fetchArticle(id: deleted.id) == nil)
        #expect(try await store.fetchArticle(id: imported.id)?.title == "Imported")
        #expect(sync.savedRecordIDs.count == 2)
    }
}
