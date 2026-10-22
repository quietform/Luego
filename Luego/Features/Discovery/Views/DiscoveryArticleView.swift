import SwiftUI

struct DiscoveryArticleView: View {
    @Bindable var viewModel: DiscoveryArticleViewModel
    @Environment(\.openURL) private var openURL
    @Environment(\.iPhoneTabBarVisibilityController) private var iPhoneTabBarVisibilityController
    @State private var loadingGif = KagiLoadingGifRotator.next()

    var body: some View {
        Group {
            if let article = viewModel.article {
                DiscoveryArticleContentView(article: article)
            } else if let error = viewModel.errorMessage, !viewModel.isLoading {
                DiscoveryErrorView(
                    message: error,
                    onTryAgain: { Task { await viewModel.load() } },
                    onOpenInBrowser: openInBrowser
                )
            } else {
                KagiSmallWebLoadingView(
                    pendingURL: viewModel.post.url,
                    gifName: loadingGif,
                    loadingText: "Opening article..."
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.regularPanelBackground)
        .safeAreaInset(edge: .bottom) {
            if viewModel.article != nil {
                HStack {
                    Spacer()
                    DiscoveryBottomBar(
                        isSaved: viewModel.isSaved,
                        onSave: { Task { await viewModel.save() } }
                    )
                }
                .padding(.trailing)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                DiscoveryToolbarMenu(
                    articleURL: viewModel.post.url,
                    articleTitle: viewModel.post.title,
                    onOpenInBrowser: openInBrowser
                )
            }
        }
        #if os(iOS)
        .appNavigationChrome(.transparent)
        #endif
        .task {
            if viewModel.article == nil {
                await viewModel.load()
            }
        }
        .onAppear {
            iPhoneTabBarVisibilityController?.hide()
        }
        .onDisappear {
            iPhoneTabBarVisibilityController?.show()
        }
    }

    private func openInBrowser() {
        openURL(viewModel.post.url)
    }
}

struct DiscoveryErrorView: View {
    let message: String
    let onTryAgain: () -> Void
    let onOpenInBrowser: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Could not load article", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again", action: onTryAgain)
                .buttonStyle(.borderedProminent)

            Button("Open in Browser", action: onOpenInBrowser)
        }
    }
}

struct DiscoveryBottomBar: View {
    let isSaved: Bool
    let onSave: () -> Void

    var body: some View {
        Button(action: onSave) {
            Image(systemName: isSaved ? "checkmark" : "plus")
                .font(.title2)
                .foregroundStyle(Color.barAccentInk)
                .frame(width: 44, height: 44, alignment: .center)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isSaved)
        .accessibilityLabel(isSaved ? "Saved to Reading List" : "Save to Reading List")
        .glassEffect(.regular.interactive().tint(Color.barAccentFill))
    }
}

struct DiscoveryToolbarMenu: View {
    let articleURL: URL
    let articleTitle: String
    let onOpenInBrowser: () -> Void

    var body: some View {
        Menu {
            ShareLink(item: articleURL, subject: Text(articleTitle)) {
                Label("Share", systemImage: "square.and.arrow.up")
            }

            Button(action: onOpenInBrowser) {
                Label("Open in Browser", systemImage: "safari")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }
}
