import Foundation

enum DiscoveryError: LocalizedError {
    case contentFetchFailed(Error)

    var errorDescription: String? {
        switch self {
        case .contentFetchFailed(let underlyingError):
            return "Could not load article content: \(underlyingError.localizedDescription)"
        }
    }
}

@MainActor
protocol DiscoveryServiceProtocol: Sendable {
    func fetchRandomArticle(
        from source: DiscoverySource,
        onArticleEntryFetched: @escaping @MainActor (URL) -> Void
    ) async throws -> EphemeralArticle
    func prepareForFetch(source: DiscoverySource) -> DiscoverySource
    func clearCache(for source: DiscoverySource)
    func clearAllCaches()
}

@MainActor
final class DiscoveryService: DiscoveryServiceProtocol {
    private let kagiSmallWebDataSource: DiscoverySourceProtocol
    private let blogrollDataSource: DiscoverySourceProtocol
    private let contentDataSource: ContentDataSourceProtocol
    private var preparedSurpriseMeSource: DiscoverySource?

    init(
        kagiSmallWebDataSource: DiscoverySourceProtocol,
        blogrollDataSource: DiscoverySourceProtocol,
        contentDataSource: ContentDataSourceProtocol
    ) {
        self.kagiSmallWebDataSource = kagiSmallWebDataSource
        self.blogrollDataSource = blogrollDataSource
        self.contentDataSource = contentDataSource
    }

    func prepareForFetch(source: DiscoverySource) -> DiscoverySource {
        if source == .surpriseMe {
            let picked = DiscoverySource.concreteSources.randomElement() ?? .kagiSmallWeb
            preparedSurpriseMeSource = picked
            return picked
        }
        return source
    }

    func fetchRandomArticle(
        from source: DiscoverySource,
        onArticleEntryFetched: @escaping @MainActor (URL) -> Void
    ) async throws -> EphemeralArticle {
        let effectiveSource: DiscoverySource
        if source == .surpriseMe {
            effectiveSource = preparedSurpriseMeSource ?? DiscoverySource.concreteSources.randomElement() ?? .kagiSmallWeb
            preparedSurpriseMeSource = nil
        } else {
            effectiveSource = source
        }

        let dataSource = dataSourceForSource(effectiveSource)
        return try await fetchArticleFromSource(dataSource, onArticleEntryFetched: onArticleEntryFetched)
    }

    func clearCache(for source: DiscoverySource) {
        switch source {
        case .kagiSmallWeb:
            kagiSmallWebDataSource.clearCache()
        case .blogroll:
            blogrollDataSource.clearCache()
        case .surpriseMe:
            clearAllCaches()
        }
    }

    func clearAllCaches() {
        kagiSmallWebDataSource.clearCache()
        blogrollDataSource.clearCache()
    }

    private func dataSourceForSource(_ source: DiscoverySource) -> DiscoverySourceProtocol {
        switch source {
        case .kagiSmallWeb, .surpriseMe:
            return kagiSmallWebDataSource
        case .blogroll:
            return blogrollDataSource
        }
    }

    private func fetchArticleFromSource(
        _ sourceDataSource: DiscoverySourceProtocol,
        onArticleEntryFetched: @escaping @MainActor (URL) -> Void
    ) async throws -> EphemeralArticle {
        let maxRetries = 10
        for _ in 0..<maxRetries {
            let articleEntry = try await sourceDataSource.randomArticleEntry()
            if isYouTubeURL(articleEntry.articleUrl) {
                continue
            }
            onArticleEntryFetched(articleEntry.articleUrl)
            return try await fetchArticleContent(for: articleEntry)
        }
        let articleEntry = try await sourceDataSource.randomArticleEntry()
        onArticleEntryFetched(articleEntry.articleUrl)
        return try await fetchArticleContent(for: articleEntry)
    }

    private func isYouTubeURL(_ url: URL) -> Bool {
        guard let host = url.host()?.lowercased() else { return false }
        let youtubeHosts = ["youtube.com", "www.youtube.com", "m.youtube.com", "youtu.be"]
        return youtubeHosts.contains(host)
    }

    private func fetchArticleContent(for articleEntry: SmallWebArticleEntry) async throws -> EphemeralArticle {
        let discoveryTimeoutSeconds: TimeInterval = 10

        do {
            let articleContent = try await contentDataSource.fetchContent(
                for: articleEntry.articleUrl,
                timeout: discoveryTimeoutSeconds,
                forceRefresh: false,
                skipCache: true
            )
            let domain = articleEntry.articleUrl.host() ?? "Unknown"

            return EphemeralArticle(
                url: articleEntry.articleUrl,
                title: articleContent.title,
                content: articleContent.content,
                thumbnailURL: articleContent.thumbnailURL,
                publishedDate: articleContent.publishedDate,
                feedTitle: domain
            )
        } catch {
            throw DiscoveryError.contentFetchFailed(error)
        }
    }
}
