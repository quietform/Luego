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

    var publishedDate: Date? {
        article?.publishedDate ?? post.displayDate(relativeTo: .now)
    }

    private let discoveryArticleService: DiscoveryArticleServiceProtocol
    private let articleService: ArticleServiceProtocol

    init(post: DiscoveryPost, discoveryArticleService: DiscoveryArticleServiceProtocol, articleService: ArticleServiceProtocol) {
        self.post = post
        self.discoveryArticleService = discoveryArticleService
        self.articleService = articleService
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            let fetchedArticle = try await discoveryArticleService.fetchArticle(for: post)
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
