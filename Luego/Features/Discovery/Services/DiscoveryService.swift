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

@MainActor
protocol DiscoveryServiceProtocol: Sendable {
    func cachedPosts() async -> [DiscoveryPost]?
    func refreshPosts(force: Bool) async throws -> [DiscoveryPost]?
    func fetchArticle(for post: DiscoveryPost) async throws -> EphemeralArticle
}

@MainActor
final class DiscoveryService: DiscoveryServiceProtocol {
    private let postSource: DiscoveryPostSourceProtocol
    private let contentDataSource: ContentDataSourceProtocol
    private let postCache: DiscoveryPostCacheProtocol
    private let maxAge: TimeInterval
    private let now: @MainActor () -> Date
    private let articleTimeout: TimeInterval = 10
    private var inFlightRefresh: Task<[DiscoveryPost], Error>?

    init(
        postSource: DiscoveryPostSourceProtocol,
        contentDataSource: ContentDataSourceProtocol,
        postCache: DiscoveryPostCacheProtocol,
        maxAge: TimeInterval = 60 * 60,
        now: @escaping @MainActor () -> Date = { .now }
    ) {
        self.postSource = postSource
        self.contentDataSource = contentDataSource
        self.postCache = postCache
        self.maxAge = maxAge
        self.now = now
    }

    func cachedPosts() async -> [DiscoveryPost]? {
        await postCache.load()?.posts
    }

    func refreshPosts(force: Bool) async throws -> [DiscoveryPost]? {
        if !force, let fetchedAt = await postCache.load()?.fetchedAt, now().timeIntervalSince(fetchedAt) < maxAge {
            return nil
        }
        if let inFlightRefresh {
            return try await inFlightRefresh.value
        }
        let refresh = Task {
            defer { inFlightRefresh = nil }
            let posts = try await postSource.fetchPosts()
            await postCache.save(DiscoveryPostSnapshot(posts: posts, fetchedAt: now()))
            return posts
        }
        inFlightRefresh = refresh
        return try await refresh.value
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
