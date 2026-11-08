import SwiftUI

struct ArticleListPane: View {
    let viewModel: ArticleListViewModel
    let filter: ArticleFilter
    @Binding var selectedArticle: Article?
    let onDiscover: () -> Void
    let shouldAnimateEmptyStateOnFirstAppearance: Bool
    let onEmptyStateAnimationConsumed: () -> Void

    private var filteredArticles: [Article] {
        viewModel.filteredArticles(for: filter)
    }

    private var filteredArticleIDs: [UUID] {
        filteredArticles.map(\.id)
    }

    var body: some View {
        ArticleListContent(
            articles: filteredArticles,
            viewModel: viewModel,
            filter: filter,
            selection: $selectedArticle,
            onDiscover: onDiscover,
            shouldAnimateEmptyStateOnFirstAppearance: shouldAnimateEmptyStateOnFirstAppearance,
            onEmptyStateAnimationConsumed: onEmptyStateAnimationConsumed
        )
        .background(Color.regularPanelBackground)
        .appNavigationStyle(.contentLargeTitle)
        .navigationTitle(filter.navigationTitle)
        .articleListActions(viewModel: viewModel)
        .onChange(of: filteredArticleIDs) { _, newIDs in
            guard let selectedArticle else { return }
            if !newIDs.contains(selectedArticle.id) {
                self.selectedArticle = nil
            }
        }
    }
}
