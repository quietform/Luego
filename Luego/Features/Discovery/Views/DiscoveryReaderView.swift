import SwiftUI

struct DiscoveryReaderView: View {
    @Bindable var viewModel: DiscoveryViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    DiscoveryLoadingContentView(viewModel: viewModel)
                } else if let article = viewModel.ephemeralArticle {
                    DiscoveryArticleContentView(article: article)
                } else if let error = viewModel.errorMessage {
                    DiscoveryErrorView(
                        message: error,
                        onTryAnother: { Task { await viewModel.loadAnotherArticle() } }
                    )
                } else {
                    DiscoveryLoadingContentView(viewModel: viewModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.regularPanelBackground)
            .safeAreaInset(edge: .bottom) {
                if viewModel.ephemeralArticle != nil && !viewModel.isLoading {
                    HStack {
                        Spacer()
                        DiscoveryBottomBar(
                            isSaved: viewModel.isSaved,
                            onShuffle: { Task { await viewModel.loadAnotherArticle() } },
                            onSave: { Task { await viewModel.saveToReadingList() } }
                        )
                    }
                    .padding(.trailing)
                }
            }
            .navigationTitle("Discover")
            .appNavigationStyle(.inlineTransparent)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }

                if let article = viewModel.ephemeralArticle {
                    ToolbarItem(placement: .primaryAction) {
                        DiscoveryToolbarMenu(
                            articleURL: article.url,
                            articleTitle: article.title,
                            onOpenInBrowser: openInBrowser
                        )
                    }
                }
            }
            .task {
                if viewModel.ephemeralArticle == nil {
                    await viewModel.fetchRandomArticle()
                }
            }
        }
        .tint(Color.regularSelectionInk)
    }

    private func openInBrowser() {
        guard let article = viewModel.ephemeralArticle else { return }
        openURL(article.url)
    }
}

struct DiscoveryLoadingContentView: View {
    @Bindable var viewModel: DiscoveryViewModel

    var body: some View {
        switch viewModel.activeSource {
        case .kagiSmallWeb:
            KagiSmallWebLoadingView(
                pendingURL: viewModel.pendingArticleURL,
                gifName: viewModel.currentLoadingGif,
                loadingText: viewModel.currentLoadingText
            )
        case .blogroll, .surpriseMe, .none:
            BlogrollLoadingView(
                pendingURL: viewModel.pendingArticleURL,
                loadingText: viewModel.currentLoadingText
            )
        }
    }
}

struct KagiSmallWebLoadingView: View {
    var pendingURL: URL?
    var gifName: String
    var loadingText: String
    @State private var isVisible = false

    var body: some View {
        VStack {
            Spacer()

            GIFImageView(gifName: gifName)
                .frame(width: 88, height: 31)

            Spacer()

            VStack(spacing: 16) {
                Text(loadingText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let domain = pendingURL?.host() {
                    LoadingDomainChip(domain: domain)
                        .transition(.opacity.combined(with: .scale))
                }
            }
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.regularPanelBackground)
        .animation(.easeInOut(duration: 0.3), value: pendingURL)
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
    }
}

struct LoadingDomainChip: View {
    let domain: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "globe")
                .foregroundStyle(.secondary)
                .font(.caption)

            Text(domain)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.1))
        .clipShape(Capsule())
        .shimmer()
    }
}

struct DiscoveryErrorView: View {
    let message: String
    let onTryAnother: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Could not load article", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Another", action: onTryAnother)
                .buttonStyle(.borderedProminent)
        }
    }
}

struct DiscoveryBottomBar: View {
    let isSaved: Bool
    let onShuffle: () -> Void
    let onSave: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            DiscoveryBottomBarButton(
                systemImage: "die.face.5",
                action: onShuffle
            )

            Divider()
                .frame(height: 24)
                .overlay(Color.barAccentInk.opacity(0.35))

            DiscoveryBottomBarButton(
                systemImage: isSaved ? "checkmark" : "plus",
                action: onSave
            )
            .disabled(isSaved)
        }
        .glassEffect(.regular.interactive().tint(Color.barAccentFill))
    }
}

struct DiscoveryBottomBarButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(Color.barAccentInk)
                .frame(width: 44, height: 44, alignment: .center)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
