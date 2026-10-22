import Foundation

enum SmallWebError: LocalizedError {
    case fetchFailed(Error)
    case noArticlesAvailable

    var errorDescription: String? {
        switch self {
        case .fetchFailed:
            return "Could not load the article list"
        case .noArticlesAvailable:
            return "No articles available"
        }
    }
}

@MainActor
protocol FeedPostsDataSourceProtocol: Sendable {
    func posts(from feedURL: URL) async throws -> [DiscoveryPost]
    func resolveFeedURL(from url: URL) async throws -> URL
}

@MainActor
final class FeedPostsDataSource: FeedPostsDataSourceProtocol {
    private let genericRSSDataSource: GenericRSSDataSource
    private let session: URLSession

    init(genericRSSDataSource: GenericRSSDataSource, session: URLSession = .shared) {
        self.genericRSSDataSource = genericRSSDataSource
        self.session = session
    }

    func posts(from feedURL: URL) async throws -> [DiscoveryPost] {
        let data: Data
        do {
            (data, _) = try await session.data(from: feedURL)
        } catch {
            throw SmallWebError.fetchFailed(error)
        }
        let posts = await parsePosts(data)
        guard !posts.isEmpty else { throw SmallWebError.noArticlesAvailable }
        return posts
    }

    func resolveFeedURL(from url: URL) async throws -> URL {
        guard let (data, response) = try? await session.data(from: url) else {
            throw DiscoveryFeedError.unreachable
        }
        let pageURL = response.url ?? url
        if await !parsePosts(data).isEmpty {
            return url
        }
        if let feedURL = await genericRSSDataSource.discoverFeedURL(in: data, baseURL: pageURL),
           await isUsableFeed(feedURL) {
            return feedURL
        }
        let homepageURL = URL(string: "/", relativeTo: pageURL)?.absoluteURL
        if let homepageURL,
           homepageURL != pageURL,
           let homepageData = try? await session.data(from: homepageURL).0,
           let feedURL = await genericRSSDataSource.discoverFeedURL(in: homepageData, baseURL: homepageURL),
           await isUsableFeed(feedURL) {
            return feedURL
        }
        let pages = homepageURL.map { $0 == pageURL ? [pageURL] : [pageURL, $0] } ?? [pageURL]
        if let feedURL = await commonFeedURL(under: pages) {
            return feedURL
        }
        throw DiscoveryFeedError.noFeedFound
    }

    private func commonFeedURL(under pages: [URL]) async -> URL? {
        let candidates = pages.flatMap { page in
            ["feed", "feed.xml", "rss", "rss.xml", "atom.xml", "index.xml"].map { page.appendingPathComponent($0) }
        }
        return await withTaskGroup(of: (Int, URL?).self) { group in
            for (index, url) in candidates.enumerated() {
                group.addTask { (index, await self.isUsableFeed(url) ? url : nil) }
            }
            var preferred: (index: Int, url: URL)?
            for await (index, url) in group {
                if let url, index < (preferred?.index ?? .max) {
                    preferred = (index, url)
                }
            }
            return preferred?.url
        }
    }

    private func isUsableFeed(_ url: URL) async -> Bool {
        let request = URLRequest(url: url, timeoutInterval: 5)
        guard let (data, response) = try? await session.data(for: request),
              let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else { return false }
        return await !parsePosts(data).isEmpty
    }

    private func parsePosts(_ data: Data) async -> [DiscoveryPost] {
        await genericRSSDataSource.parse(data)
            .filter { !Self.isVideoURL($0.postURL) }
            .compactMap { entry in
                entry.title.map {
                    DiscoveryPost(url: entry.postURL, title: $0, publishedDate: entry.publishedDate, excerpt: entry.excerpt, thumbnailURL: entry.imageURL)
                }
            }
    }

    private static func isVideoURL(_ url: URL) -> Bool {
        guard let host = url.host()?.lowercased() else { return false }
        return ["youtube.com", "www.youtube.com", "m.youtube.com", "youtu.be"].contains(host)
    }
}
