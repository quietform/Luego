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
                let fixtures = [("a", firstPosition), ("b", 0.7)].map { name, position in
                    let content = name == "a" && arguments.contains("--reader-short-fixture")
                        ? "A short article."
                        : (1...60).map { "## Passage \(name)-\($0)\n\n\(paragraph)" }.joined(separator: "\n\n")
                    return Article(
                        url: URL(string: "https://fixture.invalid/\(name)")!,
                        title: "Saved article \(name.uppercased())",
                        content: content,
                        readPosition: position
                    )
                }
                let content = FixtureContent(articles: Dictionary(uniqueKeysWithValues: fixtures.map { ($0.url, $0.content ?? "") }))
                let database = try AppDatabase(DatabaseQueue())
                let container = DIContainer(database: database, contentDataSource: content)
                container.articleStore.syncEngineManager = nil
                for article in fixtures {
                    articles.append(try await container.articleStore.saveArticle(article).article)
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
                if horizontalSizeClass == .compact { path.append(article) }
            }
            .accessibilityIdentifier("fixture.select.\(article.url.lastPathComponent)")
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
