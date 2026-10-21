import CloudKit
import GRDB
import Observation
import notify
import os

@Observable
@MainActor
final class ForegroundSyncWorkload {
    let library: ArticleListViewModel
    private var isApplying = false
    private var isVerifying = false
    private var errorMessage: String?
    @ObservationIgnored private let database: AppDatabase
    @ObservationIgnored private let store: GRDBArticleStore
    @ObservationIgnored private let enabled: Bool
    @ObservationIgnored private let isScrolling: @MainActor () -> Bool
    @ObservationIgnored private let batches: [[CKRecord]]
    @ObservationIgnored private let signposter = BenchmarkSignposts.signposter
    @ObservationIgnored private var batchTask: Task<Void, Never>?
    @ObservationIgnored private var completedBatches = 0
    @ObservationIgnored private var applied = 0
    @ObservationIgnored private var verified = 0
    @ObservationIgnored private var overlappingBatches = 0
    @ObservationIgnored private var overlappingRecords = 0

    init(database: AppDatabase, store: GRDBArticleStore, enabled: Bool, isScrolling: @escaping @MainActor () -> Bool) {
        self.database = database
        self.store = store
        self.enabled = enabled
        self.isScrolling = isScrolling
        let offline = OfflineSyncServices()
        library = ArticleListViewModel(
            articleService: ArticleService(articleStore: store, contentDataSource: OfflineContent(), syncEngineManager: offline),
            sharingService: offline,
            syncEngineManager: offline
        )
        batches = (0..<3).map { batch in
            (1...100).map { offset in
                let index = batch * 100 + offset
                var record = ForegroundSyncFixture.record(index: index)
                record.title = "Synced \(index)"
                record.content = ForegroundSyncFixture.updatedBody
                return record.makeCKRecord(recordID: ArticleRecord.makeRecordID(for: record.id))
            }
        }
        library.startObservingArticles()
    }

    var libraryIsReady: Bool { library.articles.count == 2001 }

    var status: String {
        if let errorMessage { return "error|\(errorMessage)" }
        let observed = (1...3).filter { batch in
            let index = batch * 100 - 1
            return library.articles.indices.contains(index) && library.articles[index].title == "Synced \(batch * 100)"
        }.count
        let phase = libraryIsReady && !isApplying && !isVerifying && observed == completedBatches ? "ready" : "working"
        return "\(phase)|\(library.articles.count)|\(completedBatches)|\(applied)|\(verified)|\(overlappingBatches)|\(overlappingRecords)|\(observed)"
    }

    func scrollBegan() {
        if enabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                if self.isScrolling() {
                    self.beginBatch()
                } else {
                    self.errorMessage = "Sync batch did not start during scrolling"
                }
            }
        }
    }

    func scrollEnded() {
        isVerifying = true
        let pendingBatch = batchTask
        Task {
            await pendingBatch?.value
            do {
                verified = try await database.reader.read { db in
                    try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM articles WHERE title LIKE 'Synced %' AND length(content) = 8192 AND cloudKitSystemFields IS NOT NULL") ?? 0
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isVerifying = false
            notify_post("com.esoxjem.Luego.performance.sync-verified")
        }
    }

    private func beginBatch() {
        if isApplying || completedBatches >= batches.count {
            errorMessage = "Unexpected sync batch: applying=\(isApplying), completed=\(completedBatches), applied=\(applied)"
            return
        }
        let records = batches[completedBatches]
        overlappingBatches += 1
        isApplying = true
        batchTask = Task {
            let interval = signposter.beginInterval("SyncApplyBatch", id: signposter.makeSignpostID())
            do {
                for record in records {
                    let beganDuringScroll = isScrolling()
                    let articleRecord = try ArticleRecord(record: record)
                    try await store.saveRecord(articleRecord)
                    applied += 1
                    if beganDuringScroll && isScrolling() { overlappingRecords += 1 }
                }
                completedBatches += 1
            } catch {
                errorMessage = error.localizedDescription
            }
            signposter.endInterval("SyncApplyBatch", interval)
            isApplying = false
        }
    }
}

nonisolated enum ForegroundSyncFixture {
    static let initialBody = "initial " + String(repeating: "a", count: 8184)
    static let updatedBody = "updated " + String(repeating: "b", count: 8184)

    static func record(index: Int) -> ArticleRecord {
        ArticleRecord(
            id: String(format: "00000000-0000-0000-0001-%012d", index),
            url: URL(string: "https://fixture.invalid/sync/library/\(index)")!,
            title: "Library \(index)",
            content: initialBody,
            savedDate: Date(timeIntervalSince1970: 1_700_000_000 + Double(2001 - index)),
            wordCount: 1000
        )
    }

    @concurrent
    static func makeDatabase() async throws -> AppDatabase {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ForegroundSyncBenchmark", isDirectory: true)
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = try AppDatabase.make(at: directory.appendingPathComponent("fixture.sqlite"))
        try await database.writer.write { db in
            for index in 1...2000 { try record(index: index).insert(db) }
        }
        return database
    }
}

@MainActor
private final class OfflineSyncServices: SyncEngineManagerProtocol, SharingServiceProtocol {
    func performForegroundCatchUp() async {}
    func enqueueSave(for recordID: CKRecord.ID) {}
    func refresh(mode: SyncRefreshMode) async throws -> Int { 0 }
    func syncSharedArticles() async throws -> [Article] { [] }
}
