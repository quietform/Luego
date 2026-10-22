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
    func fetchPosts() async throws -> [DiscoveryPost]
    func fetchArticle(for post: DiscoveryPost) async throws -> EphemeralArticle
}

@MainActor
final class DiscoveryService: DiscoveryServiceProtocol {
    private let postSource: DiscoveryPostSourceProtocol
    private let contentDataSource: ContentDataSourceProtocol
    private let articleTimeout: TimeInterval = 10

    init(postSource: DiscoveryPostSourceProtocol, contentDataSource: ContentDataSourceProtocol) {
        self.postSource = postSource
        self.contentDataSource = contentDataSource
    }

    func fetchPosts() async throws -> [DiscoveryPost] {
        try await postSource.fetchPosts()
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
                thumbnailURL: content.thumbnailURL,
                publishedDate: content.publishedDate,
                feedTitle: post.domain
            )
        } catch {
            throw DiscoveryError.contentFetchFailed(error)
        }
    }
}
