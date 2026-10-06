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

    @Test(arguments: [nil, "", "Local article body"] as [String?])
    func localMetadataCachesUsableContent(body: String?) async throws {
        let parser = TestParser()
        parser.result = ParserResult(success: true, content: body, metadata: ParserMetadata(title: "Local title", publishedDate: "2026-10-06T10:00:00Z", excerpt: "Local excerpt", siteName: nil, thumbnail: "https://example.com/image.jpg"), error: nil)
        let cache = TestContentCache()
        let source = makeSource(parser: parser, cache: cache, api: TestArticleAPI(isAvailable: false))

        let metadata = try await source.fetchMetadata(for: url)

        #expect(metadata.title == "Local title")
        #expect(metadata.description == "Local excerpt")
        #expect(metadata.wordCount == nil)

        if let body, !body.isEmpty {
            let content = try await source.fetchContent(for: url)
            #expect(content.content == body)
            #expect(content.title == metadata.title)
            #expect(content.description == metadata.description)
            #expect(content.thumbnailURL == metadata.thumbnailURL)
            #expect(content.publishedDate == metadata.publishedDate)
            #expect(content.wordCount == 3)
            #expect(parser.parseCount == 1)
        } else {
            #expect(cache.get(for: url) == nil)
        }
    }

    @Test
    func failedLocalParsingFallsBackToAPI() async throws {
        let source = makeSource()

        #expect(try await source.fetchContent(for: url).content == "API article body")
        #expect(try await source.fetchMetadata(for: url).title == "API title")
    }

    @Test(arguments: ["", "API article body"])
    func apiMetadataCachesUsableContent(body: String) async throws {
        let cache = TestContentCache()
        let api = TestArticleAPI(content: body)
        let source = makeSource(cache: cache, api: api)

        let metadata = try await source.fetchMetadata(for: url)

        #expect(metadata.title == "API title")
        #expect(metadata.wordCount == 3)

        if !body.isEmpty {
            let content = try await source.fetchContent(for: url)
            #expect(content.content == body)
            #expect(content.title == metadata.title)
            #expect(content.description == metadata.description)
            #expect(content.thumbnailURL == metadata.thumbnailURL)
            #expect(content.publishedDate == metadata.publishedDate)
            #expect(content.wordCount == metadata.wordCount)
            #expect(await api.fetchCount == 1)
        } else {
            #expect(cache.get(for: url) == nil)
        }
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

    @Test(arguments: ["content", "refresh", "skip", "metadata"])
    func canceledHTMLFetchDoesNotFallBackToAPI(operation: String) async {
        let html = TestHTMLSource()
        html.waitForCancellation = true
        let api = TestArticleAPI()
        let cache = TestContentCache()
        let source = makeSource(cache: cache, api: api, html: html)
        let task = Task {
            if operation == "metadata" {
                _ = try await source.fetchMetadata(for: url)
            } else {
                _ = try await source.fetchContent(for: url, timeout: nil, forceRefresh: operation == "refresh", skipCache: operation == "skip")
            }
        }
        for await _ in html.started.stream { break }
        task.cancel()
        let result = await task.result

        if case .failure(let error) = result {
            #expect(error is CancellationError)
        } else {
            Issue.record("Canceled HTML fetch returned a result")
        }
        #expect(await api.fetchCount == 0)
        #expect(cache.get(for: url) == nil)
    }

    @Test(arguments: ["content", "refresh", "skip", "metadata"])
    func canceledParsingDoesNotCacheResult(operation: String) async {
        let parser = TestParser()
        parser.waitForCompletion = true
        parser.result = ParserResult(success: true, content: "Local body", metadata: ParserMetadata(title: "Local", publishedDate: nil, excerpt: nil, siteName: nil, thumbnail: nil), error: nil)
        let api = TestArticleAPI()
        let cache = TestContentCache()
        let source = makeSource(parser: parser, cache: cache, api: api)
        let task = Task {
            if operation == "metadata" {
                _ = try await source.fetchMetadata(for: url)
            } else {
                _ = try await source.fetchContent(for: url, timeout: nil, forceRefresh: operation == "refresh", skipCache: operation == "skip")
            }
        }
        for await _ in parser.started.stream { break }
        task.cancel()
        parser.completeParsing()
        let result = await task.result

        if case .failure(let error) = result {
            #expect(error is CancellationError)
        } else {
            Issue.record("Canceled parsing returned a result")
        }
        #expect(cache.get(for: url) == nil)
        #expect(await api.fetchCount == 0)
    }

    @Test(arguments: ["content", "refresh", "skip", "metadata"], [false, true])
    func canceledAPIFetchDoesNotCacheResult(operation: String, networkError: Bool) async {
        let api = TestArticleAPI(waitForCompletion: true)
        let cache = TestContentCache()
        let source = makeSource(cache: cache, api: api)
        let task = Task {
            if operation == "metadata" {
                _ = try await source.fetchMetadata(for: url)
            } else {
                _ = try await source.fetchContent(for: url, timeout: nil, forceRefresh: operation == "refresh", skipCache: operation == "skip")
            }
        }
        for await _ in api.started.stream { break }
        task.cancel()
        await api.completeFetch(networkError: networkError)
        let result = await task.result

        if case .failure(let error) = result {
            #expect(error is CancellationError)
        } else {
            Issue.record("Canceled API fetch returned a result")
        }
        #expect(cache.get(for: url) == nil)
    }

    @Test(arguments: ["content", "refresh", "skip", "metadata"])
    func alreadyCanceledFetchLeavesCachedContentUntouched(operation: String) async {
        let cache = TestContentCache()
        cache.save(ArticleContent(title: "Cached", content: "Old body"), for: url)
        let parser = TestParser()
        let api = TestArticleAPI()
        let source = makeSource(parser: parser, cache: cache, api: api)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            if operation == "metadata" {
                _ = try await source.fetchMetadata(for: url)
            } else {
                _ = try await source.fetchContent(for: url, timeout: nil, forceRefresh: operation == "refresh", skipCache: operation == "skip")
            }
        }
        let result = await task.result

        if case .failure(let error) = result {
            #expect(error is CancellationError)
        } else {
            Issue.record("Already canceled fetch returned a result")
        }
        #expect(cache.get(for: url)?.content == "Old body")
        #expect(parser.parseCount == 0)
        #expect(await api.fetchCount == 0)
    }

    private func makeSource(parser: TestParser = TestParser(), cache: TestContentCache = TestContentCache(), api: TestArticleAPI = TestArticleAPI(), html: TestHTMLSource = TestHTMLSource()) -> ContentDataSource {
        ContentDataSource(parserDataSource: parser, parsedContentCache: cache, luegoAPIDataSource: api, webPageDataSource: html, sdkManager: TestSDKStatus())
    }
}

@MainActor
private final class TestParser: LuegoParserDataSourceProtocol {
    let isReady = true
    var result: ParserResult?
    private(set) var parseCount = 0
    var waitForCompletion = false
    let started = AsyncStream<Void>.makeStream()
    private var completion: CheckedContinuation<Void, Never>?

    func parse(html: String, url: URL) async -> ParserResult? {
        parseCount += 1
        if waitForCompletion {
            await withCheckedContinuation { continuation in
                completion = continuation
                started.continuation.yield(())
            }
        }
        return result
    }

    func completeParsing() {
        completion?.resume()
        completion = nil
    }
}

@MainActor
private final class TestContentCache: ParsedContentCacheDataSourceProtocol {
    private var contents: [URL: ArticleContent] = [:]
    func get(for url: URL) -> ArticleContent? { contents[url] }
    func save(_ content: ArticleContent, for url: URL) { contents[url] = content }
    func clear() { contents.removeAll() }
    func remove(for url: URL) { contents.removeValue(forKey: url) }
}

private actor TestArticleAPI: LuegoAPIDataSourceProtocol {
    private let isAvailable: Bool
    private let content: String
    private(set) var fetchCount = 0
    private let waitForCompletion: Bool
    nonisolated let started = AsyncStream<Void>.makeStream()
    private var completion: CheckedContinuation<Void, Error>?

    init(isAvailable: Bool = true, content: String = "API article body", waitForCompletion: Bool = false) {
        self.isAvailable = isAvailable
        self.content = content
        self.waitForCompletion = waitForCompletion
    }

    func completeFetch(networkError: Bool) {
        if networkError {
            completion?.resume(throwing: LuegoAPIError.networkError(URLError(.cancelled)))
        } else {
            completion?.resume()
        }
        completion = nil
    }

    func fetchArticle(for url: URL) async throws -> LuegoAPIResponse {
        fetchCount += 1
        if waitForCompletion {
            try await withCheckedThrowingContinuation { continuation in
                completion = continuation
                started.continuation.yield(())
            }
        }
        guard isAvailable else { throw URLError(.notConnectedToInternet) }
        return LuegoAPIResponse(content: content, metadata: LuegoAPIMetadata(title: "API title", author: nil, publishedDate: nil, estimatedReadTimeMinutes: nil, wordCount: 3, sourceUrl: url.absoluteString, domain: "example.com", thumbnail: nil))
    }
}

@MainActor
private final class TestHTMLSource: WebPageDataSourceProtocol {
    func validateURL(_ url: URL) async throws -> URL { url }
    var waitForCancellation = false
    let started = AsyncStream<Void>.makeStream()

    func fetchHTML(from url: URL, timeout: TimeInterval?) async throws -> String {
        started.continuation.yield(())
        if waitForCancellation {
            do {
                try await Task.sleep(for: .seconds(10))
            } catch {
                throw ArticleMetadataError.networkError(error)
            }
        }
        return "<article>Article</article>"
    }
}

private struct TestSDKStatus: LuegoSDKManagerProtocol {
    func ensureSDKReady() async {}
    func checkForUpdates() async -> SDKUpdateResult { .failed(LuegoSDKError.networkUnavailable) }
    func isSDKAvailable() -> Bool { true }
    func loadBundles() -> [String: String]? { nil }
    func loadRules() -> Data? { nil }
    func getVersionInfo() -> SDKVersionInfo? { nil }
}
