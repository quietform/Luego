import SwiftUI
import Testing

@MainActor
struct ReaderMoreMenuTests {
    private let articleURL = URL(string: "https://example.com/article")!

    @Test
    func voiceOverHearsTheMenuAsMore() {
        let menu = ReaderMoreMenu(articleURL: articleURL, articleTitle: "Article", onOpenInBrowser: {})

        #expect(accessibilityLabels(in: menu) == ["More"])
    }

    @Test
    func readerActionsComeBeforeOpenInBrowserAndShare() {
        let saved = ReaderMoreMenu(articleURL: articleURL, articleTitle: "Article", onOpenInBrowser: {}) {
            Button("Refresh Content", systemImage: "arrow.clockwise") {}
        }
        let discovery = ReaderMoreMenu(articleURL: articleURL, articleTitle: "Article", onOpenInBrowser: {})

        #expect(accessibilityLabels(in: VStack { saved.items }) == ["Refresh Content", "Open in Browser", "Share"])
        #expect(accessibilityLabels(in: VStack { discovery.items }) == ["Open in Browser", "Share"])
    }
}
