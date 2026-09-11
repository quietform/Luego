import Foundation

struct ArticleSaveResult {
    let article: Article
    let isNew: Bool
}

@MainActor
protocol ArticleServiceProtocol: Sendable {
    func getAllArticles() async throws -> [Article]
    func observeArticles() -> AsyncThrowingStream<[Article], Error>
    func refreshArticles() async throws
    func isArticleSaved(url: URL) async throws -> Bool
    func addArticle(url: URL, savedDate: Date) async throws -> ArticleSaveResult
    func deleteArticle(id: UUID) async throws
    func toggleFavorite(id: UUID) async throws
    func toggleArchive(id: UUID) async throws
    func saveEphemeralArticle(_ ephemeralArticle: EphemeralArticle) async throws -> Article
    func forceReSyncAllArticles() async throws -> Int
}

@MainActor
final class ArticleService: ArticleServiceProtocol {
    private let articleStore: ArticleStoreProtocol
    private let contentDataSource: ContentDataSourceProtocol
    private let syncEngineManager: SyncEngineManagerProtocol

    init(
        articleStore: ArticleStoreProtocol,
        contentDataSource: ContentDataSourceProtocol,
        syncEngineManager: SyncEngineManagerProtocol
    ) {
        self.articleStore = articleStore
        self.contentDataSource = contentDataSource
        self.syncEngineManager = syncEngineManager
    }

    func getAllArticles() async throws -> [Article] {
        try articleStore.fetchAllArticles()
    }

    func observeArticles() -> AsyncThrowingStream<[Article], Error> {
        articleStore.observeArticles()
    }

    func refreshArticles() async throws {
        _ = try await syncEngineManager.refresh(mode: .smart)
    }

    func isArticleSaved(url: URL) async throws -> Bool {
        let validatedURL = try await contentDataSource.validateURL(url)
        return try articleStore.fetchArticle(url: validatedURL) != nil
    }

    func addArticle(url: URL, savedDate: Date) async throws -> ArticleSaveResult {
        let validatedURL = try await contentDataSource.validateURL(url)
        if let existing = try articleStore.fetchArticle(url: validatedURL) {
            return ArticleSaveResult(article: existing, isNew: false)
        }

        let metadata = try await contentDataSource.fetchMetadata(for: validatedURL)
        if let existing = try articleStore.fetchArticle(url: validatedURL) {
            return ArticleSaveResult(article: existing, isNew: false)
        }

        let article = Article(
            url: validatedURL,
            title: metadata.title,
            savedDate: savedDate,
            thumbnailURL: metadata.thumbnailURL,
            publishedDate: metadata.publishedDate
        )

        do {
            let savedArticle = try articleStore.saveArticle(article)
            return ArticleSaveResult(article: savedArticle, isNew: true)
        } catch {
            if let existing = try articleStore.fetchArticle(url: validatedURL) {
                return ArticleSaveResult(article: existing, isNew: false)
            }
            throw error
        }
    }

    func deleteArticle(id: UUID) async throws {
        try articleStore.deleteArticle(id: id)
    }

    func toggleFavorite(id: UUID) async throws {
        try articleStore.toggleFavorite(id: id)
    }

    func toggleArchive(id: UUID) async throws {
        try articleStore.toggleArchive(id: id)
    }

    func saveEphemeralArticle(_ ephemeralArticle: EphemeralArticle) async throws -> Article {
        if let existingArticle = try articleStore.fetchArticle(url: ephemeralArticle.url) {
            return existingArticle
        }

        let article = Article(
            url: ephemeralArticle.url,
            title: ephemeralArticle.title,
            content: ephemeralArticle.content,
            thumbnailURL: ephemeralArticle.thumbnailURL,
            publishedDate: ephemeralArticle.publishedDate
        )

        do {
            return try articleStore.saveArticle(article)
        } catch {
            if let existingArticle = try articleStore.fetchArticle(url: ephemeralArticle.url) {
                Logger.article.debug("Duplicate detected via constraint: \(ephemeralArticle.url.absoluteString)")
                return existingArticle
            }
            throw error
        }
    }

    func forceReSyncAllArticles() async throws -> Int {
        try await syncEngineManager.refresh(mode: .fullRepair)
    }
}
