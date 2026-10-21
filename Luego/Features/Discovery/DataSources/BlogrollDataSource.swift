import Foundation

enum BlogrollError: LocalizedError {
    case fetchFailed(Error)
    case parsingFailed
    case noArticlesAvailable
    case blogFeedFetchFailed(Error)
    case noPostsInBlogFeed

    var errorDescription: String? {
        switch self {
        case .fetchFailed:
            return "Could not load the blogroll"
        case .parsingFailed:
            return "Could not parse the blogroll"
        case .noArticlesAvailable:
            return "No blogs available"
        case .blogFeedFetchFailed:
            return "Could not load the blog's feed"
        case .noPostsInBlogFeed:
            return "No posts found in this blog"
        }
    }
}

@MainActor
final class BlogrollDataSource: DiscoverySourceProtocol {
    let sourceIdentifier: DiscoverySource = .blogroll

    private let blogrollRSSDataSource: BlogrollRSSDataSource
    private let genericRSSDataSource: GenericRSSDataSource
    private let seenTracker: SeenItemTracker
    private let feedURL = URL(string: "https://blogroll.org/feed")!
    private let cacheKey = "blogroll_articles_v1"
    private let cacheTimestampKey = "blogroll_cache_timestamp_v1"
    private let cacheDuration: TimeInterval = 24 * 60 * 60
    private let maxRetries = 5

    private var cacheGeneration = UUID()
    private var cachedBlogs: [SmallWebArticleEntry] = []

    init(blogrollRSSDataSource: BlogrollRSSDataSource, genericRSSDataSource: GenericRSSDataSource) {
        self.blogrollRSSDataSource = blogrollRSSDataSource
        self.genericRSSDataSource = genericRSSDataSource
        self.seenTracker = SeenItemTracker(storageKey: "blogroll_shown_blogs")
    }

    func fetchArticles(forceRefresh: Bool = false) async throws -> [SmallWebArticleEntry] {
        if !forceRefresh && cachedBlogs.isEmpty { await loadCachedBlogs() }
        if !forceRefresh && !cachedBlogs.isEmpty && isCacheValid() {
            return cachedBlogs
        }

        let generation = cacheGeneration
        do {
            let (data, _) = try await URLSession.shared.data(from: feedURL)
            let blogs = await blogrollRSSDataSource.parse(data)

            guard !blogs.isEmpty else {
                throw BlogrollError.parsingFailed
            }

            if generation == cacheGeneration {
                cacheGeneration = UUID()
                cachedBlogs = blogs
                await saveBlogsToCache(blogs)
            }
            return blogs
        } catch let error as BlogrollError {
            throw error
        } catch {
            throw BlogrollError.fetchFailed(error)
        }
    }

    func randomArticleEntry() async throws -> SmallWebArticleEntry {
        var lastError: Error = BlogrollError.noArticlesAvailable

        for _ in 1...maxRetries {
            do {
                let blog = try await selectRandomBlog()
                let post = try await fetchRandomPostFromBlog(blog)
                await seenTracker.markAsSeen(blog.articleUrl.absoluteString)
                return post
            } catch {
                lastError = error
                continue
            }
        }

        throw lastError
    }

    func clearCache() {
        cacheGeneration = UUID()
        cachedBlogs = []
        seenTracker.clear()
        UserDefaults.standard.removeObject(forKey: cacheKey)
        UserDefaults.standard.removeObject(forKey: cacheTimestampKey)
    }

    private func selectRandomBlog() async throws -> SmallWebArticleEntry {
        let blogs = try await fetchArticles(forceRefresh: false)

        guard !blogs.isEmpty else {
            throw BlogrollError.noArticlesAvailable
        }

        let unseenBlogs = await seenTracker.filterUnseen(blogs) { $0.articleUrl.absoluteString }
        let didReset = await seenTracker.resetIfNeeded(totalCount: blogs.count, unseenCount: unseenBlogs.count)

        let blogsToChooseFrom = didReset ? blogs : (unseenBlogs.isEmpty ? blogs : unseenBlogs)

        guard let selectedBlog = blogsToChooseFrom.randomElement() else {
            throw BlogrollError.noArticlesAvailable
        }

        return selectedBlog
    }

    private func fetchRandomPostFromBlog(_ blog: SmallWebArticleEntry) async throws -> SmallWebArticleEntry {
        let feedData = try await fetchBlogFeed(blog.articleUrl)
        let posts = await genericRSSDataSource.parse(feedData)

        guard let randomPost = posts.randomElement() else {
            throw BlogrollError.noPostsInBlogFeed
        }

        return SmallWebArticleEntry(
            title: randomPost.title,
            articleUrl: randomPost.postURL,
            htmlUrl: blog.htmlUrl
        )
    }

    private func fetchBlogFeed(_ feedURL: URL) async throws -> Data {
        do {
            let (data, _) = try await URLSession.shared.data(from: feedURL)
            return data
        } catch {
            throw BlogrollError.blogFeedFetchFailed(error)
        }
    }

    private func isCacheValid() -> Bool {
        guard let timestamp = UserDefaults.standard.object(forKey: cacheTimestampKey) as? Date else {
            return false
        }
        return Date().timeIntervalSince(timestamp) < cacheDuration
    }

    private func loadCachedBlogs() async {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return }
        let generation = cacheGeneration
        let entries = await Self.decodeCachedBlogs(data)
        guard generation == cacheGeneration else { return }
        cachedBlogs = entries
    }

    @concurrent
    static func decodeCachedBlogs(_ data: Data) async -> [SmallWebArticleEntry] {
        guard let cached = try? JSONDecoder().decode([CachedBlogrollEntry].self, from: data) else { return [] }
        return cached.compactMap { entry in
            guard let url = URL(string: entry.feedUrl) else { return nil }
            return SmallWebArticleEntry(title: entry.title, articleUrl: url, htmlUrl: entry.htmlUrl.flatMap(URL.init(string:)))
        }
    }

    private func saveBlogsToCache(_ blogs: [SmallWebArticleEntry]) async {
        let generation = cacheGeneration
        let data = await Self.encodeCachedBlogs(blogs)
        guard let data, generation == cacheGeneration else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
        UserDefaults.standard.set(Date(), forKey: cacheTimestampKey)
    }

    @concurrent
    static func encodeCachedBlogs(_ blogs: [SmallWebArticleEntry]) async -> Data? {
        let cached = blogs.map { entry in
            CachedBlogrollEntry(title: entry.title, feedUrl: entry.articleUrl.absoluteString, htmlUrl: entry.htmlUrl?.absoluteString)
        }
        return try? JSONEncoder().encode(cached)
    }
}

private nonisolated struct CachedBlogrollEntry: Codable, Sendable {
    let title: String
    let feedUrl: String
    let htmlUrl: String?
}
