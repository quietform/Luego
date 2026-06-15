import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class ArticleListViewModel {
    var articles: [Article] = []
    var isLoading = false
    var errorMessage: String?
    var pendingMemberships: [UUID: ArticleListMembership] = [:]

    private let articleService: ArticleServiceProtocol
    private let sharingService: SharingServiceProtocol
    @ObservationIgnored
    private var observationTask: Task<Void, Never>?
    @ObservationIgnored
    private var observationRetryTask: Task<Void, Never>?

    init(
        articleService: ArticleServiceProtocol,
        sharingService: SharingServiceProtocol
    ) {
        self.articleService = articleService
        self.sharingService = sharingService
        self.articles = []
    }

    deinit {
        observationTask?.cancel()
        observationRetryTask?.cancel()
    }

    func startObservingArticles() {
        guard observationTask == nil else { return }

        observationRetryTask?.cancel()
        observationRetryTask = nil
        observationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                observationTask = nil
            }

            do {
                self.errorMessage = nil
                for try await articles in articleService.observeArticles() {
                    discardResolvedPendingMemberships(using: articles)
                    if shouldReplaceArticles(with: articles) {
                        if self.articles.isEmpty {
                            self.articles = articles
                        } else {
                            withAnimation(.snappy) {
                                self.articles = articles
                            }
                        }
                    }
                }
            } catch is CancellationError {
            } catch {
                self.errorMessage = "Failed to observe articles: \(error.localizedDescription)"
                scheduleObservationRestart()
            }
        }
    }

    func addArticle(from urlString: String) async {
        errorMessage = nil

        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespaces)) else {
            errorMessage = "Please enter a valid URL"
            return
        }

        if (try? await articleService.isArticleSaved(url: url)) == true {
            errorMessage = "This article has already been saved"
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            _ = try await articleService.addArticle(url: url)
        } catch let error as ArticleMetadataError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = "Failed to save article: \(error.localizedDescription)"
        }
    }

    func openOrImportArticle(from url: URL) async throws -> Article {
        try await articleService.addArticle(url: url)
    }

    func deleteArticle(_ article: Article) async {
        do {
            try await articleService.deleteArticle(id: article.id)
        } catch {
            errorMessage = "Failed to delete article: \(error.localizedDescription)"
        }
    }

    func syncSharedArticles() async {
        do {
            _ = try await sharingService.syncSharedArticles()
        } catch {
            errorMessage = "Failed to sync shared articles: \(error.localizedDescription)"
        }
    }

    func refreshArticles() async {
        do {
            try await articleService.refreshArticles()
        } catch {
            errorMessage = "Failed to refresh articles: \(error.localizedDescription)"
        }
    }

    func clearError() {
        errorMessage = nil
    }

    func toggleFavorite(_ article: Article) async {
        let originalMembership = membership(for: article)
        let nextMembership = originalMembership.togglingFavorite()

        applyPendingMembership(nextMembership, for: article.id)
        do {
            try await articleService.toggleFavorite(id: article.id)
            reconcileArticleState(id: article.id, membership: nextMembership)
        } catch {
            revertArticleState(id: article.id, membership: originalMembership)
            errorMessage = "Failed to toggle favorite: \(error.localizedDescription)"
        }
    }

    func toggleArchive(_ article: Article) async {
        let originalMembership = membership(for: article)
        let nextMembership = originalMembership.togglingArchive()

        applyPendingMembership(nextMembership, for: article.id)
        do {
            try await articleService.toggleArchive(id: article.id)
            reconcileArticleState(id: article.id, membership: nextMembership)
        } catch {
            revertArticleState(id: article.id, membership: originalMembership)
            errorMessage = "Failed to toggle archive: \(error.localizedDescription)"
        }
    }

    func membership(for article: Article) -> ArticleListMembership {
        pendingMemberships[article.id] ?? article.listMembership
    }

    func filteredArticles(for filter: ArticleFilter) -> [Article] {
        return filter.filtered(articles, membership: membership(for:))
    }

    private func applyPendingMembership(_ membership: ArticleListMembership, for id: UUID) {
        withAnimation(.snappy) {
            pendingMemberships[id] = membership
            guard let article = articles.first(where: { $0.id == id }) else {
                return
            }
            article.applyListMembership(membership)
        }
    }

    private func reconcileArticleState(id: UUID, membership: ArticleListMembership) {
        withAnimation(.snappy) {
            pendingMemberships.removeValue(forKey: id)
            guard let index = articles.firstIndex(where: { $0.id == id }) else {
                return
            }
            articles[index].applyListMembership(membership)
        }
    }

    private func revertArticleState(id: UUID, membership: ArticleListMembership) {
        withAnimation(.snappy) {
            pendingMemberships.removeValue(forKey: id)
            guard let index = articles.firstIndex(where: { $0.id == id }) else {
                return
            }
            articles[index].applyListMembership(membership)
        }
    }

    private func discardResolvedPendingMemberships(using articles: [Article]) {
        guard !pendingMemberships.isEmpty else { return }

        pendingMemberships = pendingMemberships.filter { id, pendingMembership in
            guard let article = articles.first(where: { $0.id == id }) else {
                return false
            }
            return article.listMembership != pendingMembership
        }
    }

    private func scheduleObservationRestart() {
        guard observationRetryTask == nil else { return }

        observationRetryTask = Task { @MainActor [weak self] in
            defer {
                self?.observationRetryTask = nil
            }

            do {
                try await Task.sleep(nanoseconds: 3_000_000_000)
            } catch {
                return
            }

            self?.startObservingArticles()
        }
    }

    private func shouldReplaceArticles(with newArticles: [Article]) -> Bool {
        guard articles.count == newArticles.count else {
            return true
        }

        for (currentArticle, newArticle) in zip(articles, newArticles) {
            if currentArticle.id != newArticle.id || currentArticle !== newArticle {
                return true
            }
        }

        return false
    }
}
