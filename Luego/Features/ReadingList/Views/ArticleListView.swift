import SwiftUI

struct ArticleListView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let viewModel: ArticleListViewModel
    let filter: ArticleFilter
    let shouldAnimateEmptyStateOnFirstAppearance: Bool
    let onEmptyStateAnimationConsumed: () -> Void
    let onDiscover: () -> Void

    init(
        viewModel: ArticleListViewModel,
        filter: ArticleFilter,
        shouldAnimateEmptyStateOnFirstAppearance: Bool = false,
        onEmptyStateAnimationConsumed: @escaping () -> Void = {},
        onDiscover: @escaping () -> Void = {}
    ) {
        self.viewModel = viewModel
        self.filter = filter
        self.shouldAnimateEmptyStateOnFirstAppearance = shouldAnimateEmptyStateOnFirstAppearance
        self.onEmptyStateAnimationConsumed = onEmptyStateAnimationConsumed
        self.onDiscover = onDiscover
    }

    var body: some View {
        ArticleListContent(
            articles: viewModel.filteredArticles(for: filter),
            viewModel: viewModel,
            filter: filter,
            onDiscover: onDiscover,
            shouldAnimateEmptyStateOnFirstAppearance: shouldAnimateEmptyStateOnFirstAppearance,
            onEmptyStateAnimationConsumed: onEmptyStateAnimationConsumed
        )
        .background(Color.appBackground)
        .navigationTitle(navigationTitle)
        .appNavigationStyle(horizontalSizeClass == .compact ? .largeTransparent : .largePanel)
        .articleListActions(viewModel: viewModel)
    }

    private var navigationTitle: String {
        if horizontalSizeClass == .compact {
            return filter.navigationTitle
        }

        return filter.title
    }
}

struct ArticleReaderDestination: View {
    let article: Article
    let diContainer: DIContainer?

    var body: some View {
        if let container = diContainer {
            let readerViewModel = container.makeReaderViewModel(article: article)
            ReaderView(viewModel: readerViewModel)
        }
    }
}
