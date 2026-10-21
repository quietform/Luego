import Foundation
import GRDB
import Testing

@MainActor
struct ArticleCreationTests {
    @Test
    func concurrentAddsReportOnlyOneNewArticle() async throws {
        let store = GRDBArticleStore(database: try AppDatabase(DatabaseQueue()))
        let sync = TestSyncEngine()
        store.syncEngineManager = sync
        let coordinatedStore = SaveBarrierStore(store: store)
        let service = ArticleService(articleStore: coordinatedStore, contentDataSource: TestContentDataSource(), syncEngineManager: sync)
        let url = URL(string: "https://example.com/concurrent-add")!

        let first = Task { try await service.addArticle(url: url, savedDate: Date(timeIntervalSince1970: 100)) }
        let second = Task { try await service.addArticle(url: url, savedDate: Date(timeIntervalSince1970: 200)) }
        let results = try await [first.value, second.value]

        #expect(results.filter(\.isNew).count == 1)
        #expect(Set(results.map { $0.article.id }).count == 1)
        #expect(try await store.countArticles() == 1)
        #expect(sync.savedRecordIDs.count == 1)
    }
}

@MainActor
private final class SaveBarrierStore: ArticleStoreProtocol {
    private let store: GRDBArticleStore
    private let saves = AsyncStream<Void>.makeStream()
    private var saveRequests = 0

    init(store: GRDBArticleStore) { self.store = store }

    func saveArticle(_ article: Article) async throws -> ArticleSaveResult {
        saveRequests += 1
        if saveRequests == 2 { saves.continuation.finish() }
        for await _ in saves.stream {}
        return try await store.saveArticle(article)
    }

    func fetchAllArticles() async throws -> [Article] { try await store.fetchAllArticles() }
    func observeArticles() -> AsyncThrowingStream<[Article], Error> { store.observeArticles() }
    func fetchArticle(id: UUID) async throws -> Article? { try await store.fetchArticle(id: id) }
    func fetchArticle(url: URL) async throws -> Article? { try await store.fetchArticle(url: url) }
    func updateContent(id: UUID, content: ArticleContent, forceRefresh: Bool) async throws -> Article? {
        try await store.updateContent(id: id, content: content, forceRefresh: forceRefresh)
    }
    func deleteArticle(id: UUID) async throws { try await store.deleteArticle(id: id) }
    func toggleFavorite(id: UUID) async throws { try await store.toggleFavorite(id: id) }
    func toggleArchive(id: UUID) async throws { try await store.toggleArchive(id: id) }
    func updateReadPosition(id: UUID, position: Double) async throws { try await store.updateReadPosition(id: id, position: position) }
    func countArticles() async throws -> Int { try await store.countArticles() }
}
