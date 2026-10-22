import Foundation
import Testing

@MainActor
struct DiscoveryListViewModelTests {
    @Test
    func loadingListsTheRiverPosts() async {
        let service = ListedDiscoveryService(results: [.success([.first, .second])])
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
        let service = ListedDiscoveryService(results: [.success([.first]), .failure(URLError(.notConnectedToInternet))])
        let viewModel = DiscoveryListViewModel(discoveryService: service)

        await viewModel.loadPosts()
        await viewModel.loadPosts()

        #expect(viewModel.posts == [.first])
    }

    @Test(arguments: [false, true])
    func cancelledLoadPublishesNothing(failed: Bool) async {
        let service = ListedDiscoveryService(results: [failed ? .failure(URLError(.timedOut)) : .success([.first])])
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
        let service = ListedDiscoveryService(results: [.success([.first]), .success([.second])])
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
    private var results: [Result<[DiscoveryPost], Error>]
    var articleResult: Result<EphemeralArticle, Error> = .failure(URLError(.unsupportedURL))
    private(set) var requestedArticleURLs: [URL] = []
    var suspendsFetches = false
    let started = AsyncStream<Void>.makeStream()
    private var suspensions: [Int: CheckedContinuation<Void, Never>] = [:]
    private var fetchCount = 0

    init(results: [Result<[DiscoveryPost], Error>] = []) {
        self.results = results
    }

    func fetchPosts() async throws -> [DiscoveryPost] {
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
