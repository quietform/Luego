import Foundation

@MainActor
protocol ArticleServiceProtocol: Sendable {
    func getAllArticles() async throws -> [Article]
    func observeArticles() -> AsyncThrowingStream<[Article], Error>
    func refreshArticles() async throws
    func isArticleSaved(url: URL) async throws -> Bool
    func addArticle(url: URL) async throws -> Article
    func deleteArticle(id: UUID) async throws
    func updateArticle(_ article: Article) async throws
    func toggleFavorite(id: UUID) async throws
    func toggleArchive(id: UUID) async throws
    func saveEphemeralArticle(_ ephemeralArticle: EphemeralArticle) async throws -> Article
    func forceReSyncAllArticles() async throws -> Int
}

@MainActor
final class ArticleService: ArticleServiceProtocol {
    private let articleStore: ArticleStoreProtocol
    private let metadataDataSource: MetadataDataSourceProtocol
    private let syncEngineManager: SyncEngineManagerProtocol

    init(
        articleStore: ArticleStoreProtocol,
        metadataDataSource: MetadataDataSourceProtocol,
        syncEngineManager: SyncEngineManagerProtocol
    ) {
        self.articleStore = articleStore
        self.metadataDataSource = metadataDataSource
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
        let validatedURL = try await metadataDataSource.validateURL(url)
        return try articleStore.fetchArticle(url: validatedURL) != nil
    }

    func addArticle(url: URL) async throws -> Article {
        let validatedURL = try await metadataDataSource.validateURL(url)

        if let existingArticle = try articleStore.fetchArticle(url: validatedURL) {
            Logger.article.debug("Duplicate detected: \(validatedURL.absoluteString)")
            return existingArticle
        }

        let metadata = try await metadataDataSource.fetchMetadata(for: validatedURL)

        let article = Article(
            id: UUID(),
            url: validatedURL,
            title: metadata.title,
            content: nil,
            savedDate: Date(),
            thumbnailURL: metadata.thumbnailURL,
            publishedDate: metadata.publishedDate,
            readPosition: 0
        )

        Logger.article.debug("[ThumbnailDebug] Article Storage - URL: \(validatedURL.absoluteString)")
        Logger.article.debug("[ThumbnailDebug] Article Storage - thumbnailURL: \(metadata.thumbnailURL?.absoluteString ?? "nil")")

        do {
            return try articleStore.saveArticle(article)
        } catch {
            if let existingArticle = try articleStore.fetchArticle(url: validatedURL) {
                Logger.article.debug("Duplicate detected after error: \(validatedURL.absoluteString)")
                return existingArticle
            }
            throw error
        }
    }

    func deleteArticle(id: UUID) async throws {
        try articleStore.deleteArticle(id: id)
    }

    func updateArticle(_ article: Article) async throws {
        _ = try articleStore.saveArticle(article)
    }

    func toggleFavorite(id: UUID) async throws {
        guard let article = try articleStore.fetchArticle(id: id) else {
            return
        }

        article.isFavorite.toggle()
        if article.isFavorite {
            article.isArchived = false
        }

        _ = try articleStore.saveArticle(article)
    }

    func toggleArchive(id: UUID) async throws {
        guard let article = try articleStore.fetchArticle(id: id) else {
            return
        }

        article.isArchived.toggle()
        if article.isArchived {
            article.isFavorite = false
        }

        _ = try articleStore.saveArticle(article)
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
