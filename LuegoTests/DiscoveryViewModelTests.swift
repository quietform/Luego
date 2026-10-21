import Foundation
import GRDB
import Testing

@MainActor
struct DiscoveryViewModelTests {
    @Test(arguments: [false, true])
    func cancelledFetchDoesNotPublishOrRetry(failed: Bool) async throws {
        let service = SuspendedDiscoveryService()
        let viewModel = try makeViewModel(service: service)
        var started = service.started.stream.makeAsyncIterator()
        let fetch = Task { await viewModel.fetchRandomArticle() }
        _ = await started.next()
        fetch.cancel()
        service.completeFetch(failed: failed)
        await fetch.value

        #expect(viewModel.ephemeralArticle == nil)
        #expect(viewModel.pendingArticleURL == nil)
        #expect(viewModel.errorMessage == nil)
        #expect(!viewModel.isLoading)
        #expect(service.fetchCount == 1)
    }

    @Test
    func cancelledPreviousFetchDoesNotClearCurrentLoadingState() async throws {
        let service = SuspendedDiscoveryService(requestLimit: 2)
        let viewModel = try makeViewModel(service: service)
        var started = service.started.stream.makeAsyncIterator()
        let first = Task { await viewModel.fetchRandomArticle() }
        _ = await started.next()
        first.cancel()
        let next = Task { await viewModel.fetchRandomArticle() }
        _ = await started.next()
        service.completeFetch(at: 0)
        await first.value

        #expect(viewModel.isLoading)
        #expect(viewModel.ephemeralArticle == nil)
        #expect(viewModel.errorMessage == nil)

        service.completeFetch(at: 1)
        await next.value
        #expect(viewModel.ephemeralArticle?.title == "Article 1")
        #expect(!viewModel.isLoading)
    }

    private func makeViewModel(service: SuspendedDiscoveryService) throws -> DiscoveryViewModel {
        let store = GRDBArticleStore(database: try AppDatabase(DatabaseQueue()))
        let articles = ArticleService(articleStore: store, contentDataSource: DiscoveryTestContentSource(), syncEngineManager: TestSyncEngine())
        return DiscoveryViewModel(discoveryService: service, articleService: articles, preferencesDataSource: DiscoveryTestPreferences())
    }
}

@MainActor
private final class SuspendedDiscoveryService: DiscoveryServiceProtocol {
    let started = AsyncStream<Void>.makeStream()
    private(set) var fetchCount = 0
    private let requestLimit: Int
    private var completions: [Int: CheckedContinuation<Void, Error>] = [:]

    init(requestLimit: Int = 1) { self.requestLimit = requestLimit }

    func fetchRandomArticle(from source: DiscoverySource, onArticleEntryFetched: @escaping @MainActor (URL) -> Void) async throws -> EphemeralArticle {
        let index = fetchCount
        fetchCount += 1
        guard index < requestLimit else { throw URLError(.badServerResponse) }
        try await withCheckedThrowingContinuation { continuation in
            completions[index] = continuation
            started.continuation.yield(())
        }
        let url = URL(string: "https://example.com/article-\(index)")!
        onArticleEntryFetched(url)
        return EphemeralArticle(url: url, title: "Article \(index)", content: "Body", thumbnailURL: nil, publishedDate: nil, feedTitle: "Feed")
    }

    func completeFetch(at index: Int = 0, failed: Bool = false) {
        if failed {
            completions.removeValue(forKey: index)?.resume(throwing: URLError(.badServerResponse))
        } else {
            completions.removeValue(forKey: index)?.resume()
        }
    }

    func prepareForFetch(source: DiscoverySource) -> DiscoverySource { source }
    func clearCache(for source: DiscoverySource) {}
    func clearAllCaches() {}
}

private struct DiscoveryTestPreferences: DiscoveryPreferencesDataSourceProtocol {
    func getSelectedSource() -> DiscoverySource { .kagiSmallWeb }
    func setSelectedSource(_ source: DiscoverySource) {}
}

private struct DiscoveryTestContentSource: ContentDataSourceProtocol {
    func validateURL(_ url: URL) async throws -> URL { url }
    func fetchMetadata(for url: URL, timeout: TimeInterval?) async throws -> ArticleMetadata { throw URLError(.unsupportedURL) }
    func fetchContent(for url: URL, timeout: TimeInterval?, forceRefresh: Bool, skipCache: Bool) async throws -> ArticleContent { throw URLError(.unsupportedURL) }
}
