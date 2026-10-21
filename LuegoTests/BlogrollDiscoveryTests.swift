import Foundation
import Testing

@MainActor
@Suite(.serialized)
struct BlogrollDiscoveryTests {
    @Test
    func unavailableBlogrollFallsBackToExpiredCachedBlogs() async throws {
        try await withBlogroll(cachedAt: Date().addingTimeInterval(-2 * 24 * 60 * 60)) { source in
            let post = try await source.randomArticleEntry()

            #expect(post.articleUrl.absoluteString == "https://blogroll.luego.test/posts/individual-article")
            #expect(post.title == "Individual article")
            #expect(post.htmlUrl?.absoluteString == "https://blogroll.luego.test/")
        }
    }

    private func withBlogroll(
        cachedAt timestamp: Date,
        operation: (BlogrollDataSource) async throws -> Void
    ) async throws {
        let defaults = UserDefaults.standard
        let keys = ["blogroll_articles_v1", "blogroll_cache_timestamp_v1", "blogroll_shown_blogs"]
        let previousValues = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, previousValues) {
                defaults.set(value, forKey: key)
            }
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BlogrollFeedFixture.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let encoded = try JSONSerialization.data(withJSONObject: [[
            "title": "Example blog",
            "feedUrl": "https://blogroll.luego.test/rss",
            "htmlUrl": "https://blogroll.luego.test/"
        ]])
        defaults.set(encoded, forKey: keys[0])
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
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let statusCode: Int
        let body: String
        switch (request.url?.host(), request.url?.path) {
        case ("blogroll.org", "/feed"):
            statusCode = 400
            body = #"{"status":"error","code":"error.invalidArgument","details":[]}"#
        case ("blogroll.luego.test", "/rss"):
            statusCode = 200
            body = """
            <rss version="2.0"><channel><title>Example blog</title><link>https://blogroll.luego.test/</link>
            <item><title>Individual article</title><link>https://blogroll.luego.test/posts/individual-article</link></item>
            </channel></rss>
            """
        default:
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
