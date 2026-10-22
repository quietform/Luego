import Foundation
import GRDB
import Testing

@MainActor
struct DiscoveryArticleViewModelTests {
    @Test
    func openingAPostLoadsItsArticle() async throws {
        let service = StubDiscoveryArticleService()
        service.articleResult = .success(.first)
        let (viewModel, _) = try makeViewModel(service: service)

        await viewModel.load()

        #expect(service.requestedArticleURLs == [DiscoveryPost.first.url])
        #expect(viewModel.article?.content == "First body")
        #expect(!viewModel.isSaved)
        #expect(viewModel.errorMessage == nil)
        #expect(!viewModel.isLoading)
    }

    @Test
    func failedOpenExplainsWhatWentWrong() async throws {
        let service = StubDiscoveryArticleService()
        service.articleResult = .failure(DiscoveryError.contentFetchFailed(URLError(.timedOut)))
        let (viewModel, _) = try makeViewModel(service: service)

        await viewModel.load()

        #expect(viewModel.article == nil)
        #expect(viewModel.errorMessage?.hasPrefix("Could not load article content") == true)
        #expect(!viewModel.isLoading)
    }

    @Test
    func tryingAgainAfterAFailureShowsTheArticle() async throws {
        let service = StubDiscoveryArticleService()
        service.articleResult = .failure(URLError(.timedOut))
        let (viewModel, _) = try makeViewModel(service: service)
        await viewModel.load()

        service.articleResult = .success(.first)
        await viewModel.load()

        #expect(viewModel.article?.content == "First body")
        #expect(viewModel.errorMessage == nil)
    }

    @Test(arguments: [false, true])
    func leavingWhileLoadingPublishesNothing(failed: Bool) async throws {
        let service = StubDiscoveryArticleService()
        service.articleResult = failed ? .failure(URLError(.timedOut)) : .success(.first)
        service.suspendsFetches = true
        let (viewModel, _) = try makeViewModel(service: service)
        var started = service.started.stream.makeAsyncIterator()

        let load = Task { await viewModel.load() }
        _ = await started.next()
        load.cancel()
        service.resumeFetch()
        await load.value

        #expect(viewModel.article == nil)
        #expect(viewModel.errorMessage == nil)
        #expect(!viewModel.isLoading)
    }

    @Test
    func previouslySavedPostOpensAsSaved() async throws {
        let service = StubDiscoveryArticleService()
        service.articleResult = .success(.first)
        let (viewModel, articles) = try makeViewModel(service: service)
        _ = try await articles.saveEphemeralArticle(.first)

        await viewModel.load()

        #expect(viewModel.isSaved)
    }

    @Test
    func savingAddsTheArticleToTheReadingList() async throws {
        let service = StubDiscoveryArticleService()
        service.articleResult = .success(.first)
        let (viewModel, articles) = try makeViewModel(service: service)
        await viewModel.load()

        await viewModel.save()

        #expect(viewModel.isSaved)
        #expect(try await articles.isArticleSaved(url: DiscoveryPost.first.url))
    }

    private func makeViewModel(service: StubDiscoveryArticleService, post: DiscoveryPost = .first) throws -> (DiscoveryArticleViewModel, ArticleService) {
        let store = GRDBArticleStore(database: try AppDatabase(DatabaseQueue()))
        let articles = ArticleService(articleStore: store, contentDataSource: UnusedContentSource(), syncEngineManager: TestSyncEngine())
        return (DiscoveryArticleViewModel(post: post, discoveryArticleService: service, articleService: articles), articles)
    }
}

extension EphemeralArticle {
    static let first = EphemeralArticle(
        url: DiscoveryPost.first.url,
        title: "First",
        content: "First body",
        thumbnailURL: nil,
        publishedDate: nil,
        feedTitle: "river.luego.test"
    )
}

private struct UnusedContentSource: ContentDataSourceProtocol {
    func validateURL(_ url: URL) async throws -> URL { url }
    func fetchMetadata(for url: URL, timeout: TimeInterval?) async throws -> ArticleMetadata { throw URLError(.unsupportedURL) }
    func fetchContent(for url: URL, timeout: TimeInterval?, forceRefresh: Bool, skipCache: Bool) async throws -> ArticleContent { throw URLError(.unsupportedURL) }
}

@MainActor
private final class StubDiscoveryArticleService: DiscoveryArticleServiceProtocol {
    var articleResult: Result<EphemeralArticle, Error> = .failure(URLError(.unsupportedURL))
    private(set) var requestedArticleURLs: [URL] = []
    var suspendsFetches = false
    let started = AsyncStream<Void>.makeStream()
    private var suspension: CheckedContinuation<Void, Never>?

    func fetchArticle(for post: DiscoveryPost) async throws -> EphemeralArticle {
        requestedArticleURLs.append(post.url)
        let result = articleResult
        if suspendsFetches {
            await withCheckedContinuation { continuation in
                suspension = continuation
                started.continuation.yield(())
            }
        }
        return try result.get()
    }

    func resumeFetch() {
        suspension?.resume()
        suspension = nil
    }
}
