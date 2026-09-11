import GRDB
import Testing

@MainActor
struct SavedArticleImportTests {
    @Test
    func testArticleSavedDuringMetadataFetchIsCountedAsExisting() async throws {
        let store = GRDBArticleStore(database: try AppDatabase(DatabaseQueue()))
        let metadata = TestContentDataSource()
        metadata.onFetchMetadata = { url in
            _ = try store.saveArticle(Article(url: url, title: "Saved elsewhere"))
            return ArticleMetadata(title: "Fetched title")
        }
        let articles = ArticleService(articleStore: store, contentDataSource: metadata, syncEngineManager: TestSyncEngine())
        let service = SavedArticleImportService(articleService: articles)

        let result = await service.importArticles(fromPlainText: "https://example.com/article")

        #expect(result.importedCount == 0)
        #expect(result.skippedExistingCount == 1)
        #expect(try store.countArticles() == 1)
    }
}
