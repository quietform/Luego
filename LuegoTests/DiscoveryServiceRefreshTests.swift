import Foundation
import Testing

@MainActor
struct DiscoveryServiceRefreshTests {
    private let cache = InMemoryDiscoveryPostCache()
    private let source = CountingPostSource()
    private let clock = TestClock()

    @Test
    func refreshedPostsAreAvailableFromTheCacheOnNextLaunch() async throws {
        source.results = [.success([.first, .second])]
        clock.now = Date(timeIntervalSince1970: 1_000)

        let refreshed = try await makeService().refreshPosts(force: true)
        let cachedOnNextLaunch = await makeService().cachedPosts()

        #expect(refreshed == [.first, .second])
        #expect(cachedOnNextLaunch == [.first, .second])
        #expect(cache.snapshot?.fetchedAt == Date(timeIntervalSince1970: 1_000))
    }

    @Test(arguments: [(59, false), (61, true)])
    func unforcedRefreshFetchesOnlyOnceTheListIsAnHourOld(minutesSinceFetch: Int, fetches: Bool) async throws {
        cache.snapshot = DiscoveryPostSnapshot(posts: [.first], fetchedAt: Date(timeIntervalSince1970: 0))
        source.results = [.success([.second])]
        clock.now = Date(timeIntervalSince1970: TimeInterval(minutesSinceFetch * 60))

        let refreshed = try await makeService().refreshPosts(force: false)

        #expect(source.fetchCount == (fetches ? 1 : 0))
        #expect(refreshed == (fetches ? [.second] : nil))
    }

    @Test
    func overlappingRefreshesShareOneFetch() async throws {
        source.results = [.success([.first])]
        source.suspendsFetches = true
        let service = makeService()
        var started = source.started.stream.makeAsyncIterator()

        let pullToRefresh = Task { try await service.refreshPosts(force: true) }
        _ = await started.next()
        let foregroundRefresh = Task { try await service.refreshPosts(force: true) }
        await Task.yield()
        source.resumeFetch()

        #expect(try await pullToRefresh.value == [.first])
        #expect(try await foregroundRefresh.value == [.first])
        #expect(source.fetchCount == 1)
    }

    private func makeService() -> DiscoveryService {
        DiscoveryService(
            postSource: source,
            contentDataSource: TestContentDataSource(),
            postCache: cache,
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
    var suspendsFetches = false
    let started = AsyncStream<Void>.makeStream()
    private var suspension: CheckedContinuation<Void, Never>?

    func fetchPosts() async throws -> [DiscoveryPost] {
        fetchCount += 1
        let result = results.isEmpty ? .failure(URLError(.resourceUnavailable)) : results.removeFirst()
        if suspendsFetches, suspension == nil {
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

@MainActor
private final class TestClock {
    var now = Date(timeIntervalSince1970: 0)
}
