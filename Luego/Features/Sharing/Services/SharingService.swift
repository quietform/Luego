import Foundation

@MainActor
protocol SharingServiceProtocol: Sendable {
    func syncSharedArticles() async throws -> [Article]
}

@MainActor
final class SharingService: SharingServiceProtocol {
    private let articleService: ArticleServiceProtocol
    private let sharedStorage: SharedStorageDataSourceProtocol

    init(
        articleService: ArticleServiceProtocol,
        sharedStorage: SharedStorageDataSourceProtocol
    ) {
        self.articleService = articleService
        self.sharedStorage = sharedStorage
    }

    func syncSharedArticles() async throws -> [Article] {
        let sharedURLs = try sharedStorage.getSharedURLs()

        guard !sharedURLs.isEmpty else {
            return []
        }

        var newArticles: [Article] = []

        for sharedURL in sharedURLs {
            do {
                let result = try await articleService.addArticle(url: sharedURL.url, savedDate: Date())
                try sharedStorage.acknowledgeSharedURL(id: sharedURL.id)
                if result.isNew {
                    newArticles.append(result.article)
                }
            } catch {
                Logger.sharing.error("Failed to sync shared article from \(sharedURL.url.absoluteString): \(error.localizedDescription)")
                continue
            }
        }

        return newArticles
    }
}
