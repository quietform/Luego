import Foundation
import GRDB
import Testing

@MainActor
struct ContentDataSourceTests {
    private let url = URL(string: "https://example.com/article")!

    @Test(arguments: [false, true])
    func savedArticleIncludesPrecomputedWordCount(useLocalParser: Bool) async throws {
        let parser = TestParser()
        if useLocalParser {
            parser.result = ParserResult(success: true, content: "Local article body", metadata: ParserMetadata(title: "Local title", publishedDate: nil, excerpt: nil, siteName: nil, thumbnail: nil), error: nil)
        }
        let source = makeSource(parser: parser, api: TestArticleAPI(isAvailable: !useLocalParser))
        let store = GRDBArticleStore(database: try AppDatabase(DatabaseQueue()))
        let service = ArticleService(articleStore: store, contentDataSource: source, syncEngineManager: TestSyncEngine())

        let saved = try await service.addArticle(url: url, savedDate: Date()).article

        #expect(saved.wordCount == 3)
        #expect(try await store.fetchRecord(id: saved.id)?.wordCount == 3)
    }

    @Test
    func cacheReadReturnsCompletedContentInCancelledTask() async throws {
        let cache = SuspendedContentCache()
        let source = ContentDataSource(parserDataSource: TestParser(), parsedContentCache: cache, luegoAPIDataSource: TestArticleAPI(isAvailable: false), webPageDataSource: TestHTMLSource(), sdkManager: TestSDKStatus())
        let fetch = Task { try await source.fetchContent(for: url) }
        var events = cache.started.stream.makeAsyncIterator()
        _ = await events.next()
        fetch.cancel()
        cache.completeRead()

        #expect(try await fetch.value.content == "Late cached body")
    }

    @Test(arguments: [false, true])
    func newlySavedArticleHasAnExcerptBeforeOpeningTheReader(useLocalParser: Bool) async throws {
        let body = "Fresh article body"
        let parser = TestParser()
        if useLocalParser {
            parser.result = ParserResult(success: true, content: body, metadata: ParserMetadata(title: "Article", publishedDate: nil, excerpt: "An article description", siteName: nil, thumbnail: nil), error: nil)
        }
        let api = TestArticleAPI(content: body)
        let source = makeSource(parser: parser, api: api)
        let database = try AppDatabase(DatabaseQueue())
        let store = GRDBArticleStore(database: database)
        let service = ArticleService(articleStore: store, contentDataSource: source, syncEngineManager: TestSyncEngine())

        let result = try await service.addArticle(url: url, savedDate: Date())
        let reloaded = try #require(try await GRDBArticleStore(database: database).fetchArticle(id: result.article.id))

        #expect(reloaded.excerpt == body)
        #expect(reloaded.content == body)
        #expect(result.article.excerpt == body)
        #expect(parser.parseCount == 1)
        #expect(await api.fetchCount == (useLocalParser ? 0 : 1))
    }

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
        #expect(metadata.wordCount == (body?.isEmpty == false ? 3 : nil))
        #expect(metadata.content == (body?.isEmpty == false ? body : nil))

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
        #expect(metadata.content == (body.isEmpty ? nil : body))

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
    func failedHTMLFetchUsesNormalFallbackInCancelledTask(operation: String) async throws {
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
        try await task.value
        #expect(await api.fetchCount == 1)
        #expect(cache.get(for: url)?.content == (operation == "skip" ? nil : "API article body"))
    }

    @Test(arguments: ["content", "refresh", "skip", "metadata"])
    func completedParsingUsesNormalCachePolicyInCancelledTask(operation: String) async throws {
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
        try await task.value
        #expect(cache.get(for: url)?.content == (operation == "skip" ? nil : "Local body"))
        #expect(await api.fetchCount == 0)
    }

    @Test(arguments: ["content", "refresh", "skip", "metadata"], [false, true])
    func apiCompletionUsesNormalResultAndCachePolicyInCancelledTask(operation: String, networkError: Bool) async {
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
        switch await task.result {
        case .failure(let error):
            #expect(networkError)
            if let apiError = error as? LuegoAPIError, case .networkError(let underlying) = apiError {
                #expect((underlying as? URLError)?.code == .cancelled)
            } else {
                Issue.record("Expected the original API error, received \(error)")
            }
        case .success:
            #expect(!networkError)
        }
        #expect(cache.get(for: url)?.content == (networkError || operation == "skip" ? nil : "API article body"))
    }

    @Test(arguments: ["content", "refresh", "skip", "metadata"])
    func alreadyCancelledFetchUsesNormalCachePolicy(operation: String) async throws {
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
        try await task.value
        let fetchesFreshContent = operation != "content"
        let updatesCache = operation == "refresh" || operation == "metadata"
        #expect(cache.get(for: url)?.content == (updatesCache ? "API article body" : "Old body"))
        #expect(parser.parseCount == (fetchesFreshContent ? 1 : 0))
        #expect(await api.fetchCount == (fetchesFreshContent ? 1 : 0))
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

@MainActor
private final class SuspendedContentCache: ParsedContentCacheDataSourceProtocol {
    let started = AsyncStream<Void>.makeStream()
    private var completion: CheckedContinuation<Void, Never>?

    func get(for url: URL) async -> ArticleContent? {
        await withCheckedContinuation { continuation in
            completion = continuation
            started.continuation.yield(())
        }
        return ArticleContent(title: "Cached", content: "Late cached body")
    }

    func completeRead() {
        completion?.resume()
        completion = nil
    }

    func save(_ content: ArticleContent, for url: URL) {}
    func clear() {}
    func remove(for url: URL) {}
}
