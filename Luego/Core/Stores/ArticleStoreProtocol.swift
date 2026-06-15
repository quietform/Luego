import Foundation

@MainActor
protocol ArticleStoreProtocol: AnyObject {
    func fetchAllArticles() throws -> [Article]
    func fetchAllRecords() throws -> [ArticleRecord]
    func observeArticles() -> AsyncThrowingStream<[Article], Error>
    func fetchArticle(id: UUID) throws -> Article?
    func fetchArticle(url: URL) throws -> Article?
    func fetchRecord(id: UUID) throws -> ArticleRecord?
    func fetchRecord(recordName: String) throws -> ArticleRecord?
    func fetchRecord(url: URL) throws -> ArticleRecord?
    func saveArticle(_ article: Article) throws -> Article
    func saveRecord(_ record: ArticleRecord) throws
    func deleteArticle(id: UUID) throws
    func deleteRecord(recordName: String) throws
    func clearCloudKitSystemFields(recordName: String) throws
    func toggleFavorite(id: UUID) throws
    func toggleArchive(id: UUID) throws
    func updateReadPosition(id: UUID, position: Double) throws
    func countArticles() throws -> Int
}

extension ArticleStoreProtocol {
    func fetchRecord(id: UUID) throws -> ArticleRecord? {
        try fetchArticle(id: id).map { ArticleRecord($0) }
    }

    func fetchRecord(recordName: String) throws -> ArticleRecord? {
        guard let articleID = UUID(uuidString: recordName) else {
            return nil
        }

        return try fetchRecord(id: articleID)
    }

    func fetchRecord(url: URL) throws -> ArticleRecord? {
        try fetchArticle(url: url).map { ArticleRecord($0) }
    }

    func saveRecord(_ record: ArticleRecord) throws {
        _ = try saveArticle(record.toArticle())
    }

    func toggleFavorite(id: UUID) throws {
        guard let article = try fetchArticle(id: id) else { return }
        article.toggleFavoriteMembership()
        _ = try saveArticle(article)
    }

    func toggleArchive(id: UUID) throws {
        guard let article = try fetchArticle(id: id) else { return }
        article.toggleArchiveMembership()
        _ = try saveArticle(article)
    }

    func countArticles() throws -> Int {
        try fetchAllArticles().count
    }
}
