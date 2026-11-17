import Foundation
import GRDB
import SwiftUI
import Testing
import UIKit

@MainActor
struct ArticleListContentTests {
    @Test(arguments: [false, true])
    func everyLayoutListsEachArticleUnderItsAutomationIdentifier(showsSelection: Bool) throws {
        let fixture = try SharedQueueFixture()
        defer { fixture.remove() }
        let article = Article(url: URL(string: "https://example.com/article")!, title: "Saved article", content: "Summary")

        let content = ArticleListContent(
            articles: [article],
            viewModel: try makeArticleListViewModel(sharedStorage: fixture.makeQueue()),
            filter: .readingList,
            selection: showsSelection ? .constant(nil) : nil
        )
        .environment(SyncStatusObserver())

        #expect(inspectAccessibility(of: content, accessibilityIdentifiers(in:)).contains(ReadingListAccessibilityID.open(article)))
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
