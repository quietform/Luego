import Foundation
import GRDB
import Testing

@MainActor
struct SharingServiceTests {
    @Test
    func sharedURLAddedDuringImportRemainsQueued() async throws {
        let store = GRDBArticleStore(database: try AppDatabase(DatabaseQueue()))
        let metadata = TestContentDataSource()
        let firstURL = URL(string: "https://example.com/first")!
        let laterURL = URL(string: "https://example.com/later")!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("queue.sqlite")
        let queue = SharedStorage(databaseURL: databaseURL, legacyDefaults: nil)
        let extensionQueue = SharedStorage(databaseURL: databaseURL, legacyDefaults: nil)
        try await queue.saveSharedURL(firstURL)
        metadata.onFetchMetadata = { _ in
            try await extensionQueue.saveSharedURL(laterURL)
            return ArticleMetadata(title: "First article")
        }
        let articles = ArticleService(articleStore: store, contentDataSource: metadata, syncEngineManager: TestSyncEngine())
        let service = SharingService(articleService: articles, sharedStorage: queue)

        _ = try await service.syncSharedArticles()

        #expect(try queue.getSharedURLs().map(\.url) == [laterURL])
        #expect(try store.fetchArticle(url: firstURL) != nil)
    }
    @Test
    func failedArticleRemainsQueuedUntilRetrySucceeds() async throws {
        let fixture = try SharedQueueFixture()
        defer { fixture.remove() }
        let queue = fixture.makeQueue()
        let url = URL(string: "https://example.com/retry")!
        try await queue.saveSharedURL(url)
        let store = GRDBArticleStore(database: try AppDatabase(DatabaseQueue()))
        let metadata = TestContentDataSource()
        metadata.onFetchMetadata = { _ in throw ArticleMetadataError.noMetadata }
        let articles = ArticleService(articleStore: store, contentDataSource: metadata, syncEngineManager: TestSyncEngine())
        let service = SharingService(articleService: articles, sharedStorage: queue)

        _ = try await service.syncSharedArticles()
        #expect(try queue.getSharedURLs().map(\.url) == [url])

        metadata.onFetchMetadata = { _ in ArticleMetadata(title: "Recovered") }
        _ = try await service.syncSharedArticles()
        #expect(try queue.getSharedURLs().isEmpty)
        #expect(try store.fetchArticle(url: url)?.title == "Recovered")
    }

}
