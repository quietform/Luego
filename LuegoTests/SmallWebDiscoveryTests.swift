import Foundation
import Testing

@MainActor
@Suite(.serialized)
struct SmallWebDiscoveryTests {
    @Test(arguments: ["rss", "atom"])
    func discoveryParsesAPostFromTheSelectedFeed(format: String) async throws {
        try await withFeed(path: format) { source in
            let content = SmallWebTestContentSource()
            let service = DiscoveryService(kagiSmallWebDataSource: source, blogrollDataSource: source, contentDataSource: content)
            var announcedURL: URL?

            let article = try await service.fetchRandomArticle(from: .kagiSmallWeb) { announcedURL = $0 }

            let postURL = URL(string: "https://smallweb.luego.test/posts/individual-article")!
            #expect(content.requestedURLs == [postURL])
            #expect(announcedURL == postURL)
            #expect(article.url == postURL)
            #expect(article.content == "Article body")
        }
    }

    @Test
    func downloadedOPMLResolvesToAnIndividualPost() async throws {
        try await withFeed(path: "rss", useCachedList: false) { source in
            let post = try await source.randomArticleEntry()

            #expect(post.articleUrl.absoluteString == "https://smallweb.luego.test/posts/individual-article")
            #expect(post.title == "Individual article")
            #expect(post.htmlUrl?.absoluteString == "https://smallweb.luego.test/")
        }
    }

    @Test
    func riverPostIsDiscoveredWithoutResolvingABlogFeed() async throws {
        try await withFeed(path: "network-error", riverPath: "river") { source in
            let post = try await source.randomArticleEntry()

            #expect(["https://river.luego.test/posts/first", "https://river.luego.test/posts/second"].contains(post.articleUrl.absoluteString))
            #expect(["First river post", "Second river post"].contains(post.title))
            #expect(post.htmlUrl?.absoluteString == "https://river.luego.test/")
        }
    }

    @Test(arguments: ["empty", "json"])
    func unusableRiverFallsBackToTheBlogList(riverPath: String) async throws {
        try await withFeed(path: "rss", riverPath: riverPath) { source in
            let post = try await source.randomArticleEntry()

            #expect(post.articleUrl.absoluteString == "https://smallweb.luego.test/posts/individual-article")
        }
    }

    @Test
    func shownRiverPostsGiveWayToTheBlogList() async throws {
        try await withFeed(path: "rss", riverPath: "river-single") { source in
            let riverPost = try await source.randomArticleEntry()
            let blogPost = try await source.randomArticleEntry()

            #expect(riverPost.articleUrl.absoluteString == "https://river.luego.test/posts/first")
            #expect(blogPost.articleUrl.absoluteString == "https://smallweb.luego.test/posts/individual-article")
        }
    }

    @Test
    func clearingTheCacheMakesShownRiverPostsAvailableAgain() async throws {
        try await withFeed(path: "rss", riverPath: "river-single") { source in
            _ = try await source.randomArticleEntry()
            source.clearCache()
            let post = try await source.randomArticleEntry()

            #expect(post.articleUrl.absoluteString == "https://river.luego.test/posts/first")
        }
    }

    @Test(arguments: ["empty", "json", "network-error"])
    func unusableFeedNeverReachesArticleParsing(path: String) async throws {
        try await withFeed(path: path) { source in
            let content = SmallWebTestContentSource()
            let service = DiscoveryService(kagiSmallWebDataSource: source, blogrollDataSource: source, contentDataSource: content)
            var announcedURL: URL?

            do {
                _ = try await service.fetchRandomArticle(from: .kagiSmallWeb) { announcedURL = $0 }
                Issue.record("An unusable feed should fail before article parsing")
            } catch SmallWebError.noArticlesAvailable {
                #expect(path != "network-error")
            } catch {
                #expect(path == "network-error")
                #expect((error as? URLError)?.code == .cannotConnectToHost)
            }

            #expect(content.requestedURLs.isEmpty)
            #expect(announcedURL == nil)
            #expect(UserDefaults.standard.data(forKey: "smallweb_shown_articles") == nil)
        }
    }

    private func withFeed(
        path: String,
        useCachedList: Bool = true,
        riverPath: String = "unavailable-river",
        operation: (KagiSmallWebDataSource) async throws -> Void
    ) async throws {
        let defaults = UserDefaults.standard
        let keys = ["smallweb_articles_v2", "smallweb_cache_timestamp_v2", "smallweb_shown_articles", "smallweb_shown_river_posts"]
        let previousValues = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, previousValues) {
                defaults.set(value, forKey: key)
            }
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SmallWebFeedFixture.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let encoded = try JSONSerialization.data(withJSONObject: [[
            "title": "Example blog",
            "articleUrl": "https://smallweb.luego.test/\(path)",
            "htmlUrl": "https://smallweb.luego.test/"
        ]])
        defaults.set(useCachedList ? encoded : nil, forKey: keys[0])
        defaults.set(useCachedList ? Date() : nil, forKey: keys[1])
        defaults.removeObject(forKey: keys[2])
        defaults.removeObject(forKey: keys[3])

        let source = KagiSmallWebDataSource(
            opmlDataSource: OPMLDataSource(),
            genericRSSDataSource: GenericRSSDataSource(),
            session: session,
            riverURL: URL(string: "https://smallweb.luego.test/\(riverPath)")!
        )
        try await operation(source)
    }
}

@MainActor
private final class SmallWebTestContentSource: ContentDataSourceProtocol {
    var requestedURLs: [URL] = []

    func validateURL(_ url: URL) async throws -> URL { url }

    func fetchMetadata(for url: URL, timeout: TimeInterval?) async throws -> ArticleMetadata {
        ArticleMetadata(title: "Individual article")
    }

    func fetchContent(for url: URL, timeout: TimeInterval?, forceRefresh: Bool, skipCache: Bool) async throws -> ArticleContent {
        requestedURLs.append(url)
        return ArticleContent(title: "Individual article", content: "Article body")
    }
}

private nonisolated final class SmallWebFeedFixture: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body: String
        switch request.url?.path {
        case "/smallweb/opml":
            body = """
            <opml><body><outline title="Example blog" xmlUrl="https://smallweb.luego.test/rss" htmlUrl="https://smallweb.luego.test/"/></body></opml>
            """
        case "/atom":
            body = """
            <feed xmlns="http://www.w3.org/2005/Atom"><title>Example blog</title><entry><title>Individual article</title>
            <link rel="alternate" type="text/html" href="https://smallweb.luego.test/posts/individual-article"/>
            <link rel="self" type="application/atom+xml" href="https://smallweb.luego.test/posts/individual-article.atom"/>
            </entry></feed>
            """
        case "/river":
            body = """
            <feed xmlns="http://www.w3.org/2005/Atom"><title type="text">Kagi Small Web</title>
            <entry><title type="text">First river post</title><id>https://river.luego.test/posts/first</id>
            <updated>2026-10-21T11:40:16+00:00</updated><link href="https://river.luego.test/posts/first" /></entry>
            <entry><title type="text">Second river post</title><id>https://river.luego.test/posts/second</id>
            <updated>2026-10-21T11:41:18+00:00</updated><link href="https://river.luego.test/posts/second" /></entry>
            </feed>
            """
        case "/river-single":
            body = """
            <feed xmlns="http://www.w3.org/2005/Atom"><title type="text">Kagi Small Web</title>
            <entry><title type="text">First river post</title><id>https://river.luego.test/posts/first</id>
            <updated>2026-10-21T11:40:16+00:00</updated><link href="https://river.luego.test/posts/first" /></entry>
            </feed>
            """
        case "/rss":
            body = """
            <rss version="2.0"><channel><title>Example blog</title><link>https://smallweb.luego.test/</link>
            <item><title>Individual article</title><link>https://smallweb.luego.test/posts/individual-article</link></item>
            </channel></rss>
            """
        case "/empty":
            body = "<rss><channel><title>Empty blog</title></channel></rss>"
        case "/json":
            body = #"{"message":"Not an article feed"}"#
        default:
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let data = Data(body.utf8)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/rss+xml"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
