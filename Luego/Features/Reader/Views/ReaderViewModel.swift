import Foundation
import Observation

@Observable
@MainActor
final class ReaderViewModel {
    var article: Article
    var articleContent: String?
    var isLoading: Bool
    var errorMessage: String?

    @ObservationIgnored
    private var loadingRequestID = UUID()
    private let readerService: ReaderServiceProtocol

    init(
        article: Article,
        readerService: ReaderServiceProtocol
    ) {
        self.article = article
        self.articleContent = article.content
        self.isLoading = article.content == nil
        self.readerService = readerService
    }

    func loadContent() async {
        Logger.reader.debug("loadContent() called for article \(article.id)")

        guard articleContent == nil else {
            Logger.reader.debug("Content already loaded, skipping")
            return
        }

        await fetchContent(forceRefresh: false)
    }

    func refreshContent() async {
        Logger.reader.debug("refreshContent() called for article \(article.id)")
        await fetchContent(forceRefresh: true)
    }

    private func fetchContent(forceRefresh: Bool) async {
        let requestID = UUID()
        loadingRequestID = requestID
        isLoading = true
        errorMessage = nil
        defer {
            if loadingRequestID == requestID { isLoading = false }
        }

        do {
            let updatedArticle = try await readerService.fetchContent(for: article, forceRefresh: forceRefresh)
            try Task.checkCancellation()
            article = updatedArticle
            articleContent = updatedArticle.content
            Logger.reader.debug("Content loaded successfully")
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled else { return }
            Logger.reader.error("Content fetch failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    func updateReadPosition(_ position: Double, documentPrepared: Bool) async {
        guard documentPrepared else { return }
        let clampedPosition = max(0.0, min(1.0, position))
        article.readPosition = clampedPosition

        do {
            try await readerService.updateReadPosition(articleId: article.id, position: clampedPosition)
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = "Failed to save read position: \(error.localizedDescription)"
        }
    }
}
