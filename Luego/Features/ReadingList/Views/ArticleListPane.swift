import SwiftUI

struct ArticleListPane: View {
    let viewModel: ArticleListViewModel
    let filter: ArticleFilter
    @Binding var selectedArticle: Article?
    let onDiscover: () -> Void
    let shouldAnimateEmptyStateOnFirstAppearance: Bool
    let onEmptyStateAnimationConsumed: () -> Void
    @Environment(\.diContainer) private var diContainer
    @Environment(SyncStatusObserver.self) private var syncStatusObserver
    @State private var showingSettings = false

    private var filteredArticles: [Article] {
        viewModel.filteredArticles(for: filter)
    }

    private var filteredArticleIDs: [UUID] {
        filteredArticles.map(\.id)
    }

    private var restoreStatusText: String? {
        guard filter == .readingList, syncStatusObserver.state == .restoring else { return nil }
        return "Restoring articles from iCloud."
    }

    var body: some View {
        AddArticlePresenter(viewModel: viewModel) { addArticleButton in
            Group {
                if filteredArticles.isEmpty {
                    emptyState(for: viewModel)
                } else {
                    SelectableArticleList(
                        articles: filteredArticles,
                        viewModel: viewModel,
                        selection: $selectedArticle,
                        filter: filter,
                        onRefresh: { await viewModel.refreshArticles() }
                    )
                }
            }
            .background(Color.regularPanelBackground)
            .appNavigationStyle(.contentLargeTitle)
            .navigationTitle(filter.navigationTitle)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if filter == .readingList {
                        Button(action: onDiscover) {
                            Image(systemName: "die.face.5")
                        }
                        .accessibilityIdentifier(ReadingListAccessibilityID.discoverButton)
                        .accessibilityLabel("Inspire Me")
                    }

                    addArticleButton

                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityIdentifier(ReadingListAccessibilityID.settingsButton)
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            if let container = diContainer {
                NavigationStack {
                    SettingsView(viewModel: container.makeSettingsViewModel())
                }
            }
        }
        .onChange(of: filteredArticleIDs) { _, newIDs in
            guard let selectedArticle else { return }
            if !newIDs.contains(selectedArticle.id) {
                self.selectedArticle = nil
            }
        }
    }

    @ViewBuilder
    private func emptyState(for viewModel: ArticleListViewModel) -> some View {
        let content = ArticleListEmptyState(
            onDiscover: onDiscover,
            filter: filter,
            restoreStatusText: restoreStatusText,
            shouldAnimateCopyOnFirstAppearance: filter == .readingList && shouldAnimateEmptyStateOnFirstAppearance,
            onCopyAnimationConsumed: onEmptyStateAnimationConsumed
        )

        RefreshableEmptyStateContainer(onRefresh: { await viewModel.refreshArticles() }) {
            content
        }
    }
}

struct SelectableArticleList: View {
    let articles: [Article]
    let viewModel: ArticleListViewModel
    @Binding var selection: Article?
    let filter: ArticleFilter
    let onRefresh: () async -> Void

    private var swipeActions: ArticleSwipeActions {
        ArticleSwipeActions(
            filter: filter,
            viewModel: viewModel,
            onDelete: { article in
                if selection?.id == article.id {
                    selection = nil
                }
            }
        )
    }

    var body: some View {
        List {
            ForEach(articles) { article in
                Button {
                    selection = article
                } label: {
                    ArticleRowView(article: article, isSelected: selection?.id == article.id)
                }
                .accessibilityIdentifier(ReadingListAccessibilityID.open(article))
                .buttonStyle(.plain)
                .listRowSeparator(.hidden)
                .listRowBackground(selectionBackground(isSelected: selection?.id == article.id))
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
        .background(Color.regularPanelBackground)
        .refreshable {
            await onRefresh()
        }
    }

    private func selectionBackground(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(isSelected ? Color.regularSelectionFill : Color.clear)
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
    }
}
