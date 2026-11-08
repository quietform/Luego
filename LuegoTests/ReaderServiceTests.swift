import Foundation
import GRDB
import Testing

@MainActor
struct ReaderServiceTests {
    @Test(arguments: [false, true])
    func frameworkCancellationLeavesStoredContentIntact(forceRefresh: Bool) async throws {
        let store = GRDBArticleStore(database: try AppDatabase(DatabaseQueue()))
        let previousContent = forceRefresh ? "Previously saved body" : nil
        let article = Article(url: URL(string: "https://example.com/article")!, title: "Original", content: previousContent)
        _ = try await store.saveArticle(article)
        let service = ReaderService(articleStore: store, contentDataSource: LateCanceledContentSource())
        let task = Task {
            _ = try await service.fetchContent(for: article, forceRefresh: forceRefresh)
        }
        let result = await task.result

        if case .failure(let error) = result {
            #expect(error is CancellationError)
        } else {
            Issue.record("Canceled reader fetch returned a result")
        }
        let savedArticle = try await store.fetchArticle(id: article.id)
        #expect(savedArticle?.content == previousContent)
        #expect(savedArticle?.wordCount == nil)
        #expect(savedArticle?.thumbnailURL == nil)
    }

    @Test
    func favoritingFromTheReaderIsSavedAndReported() async throws {
        let store = GRDBArticleStore(database: try AppDatabase(DatabaseQueue()))
        let article = Article(url: URL(string: "https://example.com/article")!, title: "Article")
        _ = try await store.saveArticle(article)
        let service = ReaderService(articleStore: store, contentDataSource: TestContentDataSource())

        let membership = try await service.toggleFavorite(articleId: article.id)

        let savedArticle = try await store.fetchArticle(id: article.id)
        #expect(membership == .favorites)
        #expect(savedArticle?.listMembership == .favorites)
    }

    @Test
    func archivingFromTheReaderIsSavedAndReportedWithoutFavorite() async throws {
        let store = GRDBArticleStore(database: try AppDatabase(DatabaseQueue()))
        let article = Article(url: URL(string: "https://example.com/article")!, title: "Article", isFavorite: true)
        _ = try await store.saveArticle(article)
        let service = ReaderService(articleStore: store, contentDataSource: TestContentDataSource())

        let membership = try await service.toggleArchive(articleId: article.id)

        let savedArticle = try await store.fetchArticle(id: article.id)
        #expect(membership == .archived)
        #expect(savedArticle?.listMembership == .archived)
    }

    @Test
    func togglingADeletedArticleReportsThatItIsMissing() async throws {
        let store = GRDBArticleStore(database: try AppDatabase(DatabaseQueue()))
        let article = Article(url: URL(string: "https://example.com/article")!, title: "Article")
        _ = try await store.saveArticle(article)
        try await store.deleteArticle(id: article.id)
        let service = ReaderService(articleStore: store, contentDataSource: TestContentDataSource())

        await #expect(throws: ReaderServiceError.articleNotFound) {
            _ = try await service.toggleFavorite(articleId: article.id)
        }
        await #expect(throws: ReaderServiceError.articleNotFound) {
            _ = try await service.toggleArchive(articleId: article.id)
        }
    }
}

@MainActor
private struct LateCanceledContentSource: ContentDataSourceProtocol {
    func validateURL(_ url: URL) async throws -> URL { url }
    func fetchMetadata(for url: URL, timeout: TimeInterval?) async throws -> ArticleMetadata {
        throw ArticleMetadataError.noMetadata
    }
    func fetchContent(for url: URL, timeout: TimeInterval?, forceRefresh: Bool, skipCache: Bool) async throws -> ArticleContent {
        withUnsafeCurrentTask { $0?.cancel() }
        return ArticleContent(title: "Late", thumbnailURL: URL(string: "https://example.com/late.jpg"), content: "Late body", wordCount: 2)
    }
}
