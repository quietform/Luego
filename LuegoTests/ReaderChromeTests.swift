import SwiftUI
import Testing
import UIKit

@MainActor
struct ReaderChromeTests {
    private let header = ReaderArticleHeader(
        title: "A Note",
        source: "ratik.in",
        url: URL(string: "https://ratik.in/a-note")!,
        date: nil,
        readingMinutes: nil
    )

    init() {
        LoraTestFonts.register()
    }

    @Test
    func progressStaysSilentWhileTheArticleLoads() {
        #expect(!accessibilityLabels(in: reader(markdown: nil)).contains("Reading progress"))
    }

    @Test
    func progressShowsHowFarThroughTheArticleTheReaderIs() {
        #expect(accessibilityValues(in: reader(markdown: "A short note."))["Reading progress"] == "100%")
    }

    @Test
    func openingAReaderHidesTheIPhoneTabBar() {
        let tabBar = IPhoneTabBarVisibilityController()

        _ = accessibilityLabels(in: reader(markdown: nil).environment(\.iPhoneTabBarVisibilityController, tabBar))

        #expect(!tabBar.isVisible)
    }

    @Test
    func leavingTheReaderBringsTheIPhoneTabBarBack() {
        let tabBar = IPhoneTabBarVisibilityController()
        let controller = UIHostingController(rootView: AnyView(reader(markdown: nil).environment(\.iPhoneTabBarVisibilityController, tabBar)))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        controller.view.layoutIfNeeded()

        controller.rootView = AnyView(EmptyView())
        controller.view.layoutIfNeeded()

        #expect(tabBar.isVisible)
    }

    private func reader(markdown: String?) -> some View {
        NavigationStack {
            ReaderPage(header: header, markdown: markdown)
                .readerChrome(articleURL: header.url, articleTitle: header.title, onOpenInBrowser: {}) {
                    Button("Save to Reading List", systemImage: "plus") {}
                }
        }
    }
}
