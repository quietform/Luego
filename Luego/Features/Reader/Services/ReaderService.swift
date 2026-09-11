import Foundation

enum ReaderServiceError: Error, LocalizedError {
    case articleNotFound

    var errorDescription: String? {
        switch self {
        case .articleNotFound:
            return "Article not found in database"
        }
    }
}

@MainActor
protocol ReaderServiceProtocol: Sendable {
    func fetchContent(for article: Article, forceRefresh: Bool) async throws -> Article
    func updateReadPosition(articleId: UUID, position: Double) async throws
}

@MainActor
final class ReaderService: ReaderServiceProtocol {
    private let articleStore: ArticleStoreProtocol
    private let contentDataSource: ContentDataSourceProtocol

    init(
        articleStore: ArticleStoreProtocol,
        contentDataSource: ContentDataSourceProtocol
    ) {
        self.articleStore = articleStore
        self.contentDataSource = contentDataSource
    }

    func fetchContent(for article: Article, forceRefresh: Bool = false) async throws -> Article {
        let articleId = article.id

        Logger.reader.debug("fetchContent() called for article \(articleId)")

        guard forceRefresh || article.content == nil else {
            Logger.reader.debug("Content already exists, returning cached")
            return article
        }

        Logger.reader.debug("Fetching article content")
        let content = try await contentDataSource.fetchContent(for: article.url, timeout: nil, forceRefresh: forceRefresh)

        guard let freshArticle = try articleStore.fetchArticle(id: articleId) else {
            Logger.reader.error("Article \(articleId) not found after fetch")
            throw ReaderServiceError.articleNotFound
        }

        if forceRefresh || freshArticle.content == nil, !content.content.isEmpty {
            freshArticle.content = content.content
        }

        if forceRefresh || freshArticle.wordCount == nil, let wordCount = content.wordCount {
            freshArticle.wordCount = wordCount
        }
        if forceRefresh || freshArticle.thumbnailURL == nil, let thumbnailURL = content.thumbnailURL {
            freshArticle.thumbnailURL = thumbnailURL
        }

        _ = try articleStore.saveArticle(freshArticle)
        Logger.reader.debug("Content saved for article \(articleId)")
        return freshArticle
    }

    func updateReadPosition(articleId: UUID, position: Double) async throws {
        try articleStore.updateReadPosition(id: articleId, position: position)
    }
}
