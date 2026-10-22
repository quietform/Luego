import Foundation
import Testing

@MainActor
@Suite(.serialized)
struct BlogrollDiscoveryTests {
    private static let unavailableFeed = (400, #"{"status":"error","code":"error.invalidArgument","details":[]}"#)
    private static let blogFeed = (200, """
        <rss version="2.0"><channel><title>Example blog</title><link>https://blogroll.luego.test/</link>
        <item><title>Individual article</title><link>https://blogroll.luego.test/posts/individual-article</link></item>
        </channel></rss>
        """)
    private static let homepage = (200, """
        <main class="entries-column"><div class="entries">
        <article class="entry entry-website" data-cat="personal" >
            <a class="entry-main" href="https://blogroll.luego.test/" target="_blank">
                <h1 class="entry-title">Example blog</h1>
                <p class="entry-description">A personal blog.</p>
            </a>
        </article>
        </div></main>
        """)

    @Test
    func unavailableBlogrollFallsBackToExpiredCachedBlogs() async throws {
        let routes = [
            "https://blogroll.org/feed": Self.unavailableFeed,
            "https://blogroll.luego.test/rss": Self.blogFeed
        ]
        try await withBlogroll(routes: routes, cachedAt: Date().addingTimeInterval(-2 * 24 * 60 * 60)) { source in
            let post = try await source.randomArticleEntry()

            #expect(post.articleUrl.absoluteString == "https://blogroll.luego.test/posts/individual-article")
            #expect(post.title == "Individual article")
            #expect(post.htmlUrl?.absoluteString == "https://blogroll.luego.test/")
        }
    }

    @Test
    func unavailableBlogrollWithoutCacheDiscoversFeedsFromHomepage() async throws {
        let routes = [
            "https://blogroll.org/feed": Self.unavailableFeed,
            "https://blogroll.org/": Self.homepage,
            "https://blogroll.luego.test/": (200, """
                <html><head><link rel="alternate" type="application/rss+xml" title="Feed" href="https://blogroll.luego.test/rss"></head></html>
                """),
            "https://blogroll.luego.test/rss": Self.blogFeed
        ]
        try await withBlogroll(routes: routes, cachedAt: nil) { source in
            let post = try await source.randomArticleEntry()

            #expect(post.articleUrl.absoluteString == "https://blogroll.luego.test/posts/individual-article")
            #expect(post.title == "Individual article")
            #expect(post.htmlUrl?.absoluteString == "https://blogroll.luego.test/")
        }
    }

    @Test
    func homepageBlogWithRelativeFeedLinkResolvesAgainstItsSite() async throws {
        let routes = [
            "https://blogroll.org/feed": Self.unavailableFeed,
            "https://blogroll.org/": Self.homepage,
            "https://blogroll.luego.test/": (200, """
                <html><head><link type="application/atom+xml" href="/rss" rel="alternate"></head></html>
                """),
            "https://blogroll.luego.test/rss": Self.blogFeed
        ]
        try await withBlogroll(routes: routes, cachedAt: nil) { source in
            let post = try await source.randomArticleEntry()

            #expect(post.articleUrl.absoluteString == "https://blogroll.luego.test/posts/individual-article")
        }
    }

    @Test
    func blogrollErrorResponsesAreReportedAsLoadFailures() async throws {
        let routes = [
            "https://blogroll.org/feed": Self.unavailableFeed,
            "https://blogroll.org/": (500, "<html><body>Internal Server Error</body></html>")
        ]
        try await withBlogroll(routes: routes, cachedAt: nil) { source in
            do {
                _ = try await source.randomArticleEntry()
                Issue.record("An unavailable blogroll should fail")
            } catch let error as BlogrollError {
                guard case .fetchFailed = error else {
                    Issue.record("Expected fetchFailed, got \(error)")
                    return
                }
                #expect(error.errorDescription == "Could not load the blogroll")
            }
        }
    }

    private func withBlogroll(
        routes: [String: (Int, String)],
        cachedAt timestamp: Date?,
        operation: (BlogrollDataSource) async throws -> Void
    ) async throws {
        let defaults = UserDefaults.standard
        let keys = ["blogroll_articles_v1", "blogroll_cache_timestamp_v1", "blogroll_shown_blogs"]
        let previousValues = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, previousValues) {
                defaults.set(value, forKey: key)
            }
            BlogrollFeedFixture.routes = [:]
        }
        BlogrollFeedFixture.routes = routes
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BlogrollFeedFixture.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let encoded = try JSONSerialization.data(withJSONObject: [[
            "title": "Example blog",
            "feedUrl": "https://blogroll.luego.test/rss",
            "htmlUrl": "https://blogroll.luego.test/"
        ]])
        defaults.set(timestamp == nil ? nil : encoded, forKey: keys[0])
        defaults.set(timestamp, forKey: keys[1])
        defaults.removeObject(forKey: keys[2])

        let source = BlogrollDataSource(
            blogrollRSSDataSource: BlogrollRSSDataSource(),
            genericRSSDataSource: GenericRSSDataSource(),
            session: session
        )
        try await operation(source)
    }
}

private nonisolated final class BlogrollFeedFixture: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var routes: [String: (Int, String)] = [:]

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let (statusCode, body) = Self.routes[url.absoluteString] else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
