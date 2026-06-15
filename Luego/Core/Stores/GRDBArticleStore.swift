import Foundation
import GRDB

@MainActor
final class GRDBArticleStore: ArticleStoreProtocol {
    private let database: AppDatabase
    weak var syncEngineManager: SyncEngineManagerProtocol?
    private var articleCache: [UUID: Article] = [:]

    private let visibleArticlesSQL = """
        SELECT * FROM articles
        WHERE deletedAt IS NULL
        ORDER BY savedDate DESC
        """

    init(database: AppDatabase) {
        self.database = database
    }

    func fetchAllArticles() throws -> [Article] {
        let records = try database.reader.read { db in
            try ArticleRecord.fetchAll(
                db,
                sql: self.visibleArticlesSQL
            )
        }
        return records.map(makeDetachedArticle(from:))
    }

    func fetchAllRecords() throws -> [ArticleRecord] {
        try database.reader.read { db in
            try ArticleRecord.fetchAll(
                db,
                sql: "SELECT * FROM articles ORDER BY savedDate DESC"
            )
        }
        .map(normalizedRecord(from:))
    }

    func observeArticles() -> AsyncThrowingStream<[Article], Error> {
        let observation = ValueObservation.tracking { db in
            try ArticleRecord.fetchAll(
                db,
                sql: self.visibleArticlesSQL
            )
        }

        return AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                do {
                    for try await records in observation.values(in: database.reader) {
                        continuation.yield(materializeObservedVisibleArticles(from: records))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func fetchArticle(id: UUID) throws -> Article? {
        guard let record = try fetchRecord(id: id), record.deletedAt == nil else {
            return nil
        }
        return makeDetachedArticle(from: record)
    }

    func fetchArticle(url: URL) throws -> Article? {
        guard let record = try fetchRecord(url: url), record.deletedAt == nil else {
            return nil
        }
        return makeDetachedArticle(from: record)
    }

    func fetchRecord(id: UUID) throws -> ArticleRecord? {
        try fetchRecord(recordName: id.uuidString)
    }

    func fetchRecord(recordName: String) throws -> ArticleRecord? {
        try database.reader.read { db in
            try ArticleRecord.fetchOne(db, key: recordName)
        }
        .map(normalizedRecord(from:))
    }

    func fetchRecord(url: URL) throws -> ArticleRecord? {
        try database.reader.read { db in
            try ArticleRecord.fetchOne(
                db,
                sql: "SELECT * FROM articles WHERE url = ? LIMIT 1",
                arguments: [url.absoluteString]
            )
        }
        .map(normalizedRecord(from:))
    }

    func saveArticle(_ article: Article) throws -> Article {
        if let existingRecord = try fetchRecord(url: article.url),
           existingRecord.id != article.id.uuidString {
            if existingRecord.deletedAt == nil {
                return makeDetachedArticle(from: existingRecord)
            }

            var revivedRecord = ArticleRecord(article)
            revivedRecord.id = existingRecord.id
            revivedRecord.author = existingRecord.author
            revivedRecord.cloudKitSystemFields = existingRecord.cloudKitSystemFields
            revivedRecord.deletedAt = nil
            try saveRecord(revivedRecord)
            syncEngineManager?.enqueueSave(for: ArticleRecord.makeRecordID(for: revivedRecord.id))
            articleCache.removeValue(forKey: article.id)
            return makeDetachedArticle(from: revivedRecord)
        }

        var record = ArticleRecord(article)
        if let existingRecord = try fetchRecord(id: article.id) {
            record.author = existingRecord.author
            record.cloudKitSystemFields = existingRecord.cloudKitSystemFields
        }
        record.deletedAt = nil

        try saveRecord(record)
        syncEngineManager?.enqueueSave(for: ArticleRecord.makeRecordID(for: record.id))
        return makeDetachedArticle(from: record)
    }

    func insertArticle(_ article: Article) throws {
        _ = try saveArticle(article)
    }

    func saveRecord(_ record: ArticleRecord) throws {
        var normalizedRecord = record
        normalizedRecord.normalizeListMembership()
        try database.writer.write { db in
            try normalizedRecord.save(db)
        }
    }

    func deleteArticle(id: UUID) throws {
        var didTombstone = false
        try database.writer.write { db in
            guard var record = try ArticleRecord.fetchOne(db, key: id.uuidString),
                  record.deletedAt == nil else {
                return
            }

            record.deletedAt = Date()
            try record.save(db)
            didTombstone = true
        }
        if didTombstone {
            articleCache.removeValue(forKey: id)
            syncEngineManager?.enqueueSave(for: ArticleRecord.makeRecordID(for: id.uuidString))
        }
    }

    func deleteRecord(recordName: String) throws {
        try database.writer.write { db in
            _ = try ArticleRecord.deleteOne(db, key: recordName)
        }
        if let articleID = UUID(uuidString: recordName) {
            articleCache.removeValue(forKey: articleID)
        }
    }

    func clearCloudKitSystemFields(recordName: String) throws {
        try database.writer.write { db in
            guard var record = try ArticleRecord.fetchOne(db, key: recordName) else {
                return
            }

            record.cloudKitSystemFields = nil
            try record.save(db)
        }
    }

    func toggleFavorite(id: UUID) throws {
        var didUpdate = false
        try database.writer.write { db in
            guard var record = try ArticleRecord.fetchOne(db, key: id.uuidString) else {
                return
            }

            guard record.deletedAt == nil else {
                return
            }

            record.toggleFavoriteMembership()
            try record.save(db)
            didUpdate = true
        }
        if didUpdate {
            syncEngineManager?.enqueueSave(for: ArticleRecord.makeRecordID(for: id.uuidString))
        }
    }

    func toggleArchive(id: UUID) throws {
        var didUpdate = false
        try database.writer.write { db in
            guard var record = try ArticleRecord.fetchOne(db, key: id.uuidString) else {
                return
            }

            guard record.deletedAt == nil else {
                return
            }

            record.toggleArchiveMembership()
            try record.save(db)
            didUpdate = true
        }
        if didUpdate {
            syncEngineManager?.enqueueSave(for: ArticleRecord.makeRecordID(for: id.uuidString))
        }
    }

    func updateReadPosition(id: UUID, position: Double) throws {
        var didUpdate = false
        try database.writer.write { db in
            guard var record = try ArticleRecord.fetchOne(db, key: id.uuidString) else {
                return
            }

            guard record.deletedAt == nil else {
                return
            }

            record.readPosition = position
            try record.save(db)
            didUpdate = true
        }
        if didUpdate {
            syncEngineManager?.enqueueSave(for: ArticleRecord.makeRecordID(for: id.uuidString))
        }
    }

    func countArticles() throws -> Int {
        try database.reader.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM articles WHERE deletedAt IS NULL"
            ) ?? 0
        }
    }

    private func materializeObservedVisibleArticles(from records: [ArticleRecord]) -> [Article] {
        let articles = records.compactMap { record -> Article? in
            guard record.deletedAt == nil else {
                return nil
            }
            return materializeObservedArticle(from: record)
        }

        let visibleIDs = Set(articles.map(\.id))
        articleCache = articleCache.filter { visibleIDs.contains($0.key) }

        return articles
    }

    private func materializeObservedArticle(from record: ArticleRecord) -> Article {
        let record = normalizedRecord(from: record)
        let articleID = UUID(uuidString: record.id) ?? UUID()

        if let article = articleCache[articleID] {
            apply(record, to: article, articleID: articleID)
            return article
        }

        let article = Article(
            id: articleID,
            url: record.url,
            title: record.title,
            content: record.content,
            savedDate: record.savedDate,
            thumbnailURL: record.thumbnailURL,
            publishedDate: record.publishedDate,
            readPosition: record.readPosition,
            isFavorite: record.isFavorite,
            isArchived: record.isArchived,
            wordCount: record.wordCount
        )

        articleCache[articleID] = article
        return article
    }

    private func makeDetachedArticle(from record: ArticleRecord) -> Article {
        let record = normalizedRecord(from: record)
        return Article(
            id: UUID(uuidString: record.id) ?? UUID(),
            url: record.url,
            title: record.title,
            content: record.content,
            savedDate: record.savedDate,
            thumbnailURL: record.thumbnailURL,
            publishedDate: record.publishedDate,
            readPosition: record.readPosition,
            isFavorite: record.isFavorite,
            isArchived: record.isArchived,
            wordCount: record.wordCount
        )
    }

    private func apply(_ record: ArticleRecord, to article: Article, articleID: UUID) {
        let record = normalizedRecord(from: record)
        if article.id != articleID {
            article.id = articleID
        }
        if article.url != record.url {
            article.url = record.url
        }
        if article.title != record.title {
            article.title = record.title
        }
        if article.content != record.content {
            article.content = record.content
        }
        if article.savedDate != record.savedDate {
            article.savedDate = record.savedDate
        }
        if article.thumbnailURL != record.thumbnailURL {
            article.thumbnailURL = record.thumbnailURL
        }
        if article.publishedDate != record.publishedDate {
            article.publishedDate = record.publishedDate
        }
        if article.readPosition != record.readPosition {
            article.readPosition = record.readPosition
        }
        article.applyListMembership(record.listMembership)
        if article.wordCount != record.wordCount {
            article.wordCount = record.wordCount
        }
    }

    private func normalizedRecord(from record: ArticleRecord) -> ArticleRecord {
        var normalizedRecord = record
        normalizedRecord.normalizeListMembership()
        return normalizedRecord
    }
}
