import Foundation
import Testing

@MainActor
struct SmallWebDiscoveryTests {
    @Test
    func riverPostsAreListedNewestFirst() async throws {
        try await withRiver(path: "river") { source, river in
            let posts = try await source.fetchPosts(from: [river])

            #expect(posts.map(\.url.absoluteString) == ["https://river.luego.test/posts/second", "https://river.luego.test/posts/first"])
            #expect(posts.map(\.title) == ["Second river post", "First river post"])
            #expect(posts.first?.domain == "river.luego.test")
            #expect(posts.first?.publishedDate == ISO8601DateFormatter().date(from: "2026-10-21T11:41:18Z"))
        }
    }

    @Test
    func listedPostOpensAsItsArticle() async throws {
        try await withRiver(path: "river-single") { source, river in
            let content = SmallWebTestContentSource()
            let service = DiscoveryService(postSource: source, contentDataSource: content, postCache: InMemoryDiscoveryPostCache(), feedStore: InMemoryFeedStore(saved: [river]))

            let post = try #require(try await service.refreshPosts(force: true).listedPosts.first)
            let article = try await service.fetchArticle(for: post)

            #expect(content.requestedURLs == [post.url])
            #expect(article.url == post.url)
            #expect(article.title == "First river post")
            #expect(article.content == "Article body")
            #expect(article.feedTitle == "river.luego.test")
        }
    }

    @Test
    func videoPostsAreLeftOutOfTheList() async throws {
        try await withRiver(path: "river-with-video") { source, river in
            let posts = try await source.fetchPosts(from: [river])

            #expect(posts.map(\.url.absoluteString) == ["https://river.luego.test/posts/first"])
        }
    }

    @Test
    func riverPostCarriesAPlainTextExcerpt() async throws {
        try await withRiver(path: "river-with-summary") { source, river in
            let post = try #require(try await source.fetchPosts(from: [river]).first)

            #expect(post.excerpt == "Hello & welcome, friends of the small web.")
        }
    }

    @Test
    func firstRealImageInTheSummaryBecomesTheThumbnail() async throws {
        try await withRiver(path: "river-with-images") { source, river in
            let posts = try await source.fetchPosts(from: [river])

            #expect(posts.map(\.thumbnailURL?.absoluteString) == ["https://river.luego.test/images/photo.jpg", nil])
        }
    }

    @Test
    func openedArticleKeepsTheFeedImageWhenThePageHasNone() async throws {
        try await withRiver(path: "river-with-images") { source, river in
            let service = DiscoveryService(postSource: source, contentDataSource: SmallWebTestContentSource(), postCache: InMemoryDiscoveryPostCache(), feedStore: InMemoryFeedStore(saved: [river]))

            let post = try #require(try await service.refreshPosts(force: true).listedPosts.first)
            let article = try await service.fetchArticle(for: post)

            #expect(article.thumbnailURL?.absoluteString == "https://river.luego.test/images/photo.jpg")
        }
    }

    @Test
    func untitledRiverEntriesAreLeftOutOfTheList() async throws {
        try await withRiver(path: "river-with-untitled") { source, river in
            let posts = try await source.fetchPosts(from: [river])

            #expect(posts.map(\.title) == ["First river post"])
        }
    }

    @Test(arguments: ["unavailable-river", "empty", "json"])
    func unusableRiverReportsWhyNothingIsListed(riverPath: String) async throws {
        try await withRiver(path: riverPath) { source, river in
            do {
                _ = try await source.fetchPosts(from: [river])
                Issue.record("An unusable River should not produce a list")
            } catch SmallWebError.fetchFailed {
                #expect(riverPath == "unavailable-river")
            } catch SmallWebError.noArticlesAvailable {
                #expect(riverPath != "unavailable-river")
            }
        }
    }

    @Test(arguments: [
        ("https://smallweb.luego.test/blog/feed.xml", "https://smallweb.luego.test/blog/feed.xml"),
        ("https://smallweb.luego.test/blog", "https://smallweb.luego.test/blog/feed.xml")
    ])
    func pastedBlogOrFeedResolvesToTheFeed(pasted: String, feed: String) async throws {
        try await withFeedPosts { feedPosts in
            let resolved = try await feedPosts.resolveFeedURL(from: URL(string: pasted)!)

            #expect(resolved.absoluteString == feed)
        }
    }

    @Test(arguments: ["feed", "feed.xml", "rss", "rss.xml", "atom.xml", "index.xml"])
    func pageWithoutAnAdvertisedFeedFindsItsFeedPath(path: String) async throws {
        try await withFeedPosts { feedPosts in
            let page = URL(string: "https://\(path.replacingOccurrences(of: ".", with: "-")).fallback.luego.test/")!
            let resolved = try await feedPosts.resolveFeedURL(from: page)

            #expect(resolved == page.appendingPathComponent(path))
        }
    }

    @Test
    func pastedArticleFindsTheFeedAdvertisedOnItsHomepage() async throws {
        try await withFeedPosts { feedPosts in
            let resolved = try await feedPosts.resolveFeedURL(from: URL(string: "https://homepage.luego.test/posts/article?ref=email#text")!)

            #expect(resolved.absoluteString == "https://homepage.luego.test/updates/latest.xml")
        }
    }

    @Test
    func pastedArticleFindsACommonFeedPathAtTheSiteRoot() async throws {
        try await withFeedPosts { feedPosts in
            let resolved = try await feedPosts.resolveFeedURL(from: URL(string: "https://feed-xml.fallback.luego.test/posts/article?ref=email#text")!)

            #expect(resolved.absoluteString == "https://feed-xml.fallback.luego.test/feed.xml")
        }
    }

    @Test
    func redirectedPageResolvesItsFeedLinkFromTheFinalAddress() async throws {
        try await withFeedPosts { feedPosts in
            let resolved = try await feedPosts.resolveFeedURL(from: URL(string: "https://redirect.luego.test/start")!)

            #expect(resolved.absoluteString == "https://redirect.luego.test/blog/updates.atom")
        }
    }

    @Test
    func redirectedPageFindsACommonFeedPathUnderTheFinalAddress() async throws {
        try await withFeedPosts { feedPosts in
            let resolved = try await feedPosts.resolveFeedURL(from: URL(string: "https://redirect.luego.test/moved")!)

            #expect(resolved.absoluteString == "https://redirect.luego.test/journal/feed")
        }
    }

    @Test
    func pageWithoutAFeedIsRejected() async throws {
        try await withFeedPosts { feedPosts in
            await #expect(throws: DiscoveryFeedError.noFeedFound) {
                try await feedPosts.resolveFeedURL(from: URL(string: "https://smallweb.luego.test/plain-page")!)
            }
        }
    }

    @Test
    func failedHTTPResponseIsNotAcceptedAsAFeed() async throws {
        try await withFeedPosts { feedPosts in
            await #expect(throws: DiscoveryFeedError.noFeedFound) {
                try await feedPosts.resolveFeedURL(from: URL(string: "https://http-error.luego.test/")!)
            }
        }
    }

    @Test
    func unreachableAddressSaysSo() async throws {
        try await withFeedPosts { feedPosts in
            await #expect(throws: DiscoveryFeedError.unreachable) {
                try await feedPosts.resolveFeedURL(from: URL(string: "https://smallweb.luego.test/offline")!)
            }
        }
    }

    private func withFeedPosts(operation: (FeedPostsDataSource) async throws -> Void) async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SmallWebFeedFixture.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        try await operation(FeedPostsDataSource(genericRSSDataSource: GenericRSSDataSource(), session: session))
    }

    private func withRiver(
        path: String,
        operation: (DiscoveryPostSource, DiscoveryFeed) async throws -> Void
    ) async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SmallWebFeedFixture.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let river = DiscoveryFeed(url: URL(string: "https://smallweb.luego.test/\(path)")!)
        let source = DiscoveryPostSource(
            feedPosts: FeedPostsDataSource(genericRSSDataSource: GenericRSSDataSource(), session: session),
            riverURL: river.url
        )
        try await operation(source, river)
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
        if request.url?.host() == "redirect.luego.test" {
            switch request.url?.path {
            case "/start", "/moved":
                let destination = URL(string: request.url?.path == "/start" ? "https://redirect.luego.test/blog/" : "https://redirect.luego.test/journal/")!
                let redirect = HTTPURLResponse(url: request.url!, statusCode: 301, httpVersion: nil, headerFields: ["Location": destination.absoluteString])!
                client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: destination), redirectResponse: redirect)
            case "/blog":
                respond(with: #"<html><head><link rel="alternate" type="application/atom+xml" href="updates.atom"></head></html>"#)
            case "/journal":
                respond(with: "<html><body>A journal without a feed link</body></html>")
            case "/journal/feed":
                respond(with: "<rss><channel><item><title>Journal post</title><link>https://redirect.luego.test/journal/post</link></item></channel></rss>")
            case "/blog/updates.atom":
                respond(with: "<feed><entry><title>Blog post</title><link href=\"https://redirect.luego.test/blog/post\" /></entry></feed>")
            default:
                client?.urlProtocol(self, didFailWithError: URLError(.fileDoesNotExist))
            }
            return
        }
        if request.url?.host() == "http-error.luego.test" {
            if request.url?.path == "/" {
                respond(with: "<html><body>A blog</body></html>")
            } else {
                respond(with: "<rss><channel><item><title>Unavailable</title><link>https://http-error.luego.test/post</link></item></channel></rss>", statusCode: 404)
            }
            return
        }
        if request.url?.host() == "homepage.luego.test" {
            switch request.url?.path {
            case "/":
                respond(with: #"<html><head><link rel="alternate" type="application/atom+xml" href="/updates/latest.xml"></head></html>"#)
            case "/updates/latest.xml":
                respond(with: "<feed><entry><title>Blog post</title><link href=\"https://homepage.luego.test/posts/article\" /></entry></feed>")
            case "/posts/article":
                respond(with: "<html><body>An article without a feed link</body></html>")
            default:
                client?.urlProtocol(self, didFailWithError: URLError(.fileDoesNotExist))
            }
            return
        }
        if let url = request.url, url.host()?.hasSuffix(".fallback.luego.test") == true {
            let feedPath = ["feed", "feed.xml", "rss", "rss.xml", "atom.xml", "index.xml"].first {
                url.host() == "\($0.replacingOccurrences(of: ".", with: "-")).fallback.luego.test"
            }
            if url.path == "/" || url.path == "/posts/article" {
                respond(with: "<html><body>A blog without a feed link</body></html>")
            } else if url.path == "/\(feedPath ?? "")" {
                respond(with: "<rss><channel><item><title>Blog post</title><link>https://smallweb.luego.test/post</link></item></channel></rss>")
            } else {
                client?.urlProtocol(self, didFailWithError: URLError(.fileDoesNotExist))
            }
            return
        }
        switch request.url?.path {
        case "/river":
            body = """
            <feed xmlns="http://www.w3.org/2005/Atom"><title type="text">Kagi Small Web</title>
            <entry><title type="text">First river post</title><id>https://river.luego.test/posts/first</id>
            <updated>2026-10-21T11:40:16+00:00</updated><link href="https://river.luego.test/posts/first" /></entry>
            <entry><title type="text">Second river post</title><id>https://river.luego.test/posts/second</id>
            <updated>2026-10-21T11:41:18+00:00</updated><link href="https://river.luego.test/posts/second" /></entry>
            </feed>
            """
        case "/river-with-video":
            body = """
            <feed xmlns="http://www.w3.org/2005/Atom"><title type="text">Kagi Small Web</title>
            <entry><title type="text">A video</title><link href="https://www.youtube.com/watch?v=abc" /></entry>
            <entry><title type="text">A short</title><link href="https://youtu.be/def" /></entry>
            <entry><title type="text">First river post</title><link href="https://river.luego.test/posts/first" /></entry>
            </feed>
            """
        case "/river-with-untitled":
            body = """
            <feed xmlns="http://www.w3.org/2005/Atom"><title type="text">Kagi Small Web</title>
            <entry><title type="text"> </title><link href="https://river.luego.test/posts/untitled" /></entry>
            <entry><link href="https://river.luego.test/posts/no-title" /></entry>
            <entry><title type="text">First river post</title><link href="https://river.luego.test/posts/first" /></entry>
            </feed>
            """
        case "/river-with-summary":
            body = """
            <feed xmlns="http://www.w3.org/2005/Atom"><title type="text">Kagi Small Web</title>
            <entry><title type="text">First river post</title><link href="https://river.luego.test/posts/first" />
            <summary type="html">&lt;p&gt;Hello &amp;amp; welcome,&lt;/p&gt;
              &lt;p&gt;friends&amp;#160;of the&lt;br /&gt;small web.&lt;/p&gt;</summary></entry>
            </feed>
            """
        case "/river-with-images":
            body = """
            <feed xmlns="http://www.w3.org/2005/Atom"><title type="text">Kagi Small Web</title>
            <entry><title type="text">Pictured post</title><link href="https://river.luego.test/posts/pictured" />
            <summary type="html">&lt;img src="https://stats.luego.test/pixel.gif" width="1" height="1" /&gt;
              &lt;img src="data:image/gif;base64,R0lGOD" /&gt;
              &lt;p&gt;Look:&lt;/p&gt;&lt;img alt="Photo" src="https://river.luego.test/images/photo.jpg" width="640" /&gt;</summary></entry>
            <entry><title type="text">Plain post</title><link href="https://river.luego.test/posts/plain" />
            <summary type="html">&lt;p&gt;No pictures here.&lt;/p&gt;</summary></entry>
            </feed>
            """
        case "/river-single":
            body = """
            <feed xmlns="http://www.w3.org/2005/Atom"><title type="text">Kagi Small Web</title>
            <entry><title type="text">First river post</title><id>https://river.luego.test/posts/first</id>
            <updated>2026-10-21T11:40:16+00:00</updated><link href="https://river.luego.test/posts/first" /></entry>
            </feed>
            """
        case "/blog":
            body = """
            <html><head><title>A blog</title>
            <link rel="alternate" type="application/rss+xml" title="A blog" href="/blog/feed.xml">
            </head><body>Hello</body></html>
            """
        case "/blog/feed.xml":
            body = """
            <rss><channel><title>A blog</title>
            <item><title>Blog post</title><link>https://smallweb.luego.test/blog/post</link></item>
            </channel></rss>
            """
        case "/plain-page":
            body = "<html><head><title>No feed here</title></head><body>Hello</body></html>"
        case "/empty":
            body = "<rss><channel><title>Empty blog</title></channel></rss>"
        case "/json":
            body = #"{"message":"Not an article feed"}"#
        default:
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        respond(with: body)
    }

    private func respond(with body: String, statusCode: Int = 200) {
        let data = Data(body.utf8)
        let response = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: ["Content-Type": "application/atom+xml"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private extension DiscoveryRefresh {
    var listedPosts: [DiscoveryPost] {
        guard case .posts(let posts) = self else { return [] }
        return posts
    }
}
