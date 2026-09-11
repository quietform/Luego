import Foundation
import Testing

@MainActor
struct ContentDataSourceTests {
    private let url = URL(string: "https://example.com/article")!

    @Test
    func localParsingWorksWhenAPIIsUnavailable() async throws {
        let parser = TestParser()
        parser.result = ParserResult(success: true, content: "Local article body", metadata: ParserMetadata(title: "Local title", publishedDate: nil, excerpt: nil, siteName: nil, thumbnail: nil), error: nil)
        let source = makeSource(parser: parser, api: TestArticleAPI(isAvailable: false))

        #expect(try await source.fetchContent(for: url).content == "Local article body")
        #expect(try await source.fetchMetadata(for: url).title == "Local title")
    }

    @Test
    func failedLocalParsingFallsBackToAPI() async throws {
        let source = makeSource()

        #expect(try await source.fetchContent(for: url).content == "API article body")
        #expect(try await source.fetchMetadata(for: url).title == "API title")
    }

    @Test
    func cachedContentWorksWithoutNetwork() async throws {
        let cache = TestContentCache()
        cache.save(ArticleContent(title: "Cached", content: "Offline body"), for: url)
        let source = makeSource(cache: cache, api: TestArticleAPI(isAvailable: false))

        #expect(try await source.fetchContent(for: url).content == "Offline body")
    }

    @Test
    func forceRefreshReplacesCachedContent() async throws {
        let cache = TestContentCache()
        cache.save(ArticleContent(title: "Cached", content: "Old body"), for: url)
        let source = makeSource(cache: cache)

        let result = try await source.fetchContent(for: url, timeout: nil, forceRefresh: true)

        #expect(result.content == "API article body")
        #expect(cache.get(for: url)?.content == "API article body")
    }

    @Test
    func discoveryFetchLeavesCachedContentUntouched() async throws {
        let cache = TestContentCache()
        cache.save(ArticleContent(title: "Cached", content: "Old body"), for: url)
        let source = makeSource(cache: cache)

        let result = try await source.fetchContent(for: url, timeout: nil, forceRefresh: false, skipCache: true)

        #expect(result.content == "API article body")
        #expect(cache.get(for: url)?.content == "Old body")
    }

    private func makeSource(parser: TestParser = TestParser(), cache: TestContentCache = TestContentCache(), api: TestArticleAPI = TestArticleAPI()) -> ContentDataSource {
        ContentDataSource(parserDataSource: parser, parsedContentCache: cache, luegoAPIDataSource: api, webPageDataSource: TestHTMLSource(), sdkManager: TestSDKStatus())
    }
}

@MainActor
private final class TestParser: LuegoParserDataSourceProtocol {
    let isReady = true
    var result: ParserResult?
    func parse(html: String, url: URL) async -> ParserResult? { result }
}

@MainActor
private final class TestContentCache: ParsedContentCacheDataSourceProtocol {
    private var contents: [URL: ArticleContent] = [:]
    func get(for url: URL) -> ArticleContent? { contents[url] }
    func save(_ content: ArticleContent, for url: URL) { contents[url] = content }
    func clear() { contents.removeAll() }
    func remove(for url: URL) { contents.removeValue(forKey: url) }
}

private struct TestArticleAPI: LuegoAPIDataSourceProtocol {
    var isAvailable = true
    func fetchArticle(for url: URL) async throws -> LuegoAPIResponse {
        guard isAvailable else { throw URLError(.notConnectedToInternet) }
        return LuegoAPIResponse(content: "API article body", metadata: LuegoAPIMetadata(title: "API title", author: nil, publishedDate: nil, estimatedReadTimeMinutes: nil, wordCount: 3, sourceUrl: url.absoluteString, domain: "example.com", thumbnail: nil))
    }
}

@MainActor
private final class TestHTMLSource: WebPageDataSourceProtocol {
    func validateURL(_ url: URL) async throws -> URL { url }
    func fetchHTML(from url: URL, timeout: TimeInterval?) async throws -> String { "<article>Article</article>" }
}

private struct TestSDKStatus: LuegoSDKManagerProtocol {
    func ensureSDKReady() async {}
    func checkForUpdates() async -> SDKUpdateResult { .failed(LuegoSDKError.networkUnavailable) }
    func isSDKAvailable() -> Bool { true }
    func loadBundles() -> [String: String]? { nil }
    func loadRules() -> Data? { nil }
    func getVersionInfo() -> SDKVersionInfo? { nil }
}
