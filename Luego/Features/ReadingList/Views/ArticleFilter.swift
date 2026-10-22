import Foundation
import SwiftUI

enum ArticleFilter: CaseIterable, Hashable {
    case discovery
    case readingList
    case favorites
    case archived

    var navigationTitle: String {
        switch self {
        case .readingList: "Reading List"
        case .favorites: "Favorites"
        case .archived: "Archived"
        case .discovery: "Discovery"
        }
    }

    var title: String {
        switch self {
        case .readingList: "All Articles"
        case .favorites: "Favourites"
        case .archived: "Archived"
        case .discovery: "Discovery"
        }
    }

    var icon: String {
        switch self {
        case .readingList: "list.bullet"
        case .favorites: "heart"
        case .archived: "archivebox.fill"
        case .discovery: "globe"
        }
    }

    var emptyStateIcon: String {
        switch self {
        case .readingList: "doc.text.fill"
        case .favorites: "heart.fill"
        case .archived: "archivebox.fill"
        case .discovery: "globe"
        }
    }

    var emptyStateTitle: String {
        switch self {
        case .readingList: "Hola!"
        case .favorites: "No Favorites"
        case .archived: "No Archived Articles"
        case .discovery: "Discover Something New"
        }
    }

    var emptyStateLines: [String] {
        switch self {
        case .readingList:
            [
                "Kike's looking for something good.",
                "Add your first article.",
                "He'll watch over your reading list."
            ]
        case .favorites:
            ["Articles you favorite will appear here"]
        case .archived:
            ["Archived articles will appear here"]
        case .discovery:
            ["Recent posts from the small web will appear here"]
        }
    }

    var emptyStateIconColor: Color {
        switch self {
        case .readingList: .gray
        case .favorites: .pink
        case .archived: .blue
        case .discovery: .regularSelectionInk
        }
    }

    func matches(_ membership: ArticleListMembership) -> Bool {
        switch self {
        case .readingList: !membership.isFavorite && !membership.isArchived
        case .favorites: membership.isFavorite
        case .archived: membership.isArchived
        case .discovery: false
        }
    }

    func filtered(_ articles: [Article]) -> [Article] {
        articles.filter { matches($0.listMembership) }
    }

    func filtered(
        _ articles: [Article],
        membership: (Article) -> ArticleListMembership
    ) -> [Article] {
        articles.filter { matches(membership($0)) }
    }
}
