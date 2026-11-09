import SwiftUI

struct DiscoveryArticleView: View {
    @Bindable var viewModel: DiscoveryArticleViewModel
    let canShuffle: Bool
    let onShuffle: () -> Void
    @Environment(\.openURL) private var openURL

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
                ReaderPage(header: header, markdown: viewModel.article?.content)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.regularPanelBackground)
        .readerChrome(
            articleURL: viewModel.post.url,
            articleTitle: viewModel.post.title,
            onOpenInBrowser: openInBrowser
        ) {
            Button(action: onShuffle) {
                Label("Next Random Article", systemImage: "die.face.5")
            }
            .disabled(!canShuffle)
            .accessibilityIdentifier("discovery.nextRandom")

            DiscoverySaveButton(isSaved: viewModel.isSaved, canSave: viewModel.article != nil).button {
                Task { await viewModel.save() }
            }
        }
        .task {
            if viewModel.article == nil {
                await viewModel.load()
            }
        }
    }

    private var header: ReaderArticleHeader {
        ReaderArticleHeader(
            title: viewModel.post.title,
            source: viewModel.post.domain,
            url: viewModel.post.url,
            date: viewModel.publishedDate.map { DateFormatters.articleDate($0) },
            readingMinutes: ReadingTime.minutes(wordCount: nil, content: viewModel.article?.content)
        )
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
