import Foundation
import SQLite3

protocol LegacySwiftDataArticleDataSourceProtocol {
    func fetchArticles() throws -> [Article]
}

final class LegacySwiftDataArticleDataSource: LegacySwiftDataArticleDataSourceProtocol {
    private let fileManager: FileManager
    private let groupIdentifier: String

    init(
        fileManager: FileManager = .default,
        groupIdentifier: String = "group.com.esoxjem.Luego"
    ) {
        self.fileManager = fileManager
        self.groupIdentifier = groupIdentifier
    }

    func fetchArticles() throws -> [Article] {
        guard let storeURL = legacyStoreURL(),
              fileManager.fileExists(atPath: storeURL.path) else {
            return []
        }

        return try fetchArticles(from: storeURL)
    }

    private func legacyStoreURL() -> URL? {
        if let groupContainerURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: groupIdentifier
        ) {
            return groupContainerURL
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
                .appendingPathComponent("default.store")
        }

        guard let applicationSupportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }

        return applicationSupportURL.appendingPathComponent("default.store")
    }

    private func fetchArticles(from storeURL: URL) throws -> [Article] {
        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(
            storeURL.path,
            &database,
            SQLITE_OPEN_READONLY,
            nil
        )

        guard openResult == SQLITE_OK, let database else {
            let message = database.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            throw NSError(
                domain: "LegacySwiftDataArticleDataSource",
                code: Int(openResult),
                userInfo: [NSLocalizedDescriptionKey: "Failed to open legacy SwiftData store: \(message)"]
            )
        }
        defer { sqlite3_close(database) }

        guard hasArticleTable(in: database) else {
            return []
        }

        let query = """
            SELECT ZID, ZURL, ZTITLE, ZCONTENT, ZSAVEDDATE, ZTHUMBNAILURL, ZPUBLISHEDDATE, ZREADPOSITION, ZISFAVORITE, ZISARCHIVED, ZAUTHOR, ZWORDCOUNT
            FROM ZARTICLE
            ORDER BY ZSAVEDDATE DESC, Z_PK DESC
            """

        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(database, query, -1, &statement, nil)

        guard prepareResult == SQLITE_OK, let statement else {
            let message = String(cString: sqlite3_errmsg(database))
            throw NSError(
                domain: "LegacySwiftDataArticleDataSource",
                code: Int(prepareResult),
                userInfo: [NSLocalizedDescriptionKey: "Failed to query legacy SwiftData store: \(message)"]
            )
        }
        defer { sqlite3_finalize(statement) }

        var articles: [Article] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idData = blob(from: statement, column: 0),
                  let id = uuid(from: idData),
                  let urlString = string(from: statement, column: 1),
                  let url = URL(string: urlString),
                  let title = string(from: statement, column: 2),
                  !title.isEmpty else {
                continue
            }

            let content = string(from: statement, column: 3)
            let savedDate = date(from: statement, column: 4) ?? Date()
            let thumbnailURL = string(from: statement, column: 5).flatMap(URL.init(string:))
            let publishedDate = date(from: statement, column: 6)
            let readPosition = double(from: statement, column: 7) ?? 0
            let isFavorite = bool(from: statement, column: 8)
            let isArchived = bool(from: statement, column: 9)
            let wordCount = int(from: statement, column: 11)

            articles.append(
                Article(
                    id: id,
                    url: url,
                    title: title,
                    content: content,
                    savedDate: savedDate,
                    thumbnailURL: thumbnailURL,
                    publishedDate: publishedDate,
                    readPosition: readPosition,
                    isFavorite: isFavorite,
                    isArchived: isArchived,
                    wordCount: wordCount
                )
            )
        }

        return articles
    }

    private func hasArticleTable(in database: OpaquePointer) -> Bool {
        let query = "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'ZARTICLE' LIMIT 1"
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(database, query, -1, &statement, nil)

        guard prepareResult == SQLITE_OK, let statement else {
            return false
        }
        defer { sqlite3_finalize(statement) }

        return sqlite3_step(statement) == SQLITE_ROW
    }

    private func string(from statement: OpaquePointer, column: Int32) -> String? {
        guard let text = sqlite3_column_text(statement, column) else {
            return nil
        }

        return String(cString: text)
    }

    private func blob(from statement: OpaquePointer, column: Int32) -> Data? {
        guard let bytes = sqlite3_column_blob(statement, column) else {
            return nil
        }

        let length = Int(sqlite3_column_bytes(statement, column))
        return Data(bytes: bytes, count: length)
    }

    private func double(from statement: OpaquePointer, column: Int32) -> Double? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL else {
            return nil
        }

        return sqlite3_column_double(statement, column)
    }

    private func int(from statement: OpaquePointer, column: Int32) -> Int? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL else {
            return nil
        }

        return Int(sqlite3_column_int64(statement, column))
    }

    private func bool(from statement: OpaquePointer, column: Int32) -> Bool {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL else {
            return false
        }

        return sqlite3_column_int(statement, column) != 0
    }

    private func date(from statement: OpaquePointer, column: Int32) -> Date? {
        guard let value = double(from: statement, column: column) else {
            return nil
        }

        return Date(timeIntervalSinceReferenceDate: value)
    }

    private func uuid(from data: Data) -> UUID? {
        guard data.count == 16 else {
            return nil
        }

        let bytes = [UInt8](data)
        return UUID(
            uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3],
                bytes[4], bytes[5], bytes[6], bytes[7],
                bytes[8], bytes[9], bytes[10], bytes[11],
                bytes[12], bytes[13], bytes[14], bytes[15]
            )
        )
    }
}
