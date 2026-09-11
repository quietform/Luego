import Foundation

@MainActor
final class TestContentDataSource: ContentDataSourceProtocol {
    var onFetchMetadata: (URL) async throws -> ArticleMetadata = { _ in ArticleMetadata(title: "Article") }

    func validateURL(_ url: URL) async throws -> URL {
        try await WebPageDataSource().validateURL(url)
    }

    func fetchMetadata(for url: URL, timeout: TimeInterval?) async throws -> ArticleMetadata {
        try await onFetchMetadata(url)
    }

    func fetchContent(for url: URL, timeout: TimeInterval?, forceRefresh: Bool, skipCache: Bool) async throws -> ArticleContent {
        throw ArticleMetadataError.noMetadata
    }
}
