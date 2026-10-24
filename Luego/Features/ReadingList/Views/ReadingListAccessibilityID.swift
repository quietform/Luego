import Foundation

enum ReadingListAccessibilityID {
    static let addButton = "articleList.toolbar.add"

    static func list(_ filter: ArticleFilter) -> String {
        "articleList.\(filterSegment(filter))"
    }

    static func row(_ article: Article) -> String {
        "article.\(articleSegment(article))"
    }

    static func open(_ article: Article) -> String {
        "\(row(article)).open"
    }

    static func favoriteAction(_ article: Article) -> String {
        "\(row(article)).action.favorite"
    }

    static func archiveAction(_ article: Article) -> String {
        "\(row(article)).action.archive"
    }

    static func deleteAction(_ article: Article) -> String {
        "\(row(article)).action.delete"
    }

    static func favoriteBadge(_ article: Article) -> String {
        "\(row(article)).favoriteBadge"
    }

    static func readProgress(_ article: Article) -> String {
        "\(row(article)).readProgress"
    }

    private static func filterSegment(_ filter: ArticleFilter) -> String {
        switch filter {
        case .readingList:
            "readingList"
        case .favorites:
            "favorites"
        case .archived:
            "archived"
        case .discovery:
            "discovery"
        }
    }

    private static func articleSegment(_ article: Article) -> String {
        article.id.uuidString.lowercased()
    }
}
