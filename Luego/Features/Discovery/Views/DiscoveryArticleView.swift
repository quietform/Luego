import SwiftUI

struct DiscoveryArticleView: View {
    @Bindable var viewModel: DiscoveryArticleViewModel
    let canShuffle: Bool
    let onShuffle: () -> Void
    @Environment(\.openURL) private var openURL
    @Environment(\.iPhoneTabBarVisibilityController) private var iPhoneTabBarVisibilityController

    var body: some View {
        Group {
            if let error = viewModel.errorMessage, !viewModel.isLoading {
                DiscoveryErrorView(
                    message: error,
                    canShuffle: canShuffle,
                    onTryAnother: onShuffle,
                    onTryAgain: { Task { await viewModel.load() } },
                    onOpenInBrowser: openInBrowser
                )
            } else {
                DiscoveryArticleContentView(
                    post: viewModel.post,
                    publishedDate: viewModel.publishedDate,
                    markdown: viewModel.article?.content
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.regularPanelBackground)
        .toolbar {
            DiscoveryToolbar(
                isSaved: viewModel.isSaved,
                canSave: viewModel.article != nil,
                canShuffle: canShuffle,
                articleURL: viewModel.post.url,
                articleTitle: viewModel.post.title,
                onShuffle: onShuffle,
                onSave: { Task { await viewModel.save() } },
                onOpenInBrowser: openInBrowser
            )
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
    let canShuffle: Bool
    let onTryAnother: () -> Void
    let onTryAgain: () -> Void
    let onOpenInBrowser: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Could not load article", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            if canShuffle {
                Button("Try Another", action: onTryAnother)
                    .buttonStyle(.borderedProminent)
            }

            Button("Try Again", action: onTryAgain)
                .buttonStyle(.bordered)

            Button("Open in Browser", action: onOpenInBrowser)
        }
    }
}
