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
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                DiscoveryBottomBar(
                    isSaved: viewModel.isSaved,
                    canSave: viewModel.article != nil,
                    canShuffle: canShuffle,
                    onShuffle: onShuffle,
                    onSave: { Task { await viewModel.save() } }
                )
            }
            .padding(.trailing)
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

struct DiscoveryBottomBar: View {
    let isSaved: Bool
    let canSave: Bool
    let canShuffle: Bool
    let onShuffle: () -> Void
    let onSave: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onShuffle) {
                Image(systemName: "die.face.5")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(!canShuffle)
            .accessibilityLabel("Next Random Article")
            .accessibilityIdentifier("discovery.nextRandom")

            Divider()
                .frame(height: 24)
                .overlay(Color.barAccentInk.opacity(0.35))

            Button(action: onSave) {
                Image(systemName: isSaved ? "checkmark" : "plus")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(!canSave || isSaved)
            .accessibilityLabel(isSaved ? "Saved to Reading List" : "Save to Reading List")
            .accessibilityIdentifier("discovery.save")
        }
        .font(.title2)
        .foregroundStyle(Color.barAccentInk)
        .buttonStyle(.plain)
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
