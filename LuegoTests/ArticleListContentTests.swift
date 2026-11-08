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

        #expect(accessibilityIdentifiers(in: content).contains(ReadingListAccessibilityID.open(article)))
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

    private func accessibilityIdentifiers(in view: some View) -> Set<String> {
        let controller = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        controller.view.layoutIfNeeded()
        return accessibilityIdentifiers(in: controller.view)
    }

    private func accessibilityIdentifiers(in element: NSObject) -> Set<String> {
        let identifierKey = "accessibilityIdentifier"
        let identifier = element.responds(to: NSSelectorFromString(identifierKey)) ? element.value(forKey: identifierKey) as? String : nil
        let own = identifier.map { Set([$0]) } ?? []
        let children = (element.accessibilityElements as? [NSObject])
            ?? (0..<max(element.accessibilityElementCount(), 0)).compactMap { element.accessibilityElement(at: $0) as? NSObject }
        let views = (element as? UIView)?.subviews ?? []
        return (children + views).reduce(own) { $0.union(accessibilityIdentifiers(in: $1)) }
    }
}
