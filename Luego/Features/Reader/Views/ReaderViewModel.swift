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
    private var loadingTask: Task<Void, Never>?
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
        loadingTask?.cancel()
        let requestID = UUID()
        loadingRequestID = requestID
        isLoading = true
        errorMessage = nil

        let task = Task { [weak self] in
            guard let self else { return }

            do {
                try Task.checkCancellation()
                let updatedArticle = try await readerService.fetchContent(for: article, forceRefresh: forceRefresh)
                try Task.checkCancellation()

                article = updatedArticle
                articleContent = updatedArticle.content
                Logger.reader.debug("Content loaded successfully")
            } catch is CancellationError {
                Logger.reader.debug("Content fetch cancelled for article \(article.id)")
            } catch {
                if !Task.isCancelled {
                    Logger.reader.error("Content fetch failed: \(error.localizedDescription)")
                    errorMessage = error.localizedDescription
                }
            }

            if loadingRequestID == requestID {
                isLoading = false
                loadingTask = nil
            }
        }

        loadingTask = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    func updateReadPosition(_ position: Double) async {
        let clampedPosition = max(0.0, min(1.0, position))
        article.readPosition = clampedPosition

        do {
            try await readerService.updateReadPosition(articleId: article.id, position: clampedPosition)
        } catch {
            errorMessage = "Failed to save read position: \(error.localizedDescription)"
        }
    }
}
