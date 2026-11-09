import GRDB
import SwiftUI

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
        .onScrollGeometryChange(for: String.self) { geometry in
            let offset = geometry.contentOffset.y + geometry.contentInsets.top
            return "\(offset)|\(geometry.contentSize.height)|\(geometry.containerSize.height)"
        } action: { _, geometry in
            viewport = "\(article?.url.lastPathComponent ?? "none")|\(geometry)"
            let fields = geometry.split(separator: "|").compactMap { Double($0) }
            if switchDuringRestoration, article?.url.lastPathComponent == "b",
               fields.count == 3, fields[0] == 0, fields[1] > 5000 {
                switchDuringRestoration = false
                didSwitchDuringRestoration = true
                selection = articles[0]
            }
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
