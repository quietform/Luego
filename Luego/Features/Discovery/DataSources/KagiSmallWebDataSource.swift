import Foundation

@MainActor
protocol DiscoverySourceProtocol: Sendable {
    var sourceIdentifier: DiscoverySource { get }
    func fetchArticles(forceRefresh: Bool) async throws -> [SmallWebArticleEntry]
    func randomArticleEntry() async throws -> SmallWebArticleEntry
    func clearCache()
}

typealias SmallWebDataSourceProtocol = DiscoverySourceProtocol

enum SmallWebError: LocalizedError {
    case fetchFailed(Error)
    case parsingFailed
    case noArticlesAvailable

    var errorDescription: String? {
        switch self {
        case .fetchFailed:
            return "Could not load the article list"
        case .parsingFailed:
            return "Could not parse the article list"
        case .noArticlesAvailable:
            return "No articles available"
        }
    }
}

@MainActor
final class KagiSmallWebDataSource: DiscoverySourceProtocol {
    let sourceIdentifier: DiscoverySource = .kagiSmallWeb

    private let opmlDataSource: OPMLDataSource
    private let genericRSSDataSource: GenericRSSDataSource
    private let session: URLSession
    private let seenTracker: SeenItemTracker
    private let seenRiverTracker: SeenItemTracker
    private let opmlURL = URL(string: "https://kagi.com/smallweb/opml")!
    private let riverURL: URL
    private let cacheKey = "smallweb_articles_v2"
    private let cacheTimestampKey = "smallweb_cache_timestamp_v2"
    private let cacheDuration: TimeInterval = 24 * 60 * 60

    private var cacheGeneration = UUID()
    private var cachedArticles: [SmallWebArticleEntry] = []

    init(
        opmlDataSource: OPMLDataSource,
        genericRSSDataSource: GenericRSSDataSource,
        session: URLSession = .shared,
        riverURL: URL = URL(string: "https://kagi.com/api/v1/smallweb/feed/")!
    ) {
        self.opmlDataSource = opmlDataSource
        self.genericRSSDataSource = genericRSSDataSource
        self.session = session
        self.riverURL = riverURL
        self.seenTracker = SeenItemTracker(storageKey: "smallweb_shown_articles")
        self.seenRiverTracker = SeenItemTracker(storageKey: "smallweb_shown_river_posts")
    }

    func fetchArticles(forceRefresh: Bool = false) async throws -> [SmallWebArticleEntry] {
        if !forceRefresh && cachedArticles.isEmpty { await loadCachedArticles() }
        if !forceRefresh && !cachedArticles.isEmpty && isCacheValid() {
            return cachedArticles
        }

        let generation = cacheGeneration
        do {
            let (data, _) = try await session.data(from: opmlURL)
            let articles = await opmlDataSource.parse(data)

            guard !articles.isEmpty else {
                throw SmallWebError.parsingFailed
            }

            if generation == cacheGeneration {
                cacheGeneration = UUID()
                cachedArticles = articles
                await saveArticlesToCache(articles)
            }
            return articles
        } catch let error as SmallWebError {
            throw error
        } catch {
            throw SmallWebError.fetchFailed(error)
        }
    }

    func randomArticleEntry() async throws -> SmallWebArticleEntry {
        if let post = try? await randomRiverPost() {
            return post
        }
        return try await randomPostFromBlogList()
    }

    private func randomRiverPost() async throws -> SmallWebArticleEntry? {
        let (data, _) = try await session.data(from: riverURL)
        let posts = await genericRSSDataSource.parse(data)
        let unseenPosts = await seenRiverTracker.filterUnseen(posts) { $0.postURL.absoluteString }
        guard let post = unseenPosts.randomElement() else { return nil }
        await seenRiverTracker.markAsSeen(post.postURL.absoluteString)
        return SmallWebArticleEntry(title: post.title, articleUrl: post.postURL, htmlUrl: Self.siteURL(for: post.postURL))
    }

    private static func siteURL(for postURL: URL) -> URL? {
        guard let scheme = postURL.scheme, let host = postURL.host() else { return nil }
        return URL(string: "\(scheme)://\(host)/")
    }

    private func randomPostFromBlogList() async throws -> SmallWebArticleEntry {
        let articles = try await fetchArticles(forceRefresh: false)

        guard !articles.isEmpty else {
            throw SmallWebError.noArticlesAvailable
        }

        let unseenArticles = await seenTracker.filterUnseen(articles) { $0.articleUrl.absoluteString }
        let didReset = await seenTracker.resetIfNeeded(totalCount: articles.count, unseenCount: unseenArticles.count)

        let articlesToChooseFrom = didReset ? articles : (unseenArticles.isEmpty ? articles : unseenArticles)

        guard let selectedFeed = articlesToChooseFrom.randomElement() else {
            throw SmallWebError.noArticlesAvailable
        }

        let (data, _) = try await session.data(from: selectedFeed.articleUrl)
        let posts = await genericRSSDataSource.parse(data)
        guard let post = posts.randomElement() else {
            throw SmallWebError.noArticlesAvailable
        }

        await seenTracker.markAsSeen(selectedFeed.articleUrl.absoluteString)
        return SmallWebArticleEntry(title: post.title, articleUrl: post.postURL, htmlUrl: selectedFeed.htmlUrl)
    }

    private func isCacheValid() -> Bool {
        guard let timestamp = UserDefaults.standard.object(forKey: cacheTimestampKey) as? Date else {
            return false
        }
        return Date().timeIntervalSince(timestamp) < cacheDuration
    }

    private func loadCachedArticles() async {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return }
        let generation = cacheGeneration
        let entries = await Self.decodeCachedArticles(data)
        guard generation == cacheGeneration else { return }
        cachedArticles = entries
    }

    @concurrent
    static func decodeCachedArticles(_ data: Data) async -> [SmallWebArticleEntry] {
        guard let cached = try? JSONDecoder().decode([CachedArticle].self, from: data) else { return [] }
        return cached.compactMap { entry in
            guard let url = URL(string: entry.articleUrl) else { return nil }
            return SmallWebArticleEntry(title: entry.title, articleUrl: url, htmlUrl: entry.htmlUrl.flatMap(URL.init(string:)))
        }
    }

    private func saveArticlesToCache(_ articles: [SmallWebArticleEntry]) async {
        let generation = cacheGeneration
        let data = await Self.encodeCachedArticles(articles)
        guard let data, generation == cacheGeneration else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
        UserDefaults.standard.set(Date(), forKey: cacheTimestampKey)
    }

    @concurrent
    static func encodeCachedArticles(_ articles: [SmallWebArticleEntry]) async -> Data? {
        let cached = articles.map { entry in
            CachedArticle(title: entry.title, articleUrl: entry.articleUrl.absoluteString, htmlUrl: entry.htmlUrl?.absoluteString)
        }
        return try? JSONEncoder().encode(cached)
    }

    func clearCache() {
        cacheGeneration = UUID()
        cachedArticles = []
        seenTracker.clear()
        seenRiverTracker.clear()
        UserDefaults.standard.removeObject(forKey: cacheKey)
        UserDefaults.standard.removeObject(forKey: cacheTimestampKey)
    }
}

private nonisolated struct CachedArticle: Codable, Sendable {
    let title: String
    let articleUrl: String
    let htmlUrl: String?
}
