import GRDB
import SwiftUI
import Testing
import UIKit

@MainActor
struct ArticleListEmptyStateTests {
    @Test(arguments: ArticleFilter.allCases.filter { $0 != .discovery })
    func emptyStateReadsItsMessageAsOneElementWithoutDecorativeArtwork(filter: ArticleFilter) {
        let elements = accessibleElements(in: ArticleListEmptyState(onDiscover: {}, filter: filter))

        #expect(!elements.contains { $0.isImage })
        let message = elements.first?.label ?? ""
        #expect(([filter.emptyStateTitle] + filter.emptyStateLines).allSatisfy(message.contains))
    }

    @Test
    func readingListAddArticleButtonUsesTheEnvironmentsAddArticleAction() {
        var addArticleCount = 0
        let emptyState = ArticleListEmptyState(onDiscover: {}, filter: .readingList)
            .environment(\.addArticle, AddArticleAction { addArticleCount += 1 })

        let activated = inspectAccessibility(of: emptyState) { root in
            accessibleObject(labeled: "Add Article", in: root)?.accessibilityActivate() ?? false
        }

        #expect(activated)
        #expect(addArticleCount == 1)
    }

    @Test
    func launchRevealHoldsBackTheActionsUntilTheMessageHasAppeared() {
        let emptyState = ArticleListEmptyState(
            onDiscover: {},
            filter: .readingList,
            shouldAnimateCopyOnFirstAppearance: true
        )
        .environment(\.addArticle, AddArticleAction {})

        let labels = accessibilityLabels(in: emptyState)

        #expect(!labels.contains("Add Article"))
        #expect(!labels.contains("Inspire Me"))
    }

    @Test
    func contentInsideArticleListActionsCanOpenTheAddArticlePopover() async throws {
        let fixture = try SharedQueueFixture()
        defer { fixture.remove() }
        let viewModel = try makeArticleListViewModel(sharedStorage: fixture.makeQueue())
        let host = PageHost(
            NavigationStack {
                AddArticleRequester()
                    .articleListActions(viewModel: viewModel)
            }
        )
        defer { host.close() }

        await host.settle { presentsAddArticlePopover(host) }
        #expect(presentsAddArticlePopover(host))
    }

    /// The add button's popover is the only popover `articleListActions` presents.
    private func presentsAddArticlePopover(_ host: PageHost) -> Bool {
        host.view.window?.rootViewController?.presentedViewController?.modalPresentationStyle == .popover
    }

    private func makeArticleListViewModel(sharedStorage: SharedStorage) throws -> ArticleListViewModel {
        let sync = TestSyncEngine()
        let store = GRDBArticleStore(database: try AppDatabase(DatabaseQueue()))
        let articles = ArticleService(articleStore: store, contentDataSource: TestContentDataSource(), syncEngineManager: sync)
        return ArticleListViewModel(
            articleService: articles,
            sharingService: SharingService(articleService: articles, sharedStorage: sharedStorage),
            syncEngineManager: sync
        )
    }
}

/// Stands in for any list content that asks to add an article, such as the empty state's button.
private struct AddArticleRequester: View {
    @Environment(\.addArticle) private var addArticle

    var body: some View {
        Color.clear
            .task { addArticle?() }
    }
}
