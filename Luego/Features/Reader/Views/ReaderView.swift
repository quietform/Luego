import SwiftUI

struct ReaderView: View {
    @Bindable var viewModel: ReaderViewModel
    @Environment(\.openURL) private var openURL
    @State private var scrollPosition: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var viewHeight: CGFloat = 0
    @State private var saveTask: Task<Void, Error>?
    @State private var restorationTask: Task<Void, Never>?
    @State private var isDocumentPrepared = false
    @State private var hasRestoredPosition = false
    @State private var lastSavedPosition: Double = 0
    @State private var contentRequestID = UUID()
    @State private var refreshRequested = false

    var body: some View {
        Group {
            if viewModel.isLoading {
                ReaderPage(header: header, markdown: nil)
            } else if let content = viewModel.articleContent {
                ReaderPage(header: header, markdown: content, onPreparationChanged: handlePreparationChanged) { scroll in
                    ScrollPositionTracker(
                        contentHeight: $contentHeight,
                        viewHeight: $viewHeight,
                        scrollPosition: $scrollPosition,
                        viewportHeight: scroll.viewportHeight,
                        readPosition: viewModel.article.readPosition,
                        onPositionChange: updateReadPosition,
                        onAppear: { restoreScrollPosition(scrollProxy: scroll.proxy) }
                    )
                }
                .onDisappear(perform: handleDisappear)
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

struct ScrollPositionTracker: View {
    @Binding var contentHeight: CGFloat
    @Binding var viewHeight: CGFloat
    @Binding var scrollPosition: CGFloat
    let viewportHeight: CGFloat
    let readPosition: Double
    let onPositionChange: () -> Void
    let onAppear: () -> Void

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .onChange(of: geo.frame(in: ReaderPageScroll.coordinateSpace).minY) { oldValue, newValue in
                    contentHeight = geo.size.height
                    viewHeight = viewportHeight
                    scrollPosition = max(0, -newValue)
                    onPositionChange()
                }
                .onChange(of: geo.size.height) { _, height in
                    contentHeight = height
                    onAppear()
                    onPositionChange()
                }
                .onChange(of: viewportHeight) { _, height in
                    viewHeight = height
                    onAppear()
                    onPositionChange()
                }
                .onAppear {
                    contentHeight = geo.size.height
                    viewHeight = viewportHeight
                    onAppear()
                }
                .overlay(alignment: .top) {
                    Color.clear
                        .frame(height: 1)
                        .id("readPosition")
                        .frame(height: geo.size.height * CGFloat(min(1, max(0, readPosition))), alignment: .bottom)
                }
        }
    }
}

extension ReaderView {
    private func openInBrowser() {
        openURL(viewModel.article.url)
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

    private func handlePreparationChanged(_ prepared: Bool, scroll: ReaderPageScroll) {
        isDocumentPrepared = prepared
        if prepared { restoreScrollPosition(scrollProxy: scroll.proxy) }
    }

    private func updateReadPosition() {
        saveTask?.cancel()
        guard isDocumentPrepared, restorationTask == nil else { return }
        let newPosition = calculateReadPosition()
        guard abs(newPosition - lastSavedPosition) > 0.01 else { return }

        saveTask = Task {
            try await Task.sleep(for: .seconds(2))

            await viewModel.updateReadPosition(newPosition, documentPrepared: isDocumentPrepared)
            try Task.checkCancellation()
            lastSavedPosition = newPosition
        }
    }

    private func restoreScrollPosition(scrollProxy: ScrollViewProxy) {
        guard isDocumentPrepared, !hasRestoredPosition, restorationTask == nil else { return }
        guard viewModel.article.readPosition > 0 else { return }
        guard contentHeight > 0 && viewHeight > 0 else { return }

        let savedPosition = viewModel.article.readPosition
        lastSavedPosition = savedPosition

        restorationTask = Task {
            do {
                try await Task.sleep(nanoseconds: 100_000_000)
            } catch { return }
            guard isDocumentPrepared else {
                restorationTask = nil
                return
            }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.3)) {
                    scrollProxy.scrollTo("readPosition", anchor: .bottom)
                }
                hasRestoredPosition = true
                restorationTask = nil
            }
        }
    }

    private func handleDisappear() {
        saveTask?.cancel()
        if let restorationTask {
            restorationTask.cancel()
            self.restorationTask = nil
            return
        }
        let position = calculateReadPosition()
        Task {
            await viewModel.updateReadPosition(position, documentPrepared: isDocumentPrepared)
        }
    }

    private func calculateReadPosition() -> Double {
        guard contentHeight > 0 else { return 0.0 }

        let visibleBottomPosition = scrollPosition + viewHeight
        let rawPosition = visibleBottomPosition / contentHeight
        let clampedPosition = min(1.0, max(0.0, rawPosition))

        return clampedPosition >= 0.95 ? 1.0 : clampedPosition
    }

    private func refreshContent() {
        refreshRequested = true
        contentRequestID = UUID()
    }
}
