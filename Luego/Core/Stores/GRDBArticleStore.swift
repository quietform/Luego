import Foundation
import GRDB

@MainActor
final class GRDBArticleStore: ArticleStoreProtocol, ArticleRecordStoreProtocol {
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

    func fetchAllArticles() async throws -> [Article] {
        let sql = visibleArticlesSQL
        let records = try await database.reader.read { db in
            try ArticleRecord.fetchAll(
                db,
                sql: sql
            )
        }
        return records.map(makeDetachedArticle(from:))
    }

    func fetchAllRecords() async throws -> [ArticleRecord] {
        try await database.reader.read { db in
            try ArticleRecord.fetchAll(
                db,
                sql: "SELECT * FROM articles ORDER BY savedDate DESC"
            )
        }
        .map(normalizedRecord(from:))
    }

    func observeArticles() -> AsyncThrowingStream<[Article], Error> {
        let sql = visibleArticlesSQL
        let observation = ValueObservation.tracking { db in
            try ArticleRecord.fetchAll(
                db,
                sql: sql
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

    func fetchArticle(id: UUID) async throws -> Article? {
        guard let record = try await fetchRecord(id: id), record.deletedAt == nil else {
            return nil
        }
        return makeDetachedArticle(from: record)
    }

    func fetchArticle(url: URL) async throws -> Article? {
        guard let record = try await fetchRecord(url: url), record.deletedAt == nil else {
            return nil
        }
        return makeDetachedArticle(from: record)
    }

    func fetchRecord(id: UUID) async throws -> ArticleRecord? {
        try await fetchRecord(recordName: id.uuidString)
    }

    func fetchRecord(recordName: String) async throws -> ArticleRecord? {
        try await database.reader.read { db in
            try ArticleRecord.fetchOne(db, key: recordName)
        }
        .map(normalizedRecord(from:))
    }

    func fetchRecord(url: URL) async throws -> ArticleRecord? {
        try await database.reader.read { db in
            try ArticleRecord.fetchOne(
                db,
                sql: "SELECT * FROM articles WHERE url = ? LIMIT 1",
                arguments: [url.absoluteString]
            )
        }
        .map(normalizedRecord(from:))
    }

    func saveArticle(_ article: Article) async throws -> ArticleSaveResult {
        let incoming = ArticleRecord(article)
        let result = try await database.writer.write { db -> (record: ArticleRecord, didSave: Bool, isNew: Bool) in
            var record = incoming
            let existing = try ArticleRecord.fetchOne(db, sql: "SELECT * FROM articles WHERE url = ? LIMIT 1", arguments: [incoming.url.absoluteString])
                ?? ArticleRecord.fetchOne(db, key: incoming.id)
            if let existing {
                if existing.id != incoming.id {
                    guard existing.deletedAt != nil else { return (existing, false, false) }
                    record.id = existing.id
                }
                record.author = existing.author
                record.cloudKitSystemFields = existing.cloudKitSystemFields
            }
            record.deletedAt = nil
            record.normalizeListMembership()
            try record.save(db)
            return (record, true, existing == nil || existing?.deletedAt != nil)
        }
        if result.record.id != incoming.id {
            articleCache.removeValue(forKey: article.id)
        }
        if result.didSave {
            syncEngineManager?.enqueueSave(for: ArticleRecord.makeRecordID(for: result.record.id))
        }
        return ArticleSaveResult(article: makeDetachedArticle(from: result.record), isNew: result.isNew)
    }

    func updateContent(id: UUID, content: ArticleContent, forceRefresh: Bool) async throws -> Article? {
        let saved = try await database.writer.write { db -> ArticleRecord? in
            guard var record = try ArticleRecord.fetchOne(db, key: id.uuidString), record.deletedAt == nil else { return nil }
            if (forceRefresh || record.content == nil), !content.content.isEmpty {
                record.content = content.content
            }
            if (forceRefresh || record.wordCount == nil), let wordCount = content.wordCount {
                record.wordCount = wordCount
            }
            if (forceRefresh || record.thumbnailURL == nil), let thumbnailURL = content.thumbnailURL {
                record.thumbnailURL = thumbnailURL
            }
            record.normalizeListMembership()
            try record.save(db)
            return record
        }
        guard let saved else { return nil }
        syncEngineManager?.enqueueSave(for: ArticleRecord.makeRecordID(for: saved.id))
        return makeDetachedArticle(from: saved)
    }

    func saveRecord(_ record: ArticleRecord) async throws {
        let normalizedRecord = normalizedRecord(from: record)
        try await database.writer.write { db in
            try normalizedRecord.save(db)
        }
    }

    func deleteArticle(id: UUID) async throws {
        let didTombstone = try await database.writer.write { db -> Bool in
            guard var record = try ArticleRecord.fetchOne(db, key: id.uuidString),
                  record.deletedAt == nil else {
                return false
            }

            record.deletedAt = Date()
            try record.save(db)
            return true
        }
        if didTombstone {
            articleCache.removeValue(forKey: id)
            syncEngineManager?.enqueueSave(for: ArticleRecord.makeRecordID(for: id.uuidString))
        }
    }

    func deleteRecord(recordName: String) async throws {
        try await database.writer.write { db in
            _ = try ArticleRecord.deleteOne(db, key: recordName)
        }
        if let articleID = UUID(uuidString: recordName) {
            articleCache.removeValue(forKey: articleID)
        }
    }

    func updateCloudKitSystemFields(recordName: String, fields: Data?) async throws {
        try await database.writer.write { db in
            try db.execute(sql: "UPDATE articles SET cloudKitSystemFields = ? WHERE id = ?", arguments: [fields, recordName])
        }
    }

    func toggleFavorite(id: UUID) async throws {
        let didUpdate = try await database.writer.write { db -> Bool in
            guard var record = try ArticleRecord.fetchOne(db, key: id.uuidString) else {
                return false
            }

            guard record.deletedAt == nil else {
                return false
            }

            record.toggleFavoriteMembership()
            try record.save(db)
            return true
        }
        if didUpdate {
            syncEngineManager?.enqueueSave(for: ArticleRecord.makeRecordID(for: id.uuidString))
        }
    }

    func toggleArchive(id: UUID) async throws {
        let didUpdate = try await database.writer.write { db -> Bool in
            guard var record = try ArticleRecord.fetchOne(db, key: id.uuidString) else {
                return false
            }

            guard record.deletedAt == nil else {
                return false
            }

            record.toggleArchiveMembership()
            try record.save(db)
            return true
        }
        if didUpdate {
            syncEngineManager?.enqueueSave(for: ArticleRecord.makeRecordID(for: id.uuidString))
        }
    }

    func updateReadPosition(id: UUID, position: Double) async throws {
        let didUpdate = try await database.writer.write { db -> Bool in
            guard var record = try ArticleRecord.fetchOne(db, key: id.uuidString) else {
                return false
            }

            guard record.deletedAt == nil else {
                return false
            }

            record.readPosition = position
            try record.save(db)
            return true
        }
        if didUpdate {
            syncEngineManager?.enqueueSave(for: ArticleRecord.makeRecordID(for: id.uuidString))
        }
    }

    func countArticles() async throws -> Int {
        try await database.reader.read { db in
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
