import SwiftUI

struct ReaderMoreMenu<Actions: View>: View {
    let articleURL: URL
    let articleTitle: String
    let onOpenInBrowser: () -> Void
    let actions: Actions

    init(
        articleURL: URL,
        articleTitle: String,
        onOpenInBrowser: @escaping () -> Void,
        @ViewBuilder actions: () -> Actions
    ) {
        self.articleURL = articleURL
        self.articleTitle = articleTitle
        self.onOpenInBrowser = onOpenInBrowser
        self.actions = actions()
    }

    var body: some View {
        Menu {
            items
        } label: {
            Label("More", systemImage: "ellipsis")
        }
    }

    @ViewBuilder
    var items: some View {
        actions

        Button(action: onOpenInBrowser) {
            Label("Open in Browser", systemImage: "safari")
        }

        ShareLink(item: articleURL, subject: Text(articleTitle)) {
            Label("Share", systemImage: "square.and.arrow.up")
        }
    }
}

extension ReaderMoreMenu where Actions == EmptyView {
    init(articleURL: URL, articleTitle: String, onOpenInBrowser: @escaping () -> Void) {
        self.init(articleURL: articleURL, articleTitle: articleTitle, onOpenInBrowser: onOpenInBrowser) {}
    }
}
