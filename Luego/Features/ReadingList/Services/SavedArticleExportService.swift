import Foundation

enum SavedArticleExportScope: String, CaseIterable, Identifiable, Sendable {
    case allArticles
    case readingList

    var id: String {
        rawValue
    }

    fileprivate var filenameComponent: String {
        switch self {
        case .allArticles:
            return "all-articles"
        case .readingList:
            return "reading-list"
        }
    }
}

struct SavedArticlePlainTextExport: Sendable, Equatable {
    let filename: String
    let body: String
    let articleCount: Int
    let scope: SavedArticleExportScope
}

@MainActor
protocol SavedArticleExportServiceProtocol: Sendable {
    func makePlainTextExport(scope: SavedArticleExportScope) async throws -> SavedArticlePlainTextExport
}

@MainActor
final class SavedArticleExportService: SavedArticleExportServiceProtocol {
    private let articleStore: ArticleStoreProtocol

    init(articleStore: ArticleStoreProtocol) {
        self.articleStore = articleStore
    }

    func makePlainTextExport(scope: SavedArticleExportScope) async throws -> SavedArticlePlainTextExport {
        let articles = try await articles(for: scope)

        return SavedArticlePlainTextExport(
            filename: makeFilename(scope: scope),
            body: articles.map { $0.url.absoluteString }.joined(separator: "\n"),
            articleCount: articles.count,
            scope: scope
        )
    }

    private func articles(for scope: SavedArticleExportScope) async throws -> [Article] {
        let articles = try await articleStore.fetchAllArticles()

        switch scope {
        case .allArticles:
            return articles
        case .readingList:
            return articles.filter { !$0.isArchived }
        }
    }

    private func makeFilename(scope: SavedArticleExportScope) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"

        return "luego-\(scope.filenameComponent)-\(formatter.string(from: Date())).txt"
    }
}
