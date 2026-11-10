import GRDB
import SwiftUI
import UIKit

struct ReaderRestorationFixture: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var container: DIContainer?
    @State private var content: FixtureContent?
    @State private var articles: [Article] = []
    @State private var selection: Article?
    @State private var viewport = ""
    @State private var scrollPhase = "idle"
    @State private var savedPositions = ""
    @State private var setupError: String?
    @State private var path: [Article] = []
    @State private var switchDuringRestoration = false
    @State private var didSwitchDuringRestoration = false
    @State private var discoveryListViewModel: DiscoveryListViewModel?
    @State private var selectedDiscoveryPost: DiscoveryPost?

    var body: some View {
        VStack(spacing: 0) {
            if let container {
                Group {
                    if horizontalSizeClass == .compact {
                        NavigationStack(path: $path) {
                            articleList
                                .navigationTitle("Saved articles")
                                .navigationDestination(for: Article.self) { article in
                                    trackViewport(
                                        ArticleReaderDestination(article: article, diContainer: container),
                                        article: article
                                    )
                                }
                        }
                    } else if ProcessInfo.processInfo.arguments.contains("--discovery-reader-fixture"), let discoveryListViewModel {
                        NavigationSplitView(columnVisibility: .constant(.all)) {
                            SidebarView(selection: .constant(.discovery))
                                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
                        } content: {
                            DiscoveryListPane(viewModel: discoveryListViewModel, selectedPost: $selectedDiscoveryPost) {
                                selectedDiscoveryPost = discoveryListViewModel.posts.last
                            }
                            .navigationSplitViewColumnWidth(min: 300, ideal: 320, max: 400)
                        } detail: {
                            DiscoveryDetailPane(
                                post: selectedDiscoveryPost,
                                canShuffle: true,
                                onShuffle: { selectedDiscoveryPost = discoveryListViewModel.posts.last }
                            )
                            .navigationSplitViewColumnWidth(min: 500, ideal: 500)
                        }
                        .appNavigationChrome()
                        .environment(container.syncObserver)
                    } else {
                        NavigationSplitView {
                            articleList
                        } detail: {
                            trackViewport(DetailPane(article: selection), article: selection)
                        }
                    }
                }
                .environment(\.diContainer, container)

                Button("Switch during restoration") {
                    switchDuringRestoration = true
                    selection = articles[1]
                }
                .accessibilityIdentifier("fixture.switchDuringRestoration")
                Text(didSwitchDuringRestoration ? "completed" : "waiting")
                    .lineLimit(1)
                    .accessibilityIdentifier("fixture.transition")
                Text(viewport)
                    .lineLimit(1)
                    .accessibilityIdentifier("fixture.viewport")
                Text(scrollPhase)
                    .lineLimit(1)
                    .accessibilityIdentifier("fixture.scrollPhase")
                Text(savedPositions)
                    .lineLimit(1)
                    .accessibilityIdentifier("fixture.savedPositions")
                Text("\(content?.completedFetches ?? 0)")
                    .lineLimit(1)
                    .accessibilityIdentifier("fixture.contentFetches")
            } else if let setupError {
                Text(setupError)
            } else {
                ProgressView()
            }
        }
        .task {
            do {
                let arguments = ProcessInfo.processInfo.arguments
                var firstPosition = arguments.contains("--reader-unread-fixture") ? 0.0 : 0.4
                if let index = arguments.firstIndex(of: "--reader-initial-position"),
                   index + 1 < arguments.count, let position = Double(arguments[index + 1]) {
                    firstPosition = position
                }
                let paragraph = String(repeating: "A fixed paragraph exercises wrapping and layout in the production reader. ", count: 5)
                var texts: [URL: String] = [:]
                let fixtures = [("a", firstPosition), ("b", 0.7)].map { name, position in
                    let url = URL(string: "https://fixture.invalid/\(name)")!
                    let text = name == "a" && arguments.contains("--reader-short-fixture")
                        ? "A short article."
                        : (1...60).map { "## Passage \(name)-\($0)\n\n\(paragraph)" }.joined(separator: "\n\n")
                    texts[url] = text
                    let isStored = !(name == "a" && arguments.contains("--reader-uncached-fixture"))
                    return Article(
                        url: url,
                        title: "Saved article \(name.uppercased())",
                        content: isStored ? text : nil,
                        readPosition: position
                    )
                }
                let content = FixtureContent(articles: texts)
                let database = try AppDatabase(DatabaseQueue())
                let container = DIContainer(database: database, contentDataSource: content)
                container.articleStore.syncEngineManager = nil
                for article in fixtures {
                    articles.append(try await container.articleStore.saveArticle(article).article)
                }
                if arguments.contains("--discovery-reader-fixture") {
                    let posts = fixtures.map { DiscoveryPost(url: $0.url, title: $0.title, publishedDate: nil) }
                    discoveryListViewModel = DiscoveryListViewModel(discoveryService: FixtureDiscoveryService(posts: posts))
                }
                self.content = content
                self.container = container
            } catch {
                setupError = error.localizedDescription
            }
        }
        .task(id: container != nil) {
            guard let container else { return }
            do {
                for try await saved in container.articleStore.observeArticles() {
                    savedPositions = articles.map { article in
                        let position = saved.first { $0.id == article.id }?.readPosition ?? -1
                        return "\(article.url.lastPathComponent)|\(position)"
                    }.joined(separator: "|")
                }
            } catch {
                if !Task.isCancelled { setupError = error.localizedDescription }
            }
        }
    }

    private var articleList: some View {
        List(articles) { article in
            Button(article.title) {
                selection = article
                if horizontalSizeClass == .compact {
                    path.append(article)
                    if ProcessInfo.processInfo.arguments.contains("--reader-reopen-while-loading") {
                        reopenAsDeepLinksDo(article)
                    }
                }
            }
            .accessibilityIdentifier("fixture.select.\(article.url.lastPathComponent)")
        }
    }

    private func reopenAsDeepLinksDo(_ article: Article) {
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            let sameArticle = Article(id: article.id, url: article.url, title: article.title, readPosition: article.readPosition)
            path.removeAll()
            path.append(sameArticle)
        }
    }

    private func trackViewport(_ content: some View, article: Article?) -> some View {
        content.onScrollPhaseChange { _, phase in
            scrollPhase = phase == .idle ? "idle" : "moving"
        }
        // Read from UIKit: onScrollGeometryChange can miss the last content-size change when the
        // reader's text finishes growing without scrolling, which would leave this probe stale.
        .background {
            let name = article?.url.lastPathComponent ?? "none"
            ScrollViewProbe(article: name) { offset, contentHeight, visibleHeight in
                viewport = "\(name)|\(offset)|\(contentHeight)|\(visibleHeight)"
                if switchDuringRestoration, name == "b", offset == 0, contentHeight > 5000 {
                    switchDuringRestoration = false
                    didSwitchDuringRestoration = true
                    selection = articles[0]
                }
            }
        }
    }
}

/// Once per frame, samples the visible scroll view covering most of this view on its own screen and
/// reports its offset beneath the bars, content height, and visible height whenever they, the
/// article, or the sampled scroll view change.
private struct ScrollViewProbe: UIViewRepresentable {
    let article: String
    let onChange: (_ offset: CGFloat, _ contentHeight: CGFloat, _ visibleHeight: CGFloat) -> Void

    func makeUIView(context: Context) -> ProbeView { ProbeView() }

    func updateUIView(_ view: ProbeView, context: Context) {
        view.article = article
        view.onChange = onChange
    }

    final class ProbeView: UIView {
        var article = ""
        var onChange: (CGFloat, CGFloat, CGFloat) -> Void = { _, _, _ in }
        private var displayLink: CADisplayLink?
        private var reported: Sample?

        private struct Sample: Equatable {
            let article: String
            let scrollView: ObjectIdentifier
            let values: [CGFloat]
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            displayLink?.invalidate()
            displayLink = nil
            guard window != nil else { return }
            let link = CADisplayLink(target: self, selector: #selector(sample))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        @objc private func sample() {
            // Search only this screen: an outgoing reader or the list sits in another view controller.
            guard let screen = owningViewController?.view,
                  let scrollView = Self.scrollView(in: screen, covering: convert(bounds, to: screen)) else { return }
            let insets = scrollView.adjustedContentInset
            // The same measures as ScrollGeometry: offset and visible height exclude the bars' insets.
            let values = [
                scrollView.contentOffset.y + insets.top,
                scrollView.contentSize.height,
                scrollView.bounds.height - insets.top - insets.bottom
            ]
            let sample = Sample(article: article, scrollView: ObjectIdentifier(scrollView), values: values)
            guard sample != reported else { return }
            reported = sample
            onChange(values[0], values[1], values[2])
        }

        private var owningViewController: UIViewController? {
            sequence(first: self as UIResponder, next: \.next).lazy.compactMap { $0 as? UIViewController }.first
        }

        private static func scrollView(in root: UIView, covering area: CGRect) -> UIScrollView? {
            var best: (view: UIScrollView, overlap: CGFloat)?
            var pending = [root]
            while let view = pending.popLast() {
                guard !view.isHidden, view.alpha > 0 else { continue }
                pending.append(contentsOf: view.subviews)
                guard let scrollView = view as? UIScrollView else { continue }
                let overlap = scrollView.convert(scrollView.bounds, to: root).intersection(area)
                let size = overlap.isNull ? 0 : overlap.width * overlap.height
                if size > (best?.overlap ?? 0) { best = (scrollView, size) }
            }
            return best?.view
        }
    }
}

@MainActor
private final class FixtureDiscoveryService: DiscoveryServiceProtocol {
    let posts: [DiscoveryPost]

    init(posts: [DiscoveryPost]) { self.posts = posts }

    func cachedPosts() async -> [DiscoveryPost]? { posts }
    func refreshPosts(force: Bool) async throws -> DiscoveryRefresh { .posts(posts) }
    func feeds() -> [DiscoveryFeed] { [] }
    func addFeed(from text: String) async throws -> DiscoveryFeed { throw DiscoveryFeedError.invalidURL }
    func addFeed(_ feed: DiscoveryFeed) throws {}
    func removeFeed(_ feed: DiscoveryFeed) {}
    func setFeed(_ feed: DiscoveryFeed, isEnabled: Bool) {}
    func feedChanges() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
}

@MainActor
@Observable
final class FixtureContent: ContentDataSourceProtocol {
    let articles: [URL: String]
    var completedFetches = 0

    init(articles: [URL: String]) {
        self.articles = articles
    }

    func validateURL(_ url: URL) async throws -> URL { url }

    func fetchMetadata(for url: URL, timeout: TimeInterval?) async throws -> ArticleMetadata {
        throw URLError(.notConnectedToInternet)
    }

    func fetchContent(for url: URL, timeout: TimeInterval?, forceRefresh: Bool, skipCache: Bool) async throws -> ArticleContent {
        try await Task.sleep(for: .seconds(1))
        guard let content = articles[url] else { throw URLError(.fileDoesNotExist) }
        completedFetches += 1
        return ArticleContent(title: url.lastPathComponent, content: content)
    }
}
