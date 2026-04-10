import Foundation

@MainActor
protocol SharingServiceProtocol: Sendable {
    func syncSharedArticles() async throws -> [Article]
}

@MainActor
final class SharingService: SharingServiceProtocol {
    private let articleStore: ArticleStoreProtocol
    private let metadataDataSource: MetadataDataSourceProtocol
    private let userDefaultsDataSource: UserDefaultsDataSourceProtocol

    init(
        articleStore: ArticleStoreProtocol,
        metadataDataSource: MetadataDataSourceProtocol,
        userDefaultsDataSource: UserDefaultsDataSourceProtocol
    ) {
        self.articleStore = articleStore
        self.metadataDataSource = metadataDataSource
        self.userDefaultsDataSource = userDefaultsDataSource
    }

    func syncSharedArticles() async throws -> [Article] {
        let sharedURLs = try userDefaultsDataSource.getSharedURLs()

        guard !sharedURLs.isEmpty else {
            return []
        }

        var newArticles: [Article] = []
        var remainingSharedURLs: [SharedURL] = []

        for sharedURL in sharedURLs {
            do {
                let validatedURL = try await metadataDataSource.validateURL(sharedURL.url)

                if (try articleStore.fetchArticle(url: validatedURL)) != nil {
                    Logger.sharing.debug("Skipping duplicate URL: \(validatedURL.absoluteString)")
                    continue
                }

                let metadata = try await metadataDataSource.fetchMetadata(for: validatedURL)

                let article = Article(
                    id: UUID(),
                    url: validatedURL,
                    title: metadata.title,
                    content: nil,
                    savedDate: Date(),
                    thumbnailURL: metadata.thumbnailURL,
                    publishedDate: metadata.publishedDate,
                    readPosition: 0
                )

                do {
                    let savedArticle = try articleStore.saveArticle(article)
                    newArticles.append(savedArticle)
                } catch {
                    if let existingArticle = try articleStore.fetchArticle(url: validatedURL) {
                        Logger.sharing.debug("Duplicate detected via constraint: \(validatedURL.absoluteString)")
                        newArticles.append(existingArticle)
                    } else {
                        Logger.sharing.error("Failed to save article and no existing article found: \(error.localizedDescription)")
                        remainingSharedURLs.append(sharedURL)
                    }
                }
            } catch {
                Logger.sharing.error("Failed to sync shared article from \(sharedURL.url.absoluteString): \(error.localizedDescription)")
                remainingSharedURLs.append(sharedURL)
                continue
            }
        }

        try userDefaultsDataSource.replaceSharedURLs(remainingSharedURLs)

        return newArticles
    }
}
