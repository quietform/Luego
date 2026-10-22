import Foundation
import Testing

@MainActor
struct DiscoveryListViewModelTests {
    @Test
    func loadingListsTheRiverPosts() async {
        let service = ListedDiscoveryService(results: [.success(.posts([.first, .second]))])
        let viewModel = DiscoveryListViewModel(discoveryService: service)

        await viewModel.loadPosts()

        #expect(viewModel.posts == [.first, .second])
        #expect(viewModel.errorMessage == nil)
        #expect(!viewModel.isLoading)
    }

    @Test
    func failedLoadExplainsWhyNothingIsListed() async {
        let service = ListedDiscoveryService(results: [.failure(SmallWebError.fetchFailed(URLError(.notConnectedToInternet)))])
        let viewModel = DiscoveryListViewModel(discoveryService: service)

        await viewModel.loadPosts()

        #expect(viewModel.posts.isEmpty)
        #expect(viewModel.errorMessage == "Could not load the article list")
        #expect(!viewModel.isLoading)
    }

    @Test
    func failedRefreshKeepsThePostsAlreadyListed() async {
        let service = ListedDiscoveryService(results: [.success(.posts([.first])), .failure(URLError(.notConnectedToInternet))])
        let viewModel = DiscoveryListViewModel(discoveryService: service)

        await viewModel.loadPosts()
        await viewModel.loadPosts()

        #expect(viewModel.posts == [.first])
    }

    @Test
    func savedPostsAppearBeforeTheRefreshFinishes() async {
        let service = ListedDiscoveryService(results: [.success(.posts([.second]))])
        service.cached = [.first]
        service.suspendsFetches = true
        let viewModel = DiscoveryListViewModel(discoveryService: service)
        var started = service.started.stream.makeAsyncIterator()

        let load = Task { await viewModel.loadPosts() }
        _ = await started.next()

        #expect(viewModel.posts == [.first])

        service.resumeFetch()
        await load.value
        #expect(viewModel.posts == [.second])
    }

    @Test
    func pullToRefreshFetchesEvenWhenTheListIsFresh() async {
        let service = ListedDiscoveryService(results: [.success(.unchanged), .success(.posts([.second]))])
        let viewModel = DiscoveryListViewModel(discoveryService: service)

        await viewModel.loadPosts()
        await viewModel.refresh()

        #expect(service.refreshes == [false, true])
        #expect(viewModel.posts == [.second])
    }

    @Test
    func returningToTheAppRefreshesAListAlreadyShown() async {
        let service = ListedDiscoveryService(results: [.success(.posts([.first])), .success(.posts([.second]))])
        let viewModel = DiscoveryListViewModel(discoveryService: service)

        await viewModel.loadPosts()
        await viewModel.refreshIfStale()

        #expect(service.refreshes == [false, false])
        #expect(viewModel.posts == [.second])
    }

    @Test
    func returningToTheAppLeavesDiscoveryAloneUntilItIsOpened() async {
        let service = ListedDiscoveryService(results: [.success(.posts([.first]))])
        let viewModel = DiscoveryListViewModel(discoveryService: service)

        await viewModel.refreshIfStale()

        #expect(service.refreshes.isEmpty)
        #expect(viewModel.posts.isEmpty)
    }

    @Test
    func switchingEveryFeedOffEmptiesTheList() async {
        let service = ListedDiscoveryService(results: [.success(.posts([.first])), .success(.noFeedsOn)])
        let viewModel = DiscoveryListViewModel(discoveryService: service)

        await viewModel.loadPosts()
        await viewModel.refreshIfStale()

        #expect(viewModel.posts.isEmpty)
        #expect(viewModel.hasNoFeedsOn)
    }

    @Test
    func switchingAFeedBackOnWhileOfflineShowsTheFetchError() async {
        let service = ListedDiscoveryService(results: [.success(.noFeedsOn), .failure(SmallWebError.fetchFailed(URLError(.notConnectedToInternet)))])
        let viewModel = DiscoveryListViewModel(discoveryService: service)

        await viewModel.loadPosts()
        await viewModel.refreshIfStale()

        #expect(!viewModel.hasNoFeedsOn)
        #expect(viewModel.errorMessage == "Could not load the article list")
    }

    @Test
    func switchingAFeedBackOnListsItsPosts() async {
        let service = ListedDiscoveryService(results: [.success(.noFeedsOn), .success(.posts([.second]))])
        let viewModel = DiscoveryListViewModel(discoveryService: service)

        await viewModel.loadPosts()
        await viewModel.refreshIfStale()

        #expect(viewModel.posts == [.second])
        #expect(!viewModel.hasNoFeedsOn)
    }

    @Test(.timeLimit(.minutes(1)))
    func changingYourFeedsRefreshesTheList() async {
        let service = ListedDiscoveryService(results: [.success(.posts([.first])), .success(.posts([.second]))])
        let viewModel = DiscoveryListViewModel(discoveryService: service)
        var started = service.started.stream.makeAsyncIterator()
        await viewModel.loadPosts()
        service.suspendsFetches = true

        viewModel.startObservingFeedChanges()
        service.feedChangeStream.continuation.yield(())
        _ = await started.next()

        #expect(service.refreshes == [false, false])
        service.resumeFetch(at: 1)
    }

    @Test(arguments: [false, true])
    func cancelledLoadPublishesNothing(failed: Bool) async {
        let service = ListedDiscoveryService(results: [failed ? .failure(URLError(.timedOut)) : .success(.posts([.first]))])
        service.suspendsFetches = true
        let viewModel = DiscoveryListViewModel(discoveryService: service)
        var started = service.started.stream.makeAsyncIterator()

        let load = Task { await viewModel.loadPosts() }
        _ = await started.next()
        load.cancel()
        service.resumeFetch()
        await load.value

        #expect(viewModel.posts.isEmpty)
        #expect(viewModel.errorMessage == nil)
        #expect(!viewModel.isLoading)
    }

    @Test
    func cancelledEarlierLoadLeavesTheCurrentLoadRunning() async {
        let service = ListedDiscoveryService(results: [.success(.posts([.first])), .success(.posts([.second]))])
        service.suspendsFetches = true
        let viewModel = DiscoveryListViewModel(discoveryService: service)
        var started = service.started.stream.makeAsyncIterator()

        let earlier = Task { await viewModel.loadPosts() }
        _ = await started.next()
        earlier.cancel()
        let current = Task { await viewModel.loadPosts() }
        _ = await started.next()
        service.resumeFetch(at: 0)
        await earlier.value

        #expect(viewModel.isLoading)

        service.resumeFetch(at: 1)
        await current.value
        #expect(viewModel.posts == [.second])
        #expect(!viewModel.isLoading)
    }
}

extension DiscoveryPost {
    static let first = DiscoveryPost(url: URL(string: "https://river.luego.test/first")!, title: "First", publishedDate: nil)
    static let second = DiscoveryPost(url: URL(string: "https://river.luego.test/second")!, title: "Second", publishedDate: nil)
}

@MainActor
final class ListedDiscoveryService: DiscoveryServiceProtocol {
    private var results: [Result<DiscoveryRefresh, Error>]
    var cached: [DiscoveryPost]?
    private(set) var refreshes: [Bool] = []
    var articleResult: Result<EphemeralArticle, Error> = .failure(URLError(.unsupportedURL))
    private(set) var requestedArticleURLs: [URL] = []
    var suspendsFetches = false
    let started = AsyncStream<Void>.makeStream()
    private var suspensions: [Int: CheckedContinuation<Void, Never>] = [:]
    private var fetchCount = 0

    init(results: [Result<DiscoveryRefresh, Error>] = []) {
        self.results = results
    }

    func cachedPosts() async -> [DiscoveryPost]? {
        cached
    }

    var savedFeeds: [DiscoveryFeed] = []
    var addFeedResult: Result<DiscoveryFeed, Error> = .failure(DiscoveryFeedError.invalidURL)
    private(set) var addedFeedTexts: [String] = []

    func feeds() -> [DiscoveryFeed] {
        savedFeeds
    }

    func addFeed(from text: String) async throws -> DiscoveryFeed {
        addedFeedTexts.append(text)
        await suspendIfNeeded()
        let feed = try addFeedResult.get()
        savedFeeds.append(feed)
        return feed
    }

    func removeFeed(_ feed: DiscoveryFeed) {
        savedFeeds.removeAll { $0 == feed }
    }

    let feedChangeStream = AsyncStream<Void>.makeStream()

    func feedChanges() -> AsyncStream<Void> {
        feedChangeStream.stream
    }

    func setFeed(_ feed: DiscoveryFeed, isEnabled: Bool) {
        savedFeeds = savedFeeds.map {
            var saved = $0
            if saved.id == feed.id { saved.isEnabled = isEnabled }
            return saved
        }
    }

    func addFeed(_ feed: DiscoveryFeed) throws {
        savedFeeds.append(feed)
    }

    func refreshPosts(force: Bool) async throws -> DiscoveryRefresh {
        refreshes.append(force)
        let result = results.removeFirst()
        await suspendIfNeeded()
        return try result.get()
    }

    private func suspendIfNeeded() async {
        let index = fetchCount
        fetchCount += 1
        guard suspendsFetches else { return }
        await withCheckedContinuation { continuation in
            suspensions[index] = continuation
            started.continuation.yield(())
        }
    }

    func resumeFetch(at index: Int = 0) {
        suspensions.removeValue(forKey: index)?.resume()
    }

    func fetchArticle(for post: DiscoveryPost) async throws -> EphemeralArticle {
        requestedArticleURLs.append(post.url)
        let result = articleResult
        await suspendIfNeeded()
        return try result.get()
    }
}
