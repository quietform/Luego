import GRDB
import Testing

@MainActor
struct SavedArticleImportTests {
    @Test
    func preparingInputDeduplicatesURLsWithoutBlockingMainActor() async {
        var mainActorRan = false
        let heartbeat = Task { @MainActor in mainActorRan = true }
        let input = await SavedArticleImportService.prepareInput("https://example.com/one\nhttps://example.com/one\nhttps://example.com/two\nmailto:reader@example.com")
        let progressedWhilePreparing = mainActorRan
        await heartbeat.value

        #expect(progressedWhilePreparing)
        #expect(input.detectedURLCount == 3)
        #expect(input.urls.map(\.absoluteString) == ["https://example.com/one", "https://example.com/two"])
    }

    @Test
    func testArticleSavedDuringMetadataFetchIsCountedAsExisting() async throws {
        let store = GRDBArticleStore(database: try AppDatabase(DatabaseQueue()))
        let metadata = TestContentDataSource()
        metadata.onFetchMetadata = { url in
            _ = try await store.saveArticle(Article(url: url, title: "Saved elsewhere"))
            return ArticleMetadata(title: "Fetched title")
        }
        let articles = ArticleService(articleStore: store, contentDataSource: metadata, syncEngineManager: TestSyncEngine())
        let service = SavedArticleImportService(articleService: articles)

        let result = await service.importArticles(fromPlainText: "https://example.com/article")

        #expect(result.importedCount == 0)
        #expect(result.skippedExistingCount == 1)
        #expect(try await store.countArticles() == 1)
    }
}
