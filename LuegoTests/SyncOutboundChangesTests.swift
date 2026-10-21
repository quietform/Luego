import CloudKit
import Foundation
import GRDB
import Testing

@MainActor
struct SyncOutboundChangesTests {
    @Test(arguments: [false, true])
    func failedReadsDeferChangesUntilTheStoreCanBeRead(cancelled: Bool) async throws {
        let database = try AppDatabase(DatabaseQueue())
        let store = GRDBArticleStore(database: database)
        let record = ArticleRecord(Article(url: URL(string: "https://example.com/retry")!, title: "Retry"))
        try await store.saveRecord(record)
        let recordID = ArticleRecord.makeRecordID(for: record.id)
        let pendingChanges: [CKSyncEngine.PendingRecordZoneChange] = [.saveRecord(recordID)]
        if !cancelled {
            try await database.writer.write { db in
                try db.execute(sql: "ALTER TABLE articles RENAME TO unavailable_articles")
            }
        }

        let attempt = Task {
            if cancelled { withUnsafeCurrentTask { $0?.cancel() } }
            return try await SyncEngineManager.prepareRecordZoneChangeBatch(pendingChanges, store: store)
        }
        do {
            _ = try await attempt.value
            Issue.record("A failed read must defer the batch instead of acknowledging a missing record")
        } catch {
            if cancelled {
                #expect(error is CancellationError)
            } else {
                #expect(error is DatabaseError)
            }
        }

        if !cancelled {
            try await database.writer.write { db in
                try db.execute(sql: "ALTER TABLE unavailable_articles RENAME TO articles")
            }
        }
        let retry = try await SyncEngineManager.prepareRecordZoneChangeBatch(pendingChanges, store: store)
        #expect(retry.missingRecordIDs.isEmpty)
        #expect(retry.batch?.recordsToSave.map(\.recordID) == [recordID])
    }

    @Test
    func preparingChangesSeparatesConfirmedMissingRecordsFromUploads() async throws {
        let store = GRDBArticleStore(database: try AppDatabase(DatabaseQueue()))
        let record = ArticleRecord(Article(url: URL(string: "https://example.com/upload")!, title: "Upload"))
        try await store.saveRecord(record)
        let savedID = ArticleRecord.makeRecordID(for: record.id)
        let missingID = ArticleRecord.makeRecordID(for: UUID().uuidString)
        let deletedID = ArticleRecord.makeRecordID(for: UUID().uuidString)

        let prepared = try await SyncEngineManager.prepareRecordZoneChangeBatch(
            [.saveRecord(savedID), .saveRecord(missingID), .deleteRecord(deletedID)],
            store: store
        )

        #expect(prepared.missingRecordIDs == [missingID])
        let batch = try #require(prepared.batch)
        #expect(batch.recordsToSave.map(\.recordID) == [savedID])
        #expect(batch.recordsToSave.first?["title"] as? String == "Upload")
        #expect(batch.recordIDsToDelete == [deletedID])
    }
}
