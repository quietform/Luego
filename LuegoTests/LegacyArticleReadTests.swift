import Foundation
import GRDB
import Testing

@MainActor
struct LegacyArticleReadTests {
    @Test(arguments: [false, true])
    func legacyReadReturnsSnapshotsWithoutBlockingMainActor(cancelled: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("legacy.sqlite")
        let writer = try DatabaseQueue(path: url.path)
        let id = UUID()
        var bytes = id.uuid
        let identifier = withUnsafeBytes(of: &bytes) { Data($0) }
        try await writer.write { db in
            try db.execute(sql: "CREATE TABLE ZARTICLE (Z_PK INTEGER PRIMARY KEY, ZID BLOB, ZURL TEXT, ZTITLE TEXT, ZCONTENT TEXT, ZSAVEDDATE REAL, ZTHUMBNAILURL TEXT, ZPUBLISHEDDATE REAL, ZREADPOSITION REAL, ZISFAVORITE INTEGER, ZISARCHIVED INTEGER, ZAUTHOR TEXT, ZWORDCOUNT INTEGER)")
            try db.execute(sql: "INSERT INTO ZARTICLE (ZID, ZURL, ZTITLE, ZCONTENT, ZSAVEDDATE, ZREADPOSITION, ZISFAVORITE, ZISARCHIVED, ZWORDCOUNT) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)", arguments: [identifier, "https://example.com/legacy", "Legacy title", "Legacy body", 123, 0.5, 1, 0, 2])
        }
        let source = LegacySwiftDataArticleDataSource(storeURL: url)
        var mainActorRan = false
        let heartbeat = Task { @MainActor in mainActorRan = true }

        let read = Task {
            if cancelled { withUnsafeCurrentTask { $0?.cancel() } }
            return try await source.fetchRecords()
        }
        let records = try await read.value
        let progressedWhileReading = mainActorRan
        await heartbeat.value

        #expect(progressedWhileReading)
        #expect(records.count == 1)
        #expect(records.first?.id == id.uuidString)
        #expect(records.first?.content == "Legacy body")
        #expect(records.first?.wordCount == 2)
        #expect(records.first?.readPosition == 0.5)
        #expect(records.first?.isFavorite == true)
    }
}
