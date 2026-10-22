import Foundation

enum DiscoveryError: LocalizedError {
    case contentFetchFailed(Error)

    var errorDescription: String? {
        switch self {
        case .contentFetchFailed(let underlyingError):
            return "Could not load article content: \(underlyingError.localizedDescription)"
        }
    }
}

nonisolated enum DiscoveryRefresh: Equatable, Sendable {
    case posts([DiscoveryPost])
    case unchanged
    case noFeedsOn
}

@MainActor
protocol DiscoveryServiceProtocol: Sendable {
    func cachedPosts() async -> [DiscoveryPost]?
    func refreshPosts(force: Bool) async throws -> DiscoveryRefresh
    func feeds() -> [DiscoveryFeed]
    func addFeed(from text: String) async throws -> DiscoveryFeed
    func addFeed(_ feed: DiscoveryFeed) throws
    func removeFeed(_ feed: DiscoveryFeed)
    func setFeed(_ feed: DiscoveryFeed, isEnabled: Bool)
    func feedChanges() -> AsyncStream<Void>
    func fetchArticle(for post: DiscoveryPost) async throws -> EphemeralArticle
}

@MainActor
final class DiscoveryService: DiscoveryServiceProtocol {
    private let postSource: DiscoveryPostSourceProtocol
    private let contentDataSource: ContentDataSourceProtocol
    private let postCache: DiscoveryPostCacheProtocol
    private let feedStore: DiscoveryFeedStoreProtocol
    private let maxAge: TimeInterval
    private let now: @MainActor () -> Date
    private let articleTimeout: TimeInterval = 10
    private var inFlightRefresh: InFlightRefresh?
    private var feedChangeContinuations: [UUID: AsyncStream<Void>.Continuation] = [:]

    init(
        postSource: DiscoveryPostSourceProtocol,
        contentDataSource: ContentDataSourceProtocol,
        postCache: DiscoveryPostCacheProtocol,
        feedStore: DiscoveryFeedStoreProtocol,
        maxAge: TimeInterval = 60 * 60,
        now: @escaping @MainActor () -> Date = { .now }
    ) {
        self.postSource = postSource
        self.contentDataSource = contentDataSource
        self.postCache = postCache
        self.feedStore = feedStore
        self.maxAge = maxAge
        self.now = now
    }

    func cachedPosts() async -> [DiscoveryPost]? {
        await postCache.load()?.posts
    }

    func refreshPosts(force: Bool) async throws -> DiscoveryRefresh {
        if !force, let snapshot = await postCache.load(), isFresh(snapshot) {
            return .unchanged
        }
        let feeds = feedStore.feeds()
        guard feeds.contains(where: \.isEnabled) else { return .noFeedsOn }
        if let inFlightRefresh, inFlightRefresh.feeds == feeds {
            return .posts(try await inFlightRefresh.task.value)
        }
        let id = UUID()
        let refresh = Task {
            defer {
                if inFlightRefresh?.id == id { inFlightRefresh = nil }
            }
            let posts = try await postSource.fetchPosts(from: feeds)
            if feedStore.feeds() == feeds {
                await postCache.save(DiscoveryPostSnapshot(posts: posts, fetchedAt: now(), feeds: feeds))
            }
            return posts
        }
        inFlightRefresh = InFlightRefresh(id: id, feeds: feeds, task: refresh)
        return .posts(try await refresh.value)
    }

    private func isFresh(_ snapshot: DiscoveryPostSnapshot) -> Bool {
        now().timeIntervalSince(snapshot.fetchedAt) < maxAge && snapshot.feeds == feedStore.feeds()
    }

    func addFeed(from text: String) async throws -> DiscoveryFeed {
        let feed = try await postSource.resolveFeed(from: try webAddress(from: text))
        try addFeed(feed)
        return feed
    }

    func feeds() -> [DiscoveryFeed] {
        feedStore.feeds()
    }

    func removeFeed(_ feed: DiscoveryFeed) {
        saveFeeds(feedStore.feeds().filter { $0.id != feed.id })
    }

    func addFeed(_ feed: DiscoveryFeed) throws {
        let feeds = feedStore.feeds()
        guard !feeds.contains(where: { $0.id == feed.id }) else { throw DiscoveryFeedError.alreadyAdded }
        saveFeeds(feeds + [feed])
    }

    func setFeed(_ feed: DiscoveryFeed, isEnabled: Bool) {
        saveFeeds(feedStore.feeds().map { saved in
            guard saved.id == feed.id else { return saved }
            var updated = saved
            updated.isEnabled = isEnabled
            return updated
        })
    }

    func feedChanges() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        let id = UUID()
        feedChangeContinuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.feedChangeContinuations[id] = nil }
        }
        return stream
    }

    private func saveFeeds(_ feeds: [DiscoveryFeed]) {
        feedStore.save(feeds)
        for continuation in feedChangeContinuations.values {
            continuation.yield()
        }
    }

    private func webAddress(from text: String) throws -> URL {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: withScheme), url.scheme == "https" || url.scheme == "http", url.host() != nil else {
            throw DiscoveryFeedError.invalidURL
        }
        return url
    }

    func fetchArticle(for post: DiscoveryPost) async throws -> EphemeralArticle {
        do {
            let content = try await contentDataSource.fetchContent(
                for: post.url,
                timeout: articleTimeout,
                forceRefresh: false,
                skipCache: true
            )
            return EphemeralArticle(
                url: post.url,
                title: post.title,
                content: content.content,
                thumbnailURL: content.thumbnailURL ?? post.thumbnailURL,
                publishedDate: content.publishedDate,
                feedTitle: post.domain
            )
        } catch {
            throw DiscoveryError.contentFetchFailed(error)
        }
    }
}

private struct InFlightRefresh {
    let id: UUID
    let feeds: [DiscoveryFeed]
    let task: Task<[DiscoveryPost], Error>
}
