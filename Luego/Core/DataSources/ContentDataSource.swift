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
        if parserDataSource.isReady {
            if let metadata = await tryLocalMetadataParsing(url: url, timeout: timeout) {
                return metadata
            }
        }
        return try await fetchMetadataFromAPI(url: url)
    }

    func fetchContent(for url: URL, timeout: TimeInterval?, forceRefresh: Bool, skipCache: Bool) async throws -> ArticleContent {
        logFetchStart(url: url, forceRefresh: forceRefresh, skipCache: skipCache)

        if skipCache {
            return try await fetchContentWithoutCaching(url: url, timeout: timeout)
        }

        if forceRefresh {
            parsedContentCache.remove(for: url)
            Logger.content.debug("Cache cleared (forceRefresh)")
        } else if let cached = parsedContentCache.get(for: url) {
            Logger.content.debug("✓ Cache HIT")
            return cached
        }

        if parserDataSource.isReady {
            if let result = await tryLocalParsing(url: url, timeout: timeout) {
                parsedContentCache.save(result, for: url)
                return result
            }
        }

        let result = try await fetchFromAPI(url: url)
        parsedContentCache.save(result, for: url)
        return result
    }

    private func fetchContentWithoutCaching(url: URL, timeout: TimeInterval?) async throws -> ArticleContent {
        if parserDataSource.isReady {
            if let result = await tryLocalParsing(url: url, timeout: timeout) {
                return result
            }
        }
        return try await fetchFromAPI(url: url)
    }

    private func tryLocalParsing(url: URL, timeout: TimeInterval?) async -> ArticleContent? {
        do {
            let html = try await webPageDataSource.fetchHTML(from: url, timeout: timeout)

            guard let result = await parserDataSource.parse(html: html, url: url),
                  result.success,
                  let content = result.content,
                  !content.isEmpty else {
                Logger.content.debug("✗ Local SDK parsing failed → falling back to API")
                return nil
            }

            Logger.content.debug("✓ Local SDK parsing SUCCESS")

            return ArticleContent(from: result, url: url)
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

            guard let result = await parserDataSource.parse(html: html, url: url),
                  result.success,
                  let metadata = result.metadata else {
                return nil
            }

            if let content = result.content, !content.isEmpty {
                parsedContentCache.save(ArticleContent(from: result, url: url), for: url)
            }

            return buildMetadataFromParserResult(metadata, url: url)
        } catch {
            return nil
        }
    }

    private func fetchMetadataFromAPI(url: URL) async throws -> ArticleMetadata {
        let content = try await fetchFromAPI(url: url)

        if !content.content.isEmpty {
            parsedContentCache.save(content, for: url)
        }

        return ArticleMetadata(
            title: content.title,
            thumbnailURL: content.thumbnailURL,
            description: content.description,
            publishedDate: content.publishedDate,
            wordCount: content.wordCount
        )
    }

    private func buildMetadataFromParserResult(_ metadata: ParserMetadata, url: URL) -> ArticleMetadata {
        let publishedDate = parsePublishedDate(from: metadata.publishedDate)
        let thumbnailURL = metadata.thumbnail.flatMap { URL(string: $0) }

        Logger.content.debug("[ThumbnailDebug] SDK URL Conversion - Input: '\(metadata.thumbnail ?? "nil")' → URL: \(thumbnailURL?.absoluteString ?? "nil")")

        return ArticleMetadata(
            title: metadata.title ?? url.host() ?? url.absoluteString,
            thumbnailURL: thumbnailURL,
            description: metadata.excerpt,
            publishedDate: publishedDate
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

    private func logFetchStart(url: URL, forceRefresh: Bool, skipCache: Bool) {
        let host = url.host() ?? url.absoluteString
        let sdkReady = parserDataSource.isReady
        let versionString = formatVersionString()
        let cacheMode = formatCacheMode(forceRefresh: forceRefresh, skipCache: skipCache)

        Logger.content.debug("""
        ─────────────────────────────────
        URL: \(host)
        SDK: \(sdkReady ? "Ready" : "Not available") \(versionString)
        Cache: \(cacheMode)
        ────────────────────────────────────────────────────
        """)
    }

    private func formatVersionString() -> String {
        guard let info = sdkManager.getVersionInfo() else {
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
