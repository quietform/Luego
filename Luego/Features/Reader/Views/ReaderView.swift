import SwiftUI

struct ReaderView: View {
    @Bindable var viewModel: ReaderViewModel
    @Environment(\.openURL) private var openURL
    @State private var readingPosition: ReadingPositionSession
    @State private var contentRequestID = UUID()
    @State private var refreshRequested = false

    init(viewModel: ReaderViewModel) {
        self.viewModel = viewModel
        _readingPosition = State(initialValue: ReadingPositionSession(savedPosition: viewModel.article.readPosition) { position in
            await viewModel.updateReadPosition(position)
        })
    }

    var body: some View {
        Group {
            if viewModel.isLoading || viewModel.articleContent != nil {
                ReaderPage(
                    header: header,
                    markdown: pageMarkdown,
                    restoringTo: readingPosition.restoringTo,
                    onRestored: readingPosition.pageRestored,
                    onReadingPositionChange: readingPosition.pageReported
                )
                .onDisappear(perform: readingPosition.leave)
            } else if let error = viewModel.errorMessage {
                ArticleErrorView(
                    message: error,
                    onOpenInBrowser: openInBrowser,
                    onRetry: {
                        refreshRequested = false
                        contentRequestID = UUID()
                    }
                )
            }
        }
        .readerChrome(
            articleURL: viewModel.article.url,
            articleTitle: viewModel.article.title,
            onOpenInBrowser: openInBrowser
        ) {
            ReaderListButton.favorite(for: viewModel.article.listMembership).button {
                Task { await viewModel.toggleFavorite() }
            }
            ReaderListButton.archive(for: viewModel.article.listMembership).button {
                Task { await viewModel.toggleArchive() }
            }
        } menuActions: {
            Button(action: refreshContent) {
                Label("Refresh Content", systemImage: "arrow.clockwise")
            }
        }
        .task(id: [viewModel.article.id, contentRequestID]) {
            let shouldRefresh = refreshRequested
            refreshRequested = false
            if shouldRefresh {
                await viewModel.refreshContent()
            } else {
                await viewModel.loadContent()
            }
        }
    }
}

struct ArticleErrorView: View {
    let message: String
    let onOpenInBrowser: () -> Void
    let onRetry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Failed to Load Article", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Open in Browser", action: onOpenInBrowser)
                .buttonStyle(.borderedProminent)

            Button("Retry", action: onRetry)
                .buttonStyle(.bordered)
        }
    }
}

extension ReaderView {
    private func openInBrowser() {
        openURL(viewModel.article.url)
    }

    private var pageMarkdown: String? {
        viewModel.isLoading ? nil : viewModel.articleContent
    }

    private var header: ReaderArticleHeader {
        ReaderArticleHeader(
            title: viewModel.article.title,
            source: viewModel.article.domain,
            url: viewModel.article.url,
            date: DateFormatters.articleDate(viewModel.article.publishedDate ?? viewModel.article.savedDate),
            readingMinutes: viewModel.article.readingMinutes
        )
    }

    private func refreshContent() {
        readingPosition.refresh()
        refreshRequested = true
        contentRequestID = UUID()
    }
}
