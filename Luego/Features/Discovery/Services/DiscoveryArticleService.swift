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
protocol DiscoveryArticleServiceProtocol: Sendable {
    func fetchArticle(for post: DiscoveryPost) async throws -> EphemeralArticle
}

@MainActor
final class DiscoveryArticleService: DiscoveryArticleServiceProtocol {
    private let contentDataSource: ContentDataSourceProtocol
    private let articleTimeout: TimeInterval = 10

    init(contentDataSource: ContentDataSourceProtocol) {
        self.contentDataSource = contentDataSource
    }

    func fetchArticle(for post: DiscoveryPost) async throws -> EphemeralArticle {
        do {
            let content = try await contentDataSource.fetchContent(
                for: post.url,
                timeout: articleTimeout,
                forceRefresh: false,
                skipCache: true
            )
            return EphemeralArticle(
                url: post.url,
                title: post.title,
                content: content.content,
                thumbnailURL: content.thumbnailURL ?? post.thumbnailURL,
                publishedDate: content.publishedDate,
                feedTitle: post.domain
            )
        } catch {
            throw DiscoveryError.contentFetchFailed(error)
        }
    }
}
