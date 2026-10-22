import Foundation

@MainActor
protocol DiscoveryPostSourceProtocol: Sendable {
    func fetchPosts(from feeds: [DiscoveryFeed]) async throws -> [DiscoveryPost]
    func resolveFeed(from url: URL) async throws -> DiscoveryFeed
}

@MainActor
final class DiscoveryPostSource: DiscoveryPostSourceProtocol {
    private let feedPosts: FeedPostsDataSourceProtocol
    private let riverURL: URL
    private let postsPerFeed = 5

    init(
        feedPosts: FeedPostsDataSourceProtocol,
        riverURL: URL = DiscoveryFeed.kagiSmallWeb.url
    ) {
        self.feedPosts = feedPosts
        self.riverURL = riverURL
    }

    func fetchPosts(from feeds: [DiscoveryFeed]) async throws -> [DiscoveryPost] {
        let results = await postsByFeed(feeds.filter(\.isEnabled))
        let posts = results.flatMap { (try? $0.get()) ?? [] }
        if posts.isEmpty, let failure = results.lazy.compactMap(\.failure).first {
            throw failure
        }
        var listedURLs = Set<URL>()
        return newestFirst(posts).filter { listedURLs.insert($0.url).inserted }
    }

    func resolveFeed(from url: URL) async throws -> DiscoveryFeed {
        DiscoveryFeed(url: try await feedPosts.resolveFeedURL(from: url))
    }

    private func postsByFeed(_ feeds: [DiscoveryFeed]) async -> [Result<[DiscoveryPost], Error>] {
        await withTaskGroup(of: Result<[DiscoveryPost], Error>.self) { group in
            for feed in feeds {
                group.addTask { await self.posts(from: feed) }
            }
            var results: [Result<[DiscoveryPost], Error>] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
    }

    private func posts(from feed: DiscoveryFeed) async -> Result<[DiscoveryPost], Error> {
        do {
            let posts = try await feedPosts.posts(from: feed.url)
            return .success(feed.url == riverURL ? posts : Array(newestFirst(posts).prefix(postsPerFeed)))
        } catch {
            return .failure(error)
        }
    }

    private func newestFirst(_ posts: [DiscoveryPost]) -> [DiscoveryPost] {
        posts.sorted { ($0.publishedDate ?? .distantPast) > ($1.publishedDate ?? .distantPast) }
    }
}

private extension Result {
    var failure: Failure? {
        guard case .failure(let error) = self else { return nil }
        return error
    }
}
