import Foundation

enum KagiLoadingGifRotator {
    private static let gifs = ["kagi-loading", "kagi-loading-2"]
    private static var lastIndex: Int?

    static func next() -> String {
        let availableIndices = gifs.indices.filter { $0 != lastIndex }
        let nextIndex = availableIndices.randomElement() ?? 0
        lastIndex = nextIndex
        return gifs[nextIndex]
    }
}

@Observable
@MainActor
final class DiscoveryViewModel {
    var selectedSource: DiscoverySource
    var activeSource: DiscoverySource?
    var ephemeralArticle: EphemeralArticle?
    var isLoading = false
    var errorMessage: String?
    var isSaved = false
    var pendingArticleURL: URL?
    var currentLoadingGif: String = KagiLoadingGifRotator.next()
    private var consecutiveFailures = 0

    private let discoveryService: DiscoveryServiceProtocol
    private let articleService: ArticleServiceProtocol

    var currentLoadingText: String {
        (activeSource ?? selectedSource).loadingText
    }

    init(
        discoveryService: DiscoveryServiceProtocol,
        articleService: ArticleServiceProtocol,
        preferencesDataSource: DiscoveryPreferencesDataSourceProtocol
    ) {
        self.discoveryService = discoveryService
        self.articleService = articleService
        self.selectedSource = preferencesDataSource.getSelectedSource()
    }

    func fetchRandomArticle() async {
        isLoading = true
        errorMessage = nil
        ephemeralArticle = nil
        pendingArticleURL = nil
        isSaved = false

        activeSource = discoveryService.prepareForFetch(source: selectedSource)

        if activeSource == .kagiSmallWeb {
            currentLoadingGif = KagiLoadingGifRotator.next()
        }

        do {
            let article = try await discoveryService.fetchRandomArticle(from: selectedSource) { [weak self] url in
                self?.pendingArticleURL = url
            }
            consecutiveFailures = 0
            pendingArticleURL = nil
            ephemeralArticle = article
            await checkIfAlreadySaved(url: article.url)
        } catch {
            consecutiveFailures += 1
            pendingArticleURL = nil
            if consecutiveFailures < 5 {
                await fetchRandomArticle()
                return
            }
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func saveToReadingList() async {
        guard let article = ephemeralArticle else { return }

        do {
            _ = try await articleService.saveEphemeralArticle(article)
            isSaved = true
        } catch {
            errorMessage = "Failed to save article"
        }
    }

    func loadAnotherArticle() async {
        await fetchRandomArticle()
    }

    private func checkIfAlreadySaved(url: URL) async {
        do {
            isSaved = try await articleService.isArticleSaved(url: url)
        } catch {
            isSaved = false
        }
    }
}
