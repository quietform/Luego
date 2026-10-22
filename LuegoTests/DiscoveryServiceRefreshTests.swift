import Foundation
import Testing

@MainActor
struct DiscoveryServiceRefreshTests {
    private let cache = InMemoryDiscoveryPostCache()
    private let source = CountingPostSource()
    private let clock = TestClock()
    private let feedStore = InMemoryFeedStore()
    private let blogFeed = DiscoveryFeed(url: URL(string: "https://blog.luego.test/feed.xml")!)

    @Test
    func refreshedPostsAreAvailableFromTheCacheOnNextLaunch() async throws {
        feedStore.saved = [blogFeed]
        source.results = [.success([.first, .second])]
        clock.now = Date(timeIntervalSince1970: 1_000)

        let refreshed = try await makeService().refreshPosts(force: true)
        let cachedOnNextLaunch = await makeService().cachedPosts()

        #expect(refreshed == .posts([.first, .second]))
        #expect(cachedOnNextLaunch == [.first, .second])
        #expect(cache.snapshot?.fetchedAt == Date(timeIntervalSince1970: 1_000))
    }

    @Test(arguments: [(59, false), (61, true)])
    func unforcedRefreshFetchesOnlyOnceTheListIsAnHourOld(minutesSinceFetch: Int, fetches: Bool) async throws {
        feedStore.saved = [blogFeed]
        cache.snapshot = DiscoveryPostSnapshot(posts: [.first], fetchedAt: Date(timeIntervalSince1970: 0), feeds: [blogFeed])
        source.results = [.success([.second])]
        clock.now = Date(timeIntervalSince1970: TimeInterval(minutesSinceFetch * 60))

        let refreshed = try await makeService().refreshPosts(force: false)

        #expect(source.fetchCount == (fetches ? 1 : 0))
        #expect(refreshed == (fetches ? .posts([.second]) : .unchanged))
    }

    @Test
    func refreshAfterChangingFeedsDoesNotReuseTheEarlierFetch() async throws {
        feedStore.saved = [blogFeed]
        source.results = [.success([.first]), .success([.second])]
        source.suspendsFetches = true
        let service = makeService()
        var started = source.started.stream.makeAsyncIterator()
        let edited = [blogFeed, .kagiSmallWeb]

        let earlier = Task { try await service.refreshPosts(force: true) }
        _ = await started.next()
        feedStore.saved = edited
        let afterEditing = Task { try await service.refreshPosts(force: false) }
        await Task.yield()
        source.resumeFetch()
        _ = try await earlier.value

        #expect(try await afterEditing.value == .posts([.second]))
        #expect(source.requestedFeeds == [[blogFeed], edited])
        #expect(cache.snapshot?.feeds == edited)
    }

    @Test
    func everyFeedSwitchedOffReportsNoFeedsOnWithoutFetching() async throws {
        var switchedOff = blogFeed
        switchedOff.isEnabled = false
        feedStore.saved = [switchedOff]

        let refreshed = try await makeService().refreshPosts(force: true)

        #expect(refreshed == .noFeedsOn)
        #expect(source.fetchCount == 0)
    }

    @Test
    func overlappingRefreshesShareOneFetch() async throws {
        feedStore.saved = [blogFeed]
        source.results = [.success([.first])]
        source.suspendsFetches = true
        let service = makeService()
        var started = source.started.stream.makeAsyncIterator()

        let pullToRefresh = Task { try await service.refreshPosts(force: true) }
        _ = await started.next()
        let foregroundRefresh = Task { try await service.refreshPosts(force: true) }
        await Task.yield()
        source.resumeFetch()

        #expect(try await pullToRefresh.value == .posts([.first]))
        #expect(try await foregroundRefresh.value == .posts([.first]))
        #expect(source.fetchCount == 1)
    }

    @Test
    func addingABlogSavesItsFeed() async throws {
        source.feedsByPage[URL(string: "https://blog.luego.test")!] = blogFeed

        let added = try await makeService().addFeed(from: " blog.luego.test ")

        #expect(added == blogFeed)
        #expect(feedStore.saved == [blogFeed])
    }

    @Test
    func addingAFeedAlreadyInTheListIsRejected() async {
        source.feedsByPage[URL(string: "https://blog.luego.test")!] = blogFeed
        feedStore.saved = [blogFeed]

        await #expect(throws: DiscoveryFeedError.alreadyAdded) {
            try await makeService().addFeed(from: "https://blog.luego.test")
        }
        #expect(feedStore.saved == [blogFeed])
    }

    @Test
    func refreshIncludesYourFeeds() async throws {
        feedStore.saved = [blogFeed]
        source.results = [.success([.first])]

        _ = try await makeService().refreshPosts(force: true)

        #expect(source.requestedFeeds == [[blogFeed]])
    }

    @Test
    func changingYourFeedsMakesARecentListStale() async throws {
        cache.snapshot = DiscoveryPostSnapshot(posts: [.first], fetchedAt: clock.now, feeds: [])
        feedStore.saved = [blogFeed]
        source.results = [.success([.second])]

        let refreshed = try await makeService().refreshPosts(force: false)

        #expect(refreshed == .posts([.second]))
        #expect(cache.snapshot?.feeds == [blogFeed])
    }

    @Test
    func removingAFeedTakesItOutOfYourList() {
        let other = DiscoveryFeed(url: URL(string: "https://other.luego.test/feed")!)
        feedStore.saved = [blogFeed, other]
        let service = makeService()

        service.removeFeed(blogFeed)

        #expect(service.feeds() == [other])
    }

    @Test
    func addingAFeedThatIsSwitchedOffIsRejected() async {
        var switchedOff = blogFeed
        switchedOff.isEnabled = false
        feedStore.saved = [switchedOff]
        source.feedsByPage[URL(string: "https://blog.luego.test")!] = blogFeed

        await #expect(throws: DiscoveryFeedError.alreadyAdded) {
            try await makeService().addFeed(from: "blog.luego.test")
        }
    }

    @Test
    func kagiSmallWebCanBeAddedBack() throws {
        feedStore.saved = [blogFeed]

        try makeService().addFeed(.kagiSmallWeb)

        #expect(feedStore.saved == [blogFeed, .kagiSmallWeb])
    }

    @Test
    func everyFeedEditIsAnnounced() async throws {
        feedStore.saved = [blogFeed]
        let service = makeService()
        var changes = service.feedChanges().makeAsyncIterator()

        try service.addFeed(.kagiSmallWeb)
        service.setFeed(blogFeed, isEnabled: false)
        service.removeFeed(blogFeed)

        var announced = 0
        for _ in 1...3 where await changes.next() != nil {
            announced += 1
        }
        #expect(announced == 3)
    }

    @Test
    func switchingAFeedOffKeepsItInPlace() {
        feedStore.saved = [.kagiSmallWeb, blogFeed]
        var switchedOff = blogFeed
        switchedOff.isEnabled = false

        makeService().setFeed(blogFeed, isEnabled: false)

        #expect(feedStore.saved == [.kagiSmallWeb, switchedOff])
    }

    private func makeService() -> DiscoveryService {
        DiscoveryService(
            postSource: source,
            contentDataSource: TestContentDataSource(),
            postCache: cache,
            feedStore: feedStore,
            maxAge: 60 * 60,
            now: { [clock] in clock.now }
        )
    }
}

@MainActor
final class InMemoryDiscoveryPostCache: DiscoveryPostCacheProtocol {
    var snapshot: DiscoveryPostSnapshot?

    init(snapshot: DiscoveryPostSnapshot? = nil) {
        self.snapshot = snapshot
    }

    func load() async -> DiscoveryPostSnapshot? {
        snapshot
    }

    func save(_ snapshot: DiscoveryPostSnapshot) async {
        self.snapshot = snapshot
    }
}

@MainActor
private final class CountingPostSource: DiscoveryPostSourceProtocol {
    var results: [Result<[DiscoveryPost], Error>] = []
    private(set) var fetchCount = 0
    var feedsByPage: [URL: DiscoveryFeed] = [:]
    private(set) var requestedFeeds: [[DiscoveryFeed]] = []
    var suspendsFetches = false
    let started = AsyncStream<Void>.makeStream()
    private var suspension: CheckedContinuation<Void, Never>?

    func fetchPosts(from feeds: [DiscoveryFeed]) async throws -> [DiscoveryPost] {
        fetchCount += 1
        requestedFeeds.append(feeds)
        let result = results.isEmpty ? .failure(URLError(.resourceUnavailable)) : results.removeFirst()
        if suspendsFetches, fetchCount == 1 {
            await withCheckedContinuation { continuation in
                suspension = continuation
                started.continuation.yield(())
            }
        }
        return try result.get()
    }

    func resolveFeed(from url: URL) async throws -> DiscoveryFeed {
        guard let feed = feedsByPage[url] else { throw DiscoveryFeedError.noFeedFound }
        return feed
    }

    func resumeFetch() {
        suspension?.resume()
        suspension = nil
    }
}

@MainActor
final class InMemoryFeedStore: DiscoveryFeedStoreProtocol {
    var saved: [DiscoveryFeed]

    init(saved: [DiscoveryFeed] = []) {
        self.saved = saved
    }

    func feeds() -> [DiscoveryFeed] {
        saved
    }

    func save(_ feeds: [DiscoveryFeed]) {
        saved = feeds
    }
}

@MainActor
private final class TestClock {
    var now = Date(timeIntervalSince1970: 0)
}
