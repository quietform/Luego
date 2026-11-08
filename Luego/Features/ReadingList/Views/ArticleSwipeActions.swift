import SwiftUI

struct ArticleSwipeActions {
    let filter: ArticleFilter
    let viewModel: ArticleListViewModel
    var onDelete: ((Article) -> Void)?

    func favoriteButton(for article: Article) -> some View {
        button(filter == .favorites ? .unfavorite : .favorite) {
            await viewModel.toggleFavorite(article)
        }
        .accessibilityIdentifier(ReadingListAccessibilityID.favoriteAction(article))
    }

    func archiveButton(for article: Article) -> some View {
        button(filter == .archived ? .unarchive : .archive) {
            await viewModel.toggleArchive(article)
        }
        .accessibilityIdentifier(ReadingListAccessibilityID.archiveAction(article))
    }

    func deleteButton(for article: Article) -> some View {
        button(.delete) {
            onDelete?(article)
            await viewModel.deleteArticle(article)
        }
        .accessibilityIdentifier(ReadingListAccessibilityID.deleteAction(article))
    }

    private func button(
        _ action: ArticleSwipeAction,
        perform: @escaping @MainActor () async -> Void
    ) -> some View {
        Button(role: action.role) {
            Task { await perform() }
        } label: {
            Label(action.title, systemImage: action.systemImage)
        }
        .tint(action.tint)
    }
}

enum ArticleSwipeAction {
    case favorite
    case unfavorite
    case archive
    case unarchive
    case delete

    var title: String {
        switch self {
        case .favorite: "Favorite"
        case .unfavorite: "Unfavorite"
        case .archive: "Archive"
        case .unarchive: "Unarchive"
        case .delete: "Delete"
        }
    }

    var systemImage: String {
        switch self {
        case .favorite: "heart.fill"
        case .unfavorite: "heart.slash.fill"
        case .archive: "archivebox.fill"
        case .unarchive: "tray.and.arrow.up.fill"
        case .delete: "trash.fill"
        }
    }

    var role: ButtonRole? {
        self == .delete ? .destructive : nil
    }

    var tint: Color {
        switch self {
        case .favorite: .red
        case .unfavorite: .gray
        case .archive, .unarchive: .blue
        case .delete: .red
        }
    }
}
