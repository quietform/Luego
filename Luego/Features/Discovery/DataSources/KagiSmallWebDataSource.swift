import Foundation

@MainActor
protocol DiscoveryPostSourceProtocol: Sendable {
    func fetchPosts() async throws -> [DiscoveryPost]
}

enum SmallWebError: LocalizedError {
    case fetchFailed(Error)
    case noArticlesAvailable

    var errorDescription: String? {
        switch self {
        case .fetchFailed:
            return "Could not load the article list"
        case .noArticlesAvailable:
            return "No articles available"
        }
    }
}

@MainActor
final class KagiSmallWebDataSource: DiscoveryPostSourceProtocol {
    private let genericRSSDataSource: GenericRSSDataSource
    private let session: URLSession
    private let riverURL: URL

    init(
        genericRSSDataSource: GenericRSSDataSource,
        session: URLSession = .shared,
        riverURL: URL = URL(string: "https://kagi.com/api/v1/smallweb/feed/")!
    ) {
        self.genericRSSDataSource = genericRSSDataSource
        self.session = session
        self.riverURL = riverURL
    }

    func fetchPosts() async throws -> [DiscoveryPost] {
        let data: Data
        do {
            (data, _) = try await session.data(from: riverURL)
        } catch {
            throw SmallWebError.fetchFailed(error)
        }
        let posts = await genericRSSDataSource.parse(data)
            .filter { !Self.isVideoURL($0.postURL) }
            .compactMap { entry in
                entry.title.map {
                    DiscoveryPost(url: entry.postURL, title: $0, publishedDate: entry.publishedDate, excerpt: entry.excerpt, thumbnailURL: entry.imageURL)
                }
            }
        guard !posts.isEmpty else { throw SmallWebError.noArticlesAvailable }
        return posts
    }

    private static func isVideoURL(_ url: URL) -> Bool {
        guard let host = url.host()?.lowercased() else { return false }
        return ["youtube.com", "www.youtube.com", "m.youtube.com", "youtu.be"].contains(host)
    }
}
