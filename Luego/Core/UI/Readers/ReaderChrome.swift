import SwiftUI

extension View {
    func readerChrome<Actions: View, MenuActions: View>(
        articleURL: URL,
        articleTitle: String,
        onOpenInBrowser: @escaping () -> Void,
        @ViewBuilder actions: () -> Actions,
        @ViewBuilder menuActions: () -> MenuActions
    ) -> some View {
        modifier(ReaderChrome(
            articleURL: articleURL,
            articleTitle: articleTitle,
            onOpenInBrowser: onOpenInBrowser,
            actions: actions(),
            menuActions: menuActions()
        ))
    }

    func readerChrome<Actions: View>(
        articleURL: URL,
        articleTitle: String,
        onOpenInBrowser: @escaping () -> Void,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        readerChrome(articleURL: articleURL, articleTitle: articleTitle, onOpenInBrowser: onOpenInBrowser, actions: actions) {
            EmptyView()
        }
    }
}

private struct ReaderChrome<Actions: View, MenuActions: View>: ViewModifier {
    let articleURL: URL
    let articleTitle: String
    let onOpenInBrowser: () -> Void
    let actions: Actions
    let menuActions: MenuActions
    @State private var progressPercent: Int?
    @Environment(\.iPhoneTabBarVisibilityController) private var iPhoneTabBarVisibilityController

    func body(content: Content) -> some View {
        content
            .onReadingProgressChange { progressPercent = $0 }
            .toolbar {
                ReaderToolbar(
                    progressPercent: progressPercent,
                    articleURL: articleURL,
                    articleTitle: articleTitle,
                    onOpenInBrowser: onOpenInBrowser,
                    actions: actions,
                    menuActions: menuActions
                )
            }
            .appNavigationChrome(.transparent)
            .onAppear { iPhoneTabBarVisibilityController?.hide() }
            .onDisappear { iPhoneTabBarVisibilityController?.show() }
    }
}

private struct ReaderToolbar<Actions: View, MenuActions: View>: ToolbarContent {
    let progressPercent: Int?
    let articleURL: URL
    let articleTitle: String
    let onOpenInBrowser: () -> Void
    let actions: Actions
    let menuActions: MenuActions

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            ReaderProgressRing(percent: progressPercent ?? 0)
                .opacity(progressPercent == nil ? 0 : 1)
                .accessibilityHidden(progressPercent == nil)
        }
        .sharedBackgroundVisibility(.hidden)

        ToolbarItemGroup(placement: .topBarTrailing) {
            actions
        }

        ToolbarSpacer(.fixed, placement: .topBarTrailing)

        ToolbarItem(placement: .topBarTrailing) {
            ReaderMoreMenu(articleURL: articleURL, articleTitle: articleTitle, onOpenInBrowser: onOpenInBrowser) {
                menuActions
            }
        }
    }
}
