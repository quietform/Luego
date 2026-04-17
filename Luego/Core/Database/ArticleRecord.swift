import CloudKit
import Foundation
import GRDB

enum ArticleRecordError: Error {
    case missingURL
    case missingTitle
}

struct ArticleRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "articles"
    static let recordType = "Article"

    var id: String
    var url: URL
    var title: String
    var content: String?
    var savedDate: Date
    var thumbnailURL: URL?
    var publishedDate: Date?
    var readPosition: Double
    var isFavorite: Bool
    var isArchived: Bool
    var author: String?
    var wordCount: Int?
    var cloudKitSystemFields: Data?
    var deletedAt: Date?

    init(
        id: String,
        url: URL,
        title: String,
        content: String? = nil,
        savedDate: Date = Date(),
        thumbnailURL: URL? = nil,
        publishedDate: Date? = nil,
        readPosition: Double = 0,
        isFavorite: Bool = false,
        isArchived: Bool = false,
        author: String? = nil,
        wordCount: Int? = nil,
        cloudKitSystemFields: Data? = nil,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.content = content
        self.savedDate = savedDate
        self.thumbnailURL = thumbnailURL
        self.publishedDate = publishedDate
        self.readPosition = readPosition
        self.isFavorite = isFavorite
        self.isArchived = isArchived
        self.author = author
        self.wordCount = wordCount
        self.cloudKitSystemFields = cloudKitSystemFields
        self.deletedAt = deletedAt
    }

    @MainActor
    init(_ article: Article, cloudKitSystemFields: Data? = nil) {
        let membership = article.listMembership
        self.init(
            id: article.id.uuidString,
            url: article.url,
            title: article.title,
            content: article.content,
            savedDate: article.savedDate,
            thumbnailURL: article.thumbnailURL,
            publishedDate: article.publishedDate,
            readPosition: article.readPosition,
            isFavorite: membership.isFavorite,
            isArchived: membership.isArchived,
            wordCount: article.wordCount,
            cloudKitSystemFields: cloudKitSystemFields,
            deletedAt: nil
        )
    }

    init(record: CKRecord) throws {
        guard let url = record["url"] as? String, let url = URL(string: url) else {
            throw ArticleRecordError.missingURL
        }

        guard let title = record["title"] as? String else {
            throw ArticleRecordError.missingTitle
        }

        self.init(
            id: record.recordID.recordName,
            url: url,
            title: title,
            content: record["content"] as? String,
            savedDate: record["savedDate"] as? Date ?? Date(),
            thumbnailURL: (record["thumbnailURL"] as? String).flatMap(URL.init(string:)),
            publishedDate: record["publishedDate"] as? Date,
            readPosition: record["readPosition"] as? Double ?? 0,
            isFavorite: record["isFavorite"] as? Bool ?? false,
            isArchived: record["isArchived"] as? Bool ?? false,
            author: record["author"] as? String,
            wordCount: record["wordCount"] as? Int,
            cloudKitSystemFields: Self.encodeSystemFields(record),
            deletedAt: record["deletedAt"] as? Date
        )
        normalizeListMembership()
    }

    @MainActor
    func toArticle() -> Article {
        let membership = listMembership
        return Article(
            id: UUID(uuidString: id) ?? UUID(),
            url: url,
            title: title,
            content: content,
            savedDate: savedDate,
            thumbnailURL: thumbnailURL,
            publishedDate: publishedDate,
            readPosition: readPosition,
            isFavorite: membership.isFavorite,
            isArchived: membership.isArchived,
            wordCount: wordCount
        )
    }

    func makeCKRecord(recordID: CKRecord.ID) -> CKRecord {
        let membership = listMembership
        let record: CKRecord
        if let cloudKitSystemFields,
           let coder = try? NSKeyedUnarchiver(forReadingFrom: cloudKitSystemFields),
           let existingRecord = CKRecord(coder: coder) {
            coder.finishDecoding()
            record = existingRecord
        } else {
            record = CKRecord(recordType: Self.recordType, recordID: recordID)
        }

        record["url"] = url.absoluteString
        record["title"] = title
        record["content"] = content
        record["savedDate"] = savedDate
        record["thumbnailURL"] = thumbnailURL?.absoluteString
        record["publishedDate"] = publishedDate
        record["readPosition"] = readPosition
        record["isFavorite"] = membership.isFavorite
        record["isArchived"] = membership.isArchived
        record["author"] = author
        record["wordCount"] = wordCount
        record["deletedAt"] = deletedAt
        return record
    }

    static func makeRecordID(for articleID: String) -> CKRecord.ID {
        CKRecord.ID(recordName: articleID, zoneID: CKRecordZone.default().zoneID)
    }

    static func encodeSystemFields(_ record: CKRecord) -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)
        archiver.finishEncoding()
        return archiver.encodedData
    }

    var listMembership: ArticleListMembership {
        ArticleListMembership(isFavorite: isFavorite, isArchived: isArchived)
    }

    mutating func normalizeListMembership() {
        let membership = listMembership
        isFavorite = membership.isFavorite
        isArchived = membership.isArchived
    }
}
