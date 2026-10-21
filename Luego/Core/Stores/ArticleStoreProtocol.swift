import Foundation

struct ArticleSaveResult {
    let article: Article
    let isNew: Bool
}

@MainActor
protocol ArticleStoreProtocol: AnyObject {
    func fetchAllArticles() async throws -> [Article]
    func observeArticles() -> AsyncThrowingStream<[Article], Error>
    func fetchArticle(id: UUID) async throws -> Article?
    func fetchArticle(url: URL) async throws -> Article?
    func saveArticle(_ article: Article) async throws -> ArticleSaveResult
    func updateContent(id: UUID, content: ArticleContent, forceRefresh: Bool) async throws -> Article?
    func deleteArticle(id: UUID) async throws
    func toggleFavorite(id: UUID) async throws
    func toggleArchive(id: UUID) async throws
    func updateReadPosition(id: UUID, position: Double) async throws
    func countArticles() async throws -> Int
}

@MainActor
protocol ArticleRecordStoreProtocol: AnyObject {
    func fetchAllRecords() async throws -> [ArticleRecord]
    func fetchRecord(id: UUID) async throws -> ArticleRecord?
    func fetchRecord(recordName: String) async throws -> ArticleRecord?
    func fetchRecord(url: URL) async throws -> ArticleRecord?
    func saveRecord(_ record: ArticleRecord) async throws
    func deleteRecord(recordName: String) async throws
    func updateCloudKitSystemFields(recordName: String, fields: Data?) async throws
    func countArticles() async throws -> Int
}
