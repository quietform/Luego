import Foundation
import Observation

@Observable
@MainActor
final class DiscoveryArticleViewModel {
    let post: DiscoveryPost
    var article: EphemeralArticle?
    var isLoading = false
    var errorMessage: String?
    var isSaved = false

    private let discoveryService: DiscoveryServiceProtocol
    private let articleService: ArticleServiceProtocol

    init(post: DiscoveryPost, discoveryService: DiscoveryServiceProtocol, articleService: ArticleServiceProtocol) {
        self.post = post
        self.discoveryService = discoveryService
        self.articleService = articleService
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            let fetchedArticle = try await discoveryService.fetchArticle(for: post)
            let saved = (try? await articleService.isArticleSaved(url: post.url)) ?? false
            try Task.checkCancellation()
            article = fetchedArticle
            isSaved = saved
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    func save() async {
        guard let article, (try? await articleService.saveEphemeralArticle(article)) != nil else { return }
        isSaved = true
    }
}
