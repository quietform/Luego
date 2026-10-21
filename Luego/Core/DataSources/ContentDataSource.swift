import Foundation

@MainActor
protocol ContentDataSourceProtocol: Sendable {
    func validateURL(_ url: URL) async throws -> URL
    func fetchMetadata(for url: URL, timeout: TimeInterval?) async throws -> ArticleMetadata
    func fetchContent(for url: URL, timeout: TimeInterval?, forceRefresh: Bool, skipCache: Bool) async throws -> ArticleContent
}

extension ContentDataSourceProtocol {
    func fetchMetadata(for url: URL) async throws -> ArticleMetadata {
        try await fetchMetadata(for: url, timeout: nil)
    }

    func fetchContent(for url: URL) async throws -> ArticleContent {
        try await fetchContent(for: url, timeout: nil, forceRefresh: false, skipCache: false)
    }

    func fetchContent(for url: URL, timeout: TimeInterval?) async throws -> ArticleContent {
        try await fetchContent(for: url, timeout: timeout, forceRefresh: false, skipCache: false)
    }

    func fetchContent(for url: URL, timeout: TimeInterval?, forceRefresh: Bool) async throws -> ArticleContent {
        try await fetchContent(for: url, timeout: timeout, forceRefresh: forceRefresh, skipCache: false)
    }
}

@MainActor
final class ContentDataSource: ContentDataSourceProtocol {
    private let parserDataSource: LuegoParserDataSourceProtocol
    private let parsedContentCache: ParsedContentCacheDataSourceProtocol
    private let luegoAPIDataSource: LuegoAPIDataSourceProtocol
    private let webPageDataSource: WebPageDataSourceProtocol
    private let sdkManager: LuegoSDKManagerProtocol

    init(
        parserDataSource: LuegoParserDataSourceProtocol,
        parsedContentCache: ParsedContentCacheDataSourceProtocol,
        luegoAPIDataSource: LuegoAPIDataSourceProtocol,
        webPageDataSource: WebPageDataSourceProtocol,
        sdkManager: LuegoSDKManagerProtocol
    ) {
        self.parserDataSource = parserDataSource
        self.parsedContentCache = parsedContentCache
        self.luegoAPIDataSource = luegoAPIDataSource
        self.webPageDataSource = webPageDataSource
        self.sdkManager = sdkManager
    }

    func validateURL(_ url: URL) async throws -> URL {
        try await webPageDataSource.validateURL(url)
    }

    func fetchMetadata(for url: URL, timeout: TimeInterval?) async throws -> ArticleMetadata {
        if await parserDataSource.isReady {
            if let metadata = await tryLocalMetadataParsing(url: url, timeout: timeout) {
                return metadata
            }
        }
        return try await fetchMetadataFromAPI(url: url)
    }

    func fetchContent(for url: URL, timeout: TimeInterval?, forceRefresh: Bool, skipCache: Bool) async throws -> ArticleContent {
        await logFetchStart(url: url, forceRefresh: forceRefresh, skipCache: skipCache)

        let result: ArticleContent
        if skipCache {
            result = try await fetchContentWithoutCaching(url: url, timeout: timeout)
        } else if !forceRefresh, let cached = await parsedContentCache.get(for: url) {
            result = cached
        } else {
            if forceRefresh {
                await parsedContentCache.remove(for: url)
            }
            if await parserDataSource.isReady, let parsed = await tryLocalParsing(url: url, timeout: timeout) {
                result = parsed
            } else {
                result = try await fetchFromAPI(url: url)
            }
            await parsedContentCache.save(result, for: url)
        }
        return result
    }

    private func fetchContentWithoutCaching(url: URL, timeout: TimeInterval?) async throws -> ArticleContent {
        if await parserDataSource.isReady {
            if let result = await tryLocalParsing(url: url, timeout: timeout) {
                return result
            }
        }
        return try await fetchFromAPI(url: url)
    }

    private func tryLocalParsing(url: URL, timeout: TimeInterval?) async -> ArticleContent? {
        do {
            let html = try await webPageDataSource.fetchHTML(from: url, timeout: timeout)

            let result = await parserDataSource.parse(html: html, url: url)

            guard let result,
                  result.success,
                  let content = result.content,
                  !content.isEmpty else {
                Logger.content.debug("✗ Local SDK parsing failed → falling back to API")
                return nil
            }

            Logger.content.debug("✓ Local SDK parsing SUCCESS")

            return await ArticleContent.prepare(from: result, url: url)
        } catch {
            Logger.content.debug("✗ HTML fetch failed: \(error.localizedDescription) → falling back to API")
            return nil
        }
    }

    private func fetchFromAPI(url: URL) async throws -> ArticleContent {
        let response = try await luegoAPIDataSource.fetchArticle(for: url)

        Logger.content.debug("✓ API fetch SUCCESS")

        let publishedDate = parsePublishedDate(from: response.metadata.publishedDate)
        let thumbnailURL = response.metadata.thumbnail.flatMap { URL(string: $0) }

        return ArticleContent(
            title: response.metadata.title ?? url.host() ?? url.absoluteString,
            thumbnailURL: thumbnailURL,
            description: nil,
            content: response.content,
            publishedDate: publishedDate,
            wordCount: response.metadata.wordCount
        )
    }

    private func tryLocalMetadataParsing(url: URL, timeout: TimeInterval?) async -> ArticleMetadata? {
        do {
            let html = try await webPageDataSource.fetchHTML(from: url, timeout: timeout)

            let result = await parserDataSource.parse(html: html, url: url)

            guard let result,
                  result.success,
                  result.metadata != nil else {
                return nil
            }

            let content = await ArticleContent.prepare(from: result, url: url)
            if !content.content.isEmpty {
                await parsedContentCache.save(content, for: url)
            }
            return ArticleMetadata(title: content.title, thumbnailURL: content.thumbnailURL, description: content.description, content: content.content, publishedDate: content.publishedDate, wordCount: content.wordCount)
        } catch {
            return nil
        }
    }

    private func fetchMetadataFromAPI(url: URL) async throws -> ArticleMetadata {
        let content = try await fetchFromAPI(url: url)

        if !content.content.isEmpty {
            await parsedContentCache.save(content, for: url)
        }

        return ArticleMetadata(
            title: content.title,
            thumbnailURL: content.thumbnailURL,
            description: content.description,
            content: content.content,
            publishedDate: content.publishedDate,
            wordCount: content.wordCount
        )
    }

    private func parsePublishedDate(from dateString: String?) -> Date? {
        guard let dateString = dateString else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let date = formatter.date(from: dateString) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: dateString)
    }

    private func logFetchStart(url: URL, forceRefresh: Bool, skipCache: Bool) async {
        let host = url.host() ?? url.absoluteString
        let sdkReady = await parserDataSource.isReady
        let versionString = await formatVersionString()
        let cacheMode = formatCacheMode(forceRefresh: forceRefresh, skipCache: skipCache)

        Logger.content.debug("""
        ─────────────────────────────────
        URL: \(host)
        SDK: \(sdkReady ? "Ready" : "Not available") \(versionString)
        Cache: \(cacheMode)
        ────────────────────────────────────────────────────
        """)
    }

    private func formatVersionString() async -> String {
        guard let info = await sdkManager.getVersionInfo() else {
            return ""
        }
        return "(v\(info.parserVersion), rules: \(info.rulesVersion))"
    }

    private func formatCacheMode(forceRefresh: Bool, skipCache: Bool) -> String {
        if skipCache {
            return "SKIP (no read/write)"
        } else if forceRefresh {
            return "FORCE REFRESH (clear → fetch → save)"
        } else {
            return "NORMAL (read → fetch if miss → save)"
        }
    }
}
