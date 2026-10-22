import Foundation
import Testing

@MainActor
struct SmallWebDiscoveryTests {
    @Test
    func riverPostsAreListedInFeedOrder() async throws {
        try await withRiver(path: "river") { source in
            let posts = try await source.fetchPosts()

            #expect(posts.map(\.url.absoluteString) == ["https://river.luego.test/posts/first", "https://river.luego.test/posts/second"])
            #expect(posts.map(\.title) == ["First river post", "Second river post"])
            #expect(posts.first?.domain == "river.luego.test")
            #expect(posts.first?.publishedDate == ISO8601DateFormatter().date(from: "2026-10-21T11:40:16Z"))
        }
    }

    @Test
    func listedPostOpensAsItsArticle() async throws {
        try await withRiver(path: "river-single") { source in
            let content = SmallWebTestContentSource()
            let service = DiscoveryService(postSource: source, contentDataSource: content)

            let post = try #require(try await service.fetchPosts().first)
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
        try await withRiver(path: "river-with-video") { source in
            let posts = try await source.fetchPosts()

            #expect(posts.map(\.url.absoluteString) == ["https://river.luego.test/posts/first"])
        }
    }

    @Test
    func riverPostCarriesAPlainTextExcerpt() async throws {
        try await withRiver(path: "river-with-summary") { source in
            let post = try #require(try await source.fetchPosts().first)

            #expect(post.excerpt == "Hello & welcome, friends of the small web.")
        }
    }

    @Test
    func firstRealImageInTheSummaryBecomesTheThumbnail() async throws {
        try await withRiver(path: "river-with-images") { source in
            let posts = try await source.fetchPosts()

            #expect(posts.map(\.thumbnailURL?.absoluteString) == ["https://river.luego.test/images/photo.jpg", nil])
        }
    }

    @Test
    func openedArticleKeepsTheFeedImageWhenThePageHasNone() async throws {
        try await withRiver(path: "river-with-images") { source in
            let service = DiscoveryService(postSource: source, contentDataSource: SmallWebTestContentSource())

            let post = try #require(try await service.fetchPosts().first)
            let article = try await service.fetchArticle(for: post)

            #expect(article.thumbnailURL?.absoluteString == "https://river.luego.test/images/photo.jpg")
        }
    }

    @Test
    func untitledRiverEntriesAreLeftOutOfTheList() async throws {
        try await withRiver(path: "river-with-untitled") { source in
            let posts = try await source.fetchPosts()

            #expect(posts.map(\.title) == ["First river post"])
        }
    }

    @Test(arguments: ["unavailable-river", "empty", "json"])
    func unusableRiverReportsWhyNothingIsListed(riverPath: String) async throws {
        try await withRiver(path: riverPath) { source in
            do {
                _ = try await source.fetchPosts()
                Issue.record("An unusable River should not produce a list")
            } catch SmallWebError.fetchFailed {
                #expect(riverPath == "unavailable-river")
            } catch SmallWebError.noArticlesAvailable {
                #expect(riverPath != "unavailable-river")
            }
        }
    }

    private func withRiver(
        path: String,
        operation: (KagiSmallWebDataSource) async throws -> Void
    ) async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SmallWebFeedFixture.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let source = KagiSmallWebDataSource(
            genericRSSDataSource: GenericRSSDataSource(),
            session: session,
            riverURL: URL(string: "https://smallweb.luego.test/\(path)")!
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
        case "/empty":
            body = "<rss><channel><title>Empty blog</title></channel></rss>"
        case "/json":
            body = #"{"message":"Not an article feed"}"#
        default:
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let data = Data(body.utf8)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/atom+xml"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
