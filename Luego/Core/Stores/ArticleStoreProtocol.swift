import Foundation

@MainActor
protocol ArticleStoreProtocol: AnyObject {
    func fetchAllArticles() throws -> [Article]
    func observeArticles() -> AsyncThrowingStream<[Article], Error>
    func fetchArticle(id: UUID) throws -> Article?
    func fetchArticle(url: URL) throws -> Article?
    func saveArticle(_ article: Article) throws -> Article
    func deleteArticle(id: UUID) throws
    func toggleFavorite(id: UUID) throws
    func toggleArchive(id: UUID) throws
    func updateReadPosition(id: UUID, position: Double) throws
    func countArticles() throws -> Int
}

@MainActor
protocol ArticleRecordStoreProtocol: AnyObject {
    func fetchAllRecords() throws -> [ArticleRecord]
    func fetchRecord(id: UUID) throws -> ArticleRecord?
    func fetchRecord(recordName: String) throws -> ArticleRecord?
    func fetchRecord(url: URL) throws -> ArticleRecord?
    func saveRecord(_ record: ArticleRecord) throws
    func deleteRecord(recordName: String) throws
    func clearCloudKitSystemFields(recordName: String) throws
    func countArticles() throws -> Int
}
