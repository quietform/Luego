import SwiftUI

struct ArticleListContent: View {
    let articles: [Article]
    let viewModel: ArticleListViewModel
    let filter: ArticleFilter
    var selection: Binding<Article?>?
    var onDiscover: () -> Void = {}
    var shouldAnimateEmptyStateOnFirstAppearance = false
    var onEmptyStateAnimationConsumed: () -> Void = {}
    @Environment(SyncStatusObserver.self) private var syncStatusObserver

    private var restoreStatusText: String? {
        guard filter == .readingList, syncStatusObserver.state == .restoring else { return nil }
        return "Restoring articles from iCloud."
    }

    var body: some View {
        Group {
            if articles.isEmpty {
                emptyState
            } else {
                ArticleList(
                    articles: articles,
                    viewModel: viewModel,
                    filter: filter,
                    selection: selection,
                    onRefresh: { await viewModel.refreshArticles() }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        RefreshableEmptyStateContainer(onRefresh: { await viewModel.refreshArticles() }) {
            ArticleListEmptyState(
                onDiscover: onDiscover,
                filter: filter,
                restoreStatusText: restoreStatusText,
                shouldAnimateCopyOnFirstAppearance: filter == .readingList && shouldAnimateEmptyStateOnFirstAppearance,
                onCopyAnimationConsumed: onEmptyStateAnimationConsumed
            )
        }
    }
}

struct ArticleList: View {
    let articles: [Article]
    let viewModel: ArticleListViewModel
    let filter: ArticleFilter
    let selection: Binding<Article?>?
    let onRefresh: () async -> Void

    private var swipeActions: ArticleSwipeActions {
        ArticleSwipeActions(filter: filter, viewModel: viewModel, onDelete: deselect)
    }

    var body: some View {
        List {
            ForEach(articles) { article in
                row(for: article)
                    .accessibilityIdentifier(ReadingListAccessibilityID.open(article))
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        swipeActions.favoriteButton(for: article)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        swipeActions.archiveButton(for: article)
                        swipeActions.deleteButton(for: article)
                    }
            }
        }
        .id(filter)
        .accessibilityIdentifier(ReadingListAccessibilityID.list(filter))
        .scrollContentBackground(.hidden)
        .refreshable {
            await onRefresh()
        }
    }

    @ViewBuilder
    private func row(for article: Article) -> some View {
        if let selection {
            let isSelected = selection.wrappedValue?.id == article.id
            Button {
                selection.wrappedValue = article
            } label: {
                ArticleRowView(article: article, isSelected: isSelected)
            }
            .buttonStyle(.plain)
            .listRowSeparator(.hidden)
            .listRowBackground(RowSelectionBackground(isSelected: isSelected))
        } else {
            NavigationLink(value: article) {
                ArticleRowView(article: article)
            }
        }
    }

    private func deselect(_ article: Article) {
        if selection?.wrappedValue?.id == article.id {
            selection?.wrappedValue = nil
        }
    }
}
