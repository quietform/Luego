import Foundation
import GRDB
import Testing

@MainActor
struct ReaderServiceTests {
    @Test(arguments: [false, true])
    func canceledFetchDoesNotPersistLateContent(forceRefresh: Bool) async throws {
        let store = GRDBArticleStore(database: try AppDatabase(DatabaseQueue()))
        let previousContent = forceRefresh ? "Previously saved body" : nil
        let article = Article(url: URL(string: "https://example.com/article")!, title: "Original", content: previousContent)
        _ = try store.saveArticle(article)
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
        let savedArticle = try store.fetchArticle(id: article.id)
        #expect(savedArticle?.content == previousContent)
        #expect(savedArticle?.wordCount == nil)
        #expect(savedArticle?.thumbnailURL == nil)
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
