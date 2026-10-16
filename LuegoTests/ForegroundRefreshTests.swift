import Foundation
import GRDB
import Testing

@MainActor
struct ForegroundRefreshTests {
    @Test
    func sharedArticleIsSavedWhileCloudKitCatchUpIsBlocked() async throws {
        let fixture = try SharedQueueFixture()
        defer { fixture.remove() }
        let queue = fixture.makeQueue()
        let url = URL(string: "https://example.com/shared")!
        try await queue.saveSharedURL(url)
        let store = GRDBArticleStore(database: try AppDatabase(DatabaseQueue()))
        let sync = TestSyncEngine()
        store.syncEngineManager = sync
        let cloudKitGate = AsyncStream<Void>.makeStream()
        var cloudKitStarted = false
        var cloudKitFinished = false
        sync.onForegroundCatchUp = {
            cloudKitStarted = true
            for await _ in cloudKitGate.stream {}
            cloudKitFinished = true
        }
        let articles = ArticleService(articleStore: store, contentDataSource: TestContentDataSource(), syncEngineManager: sync)
        let sharing = SharingService(articleService: articles, sharedStorage: queue)
        let viewModel = ArticleListViewModel(articleService: articles, sharingService: sharing, syncEngineManager: sync)
        let refresh = Task { await viewModel.refreshOnForeground() }

        let imported = await waitUntil {
            cloudKitStarted && (try? store.fetchArticle(url: url)) != nil
        }
        #expect(imported)
        #expect(!cloudKitFinished)
        #expect(try queue.getSharedURLs().isEmpty)
        #expect(sync.savedRecordIDs.count == 1)

        cloudKitGate.continuation.finish()
        await refresh.value
        #expect(cloudKitFinished)
        #expect(viewModel.errorMessage == nil)
    }

    @Test
    func overlappingForegroundEventsImportTheQueueOnceWhileCloudKitContinues() async throws {
        let fixture = try SharedQueueFixture()
        defer { fixture.remove() }
        let queue = fixture.makeQueue()
        let url = URL(string: "https://example.com/shared")!
        try await queue.saveSharedURL(url)
        let store = GRDBArticleStore(database: try AppDatabase(DatabaseQueue()))
        let sync = TestSyncEngine()
        var catchUpCount = 0
        sync.onForegroundCatchUp = { catchUpCount += 1 }
        let metadata = TestContentDataSource()
        let metadataGate = AsyncStream<Void>.makeStream()
        var metadataRequests = 0
        metadata.onFetchMetadata = { _ in
            metadataRequests += 1
            for await _ in metadataGate.stream {}
            return ArticleMetadata(title: "Shared article")
        }
        let articles = ArticleService(articleStore: store, contentDataSource: metadata, syncEngineManager: sync)
        let sharing = SharingService(articleService: articles, sharedStorage: queue)
        let viewModel = ArticleListViewModel(articleService: articles, sharingService: sharing, syncEngineManager: sync)
        let first = Task { await viewModel.refreshOnForeground() }
        let firstStarted = await waitUntil { metadataRequests == 1 }
        #expect(firstStarted)
        let second = Task { await viewModel.refreshOnForeground() }

        let bothCaughtUp = await waitUntil { catchUpCount == 2 }
        #expect(bothCaughtUp)
        #expect(metadataRequests == 1)
        #expect(try store.countArticles() == 0)

        metadataGate.continuation.finish()
        await first.value
        await second.value
        #expect(try store.countArticles() == 1)
        #expect(try queue.getSharedURLs().isEmpty)
    }

    @Test
    func anotherForegroundEventImportsURLsQueuedDuringAnEarlierImport() async throws {
        let fixture = try SharedQueueFixture()
        defer { fixture.remove() }
        let queue = fixture.makeQueue()
        let firstURL = URL(string: "https://example.com/first")!
        let laterURL = URL(string: "https://example.com/later")!
        try await queue.saveSharedURL(firstURL)
        let store = GRDBArticleStore(database: try AppDatabase(DatabaseQueue()))
        let sync = TestSyncEngine()
        let metadata = TestContentDataSource()
        let metadataGate = AsyncStream<Void>.makeStream()
        var metadataStarted = false
        metadata.onFetchMetadata = { _ in
            metadataStarted = true
            for await _ in metadataGate.stream {}
            return ArticleMetadata(title: "Shared article")
        }
        let articles = ArticleService(articleStore: store, contentDataSource: metadata, syncEngineManager: sync)
        let sharing = SharingService(articleService: articles, sharedStorage: queue)
        let viewModel = ArticleListViewModel(articleService: articles, sharingService: sharing, syncEngineManager: sync)
        let first = Task { await viewModel.refreshOnForeground() }
        let firstStarted = await waitUntil { metadataStarted }
        #expect(firstStarted)

        try await queue.saveSharedURL(laterURL)
        await viewModel.refreshOnForeground()
        metadataGate.continuation.finish()
        await first.value

        #expect(try store.fetchArticle(url: laterURL) != nil)
        #expect(try store.countArticles() == 2)
        #expect(try queue.getSharedURLs().isEmpty)
    }

    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !condition() {
            guard ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return true
    }
}
