import GRDB
import SwiftUI

struct ReaderRestorationFixture: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var container: DIContainer?
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
                    .accessibilityIdentifier("fixture.transition")
                Text(viewport)
                    .accessibilityIdentifier("fixture.viewport")
                Text(scrollPhase)
                    .accessibilityIdentifier("fixture.scrollPhase")
                Text(savedPositions)
                    .accessibilityIdentifier("fixture.savedPositions")
            } else if let setupError {
                Text(setupError)
            } else {
                ProgressView()
            }
        }
        .task {
            do {
                let database = try AppDatabase(DatabaseQueue())
                let container = DIContainer(database: database)
                container.articleStore.syncEngineManager = nil
                let arguments = ProcessInfo.processInfo.arguments
                var firstPosition = arguments.contains("--reader-unread-fixture") ? 0.0 : 0.4
                if let index = arguments.firstIndex(of: "--reader-initial-position"),
                   index + 1 < arguments.count, let position = Double(arguments[index + 1]) {
                    firstPosition = position
                }
                for (name, position) in [("a", firstPosition), ("b", 0.7)] {
                    let paragraph = String(repeating: "A fixed paragraph exercises wrapping and layout in the production reader. ", count: 5)
                    let content = name == "a" && arguments.contains("--reader-short-fixture")
                        ? "A short article."
                        : (1...60).map { "## Passage \(name)-\($0)\n\n\(paragraph)" }.joined(separator: "\n\n")
                    let article = Article(
                        url: URL(string: "https://fixture.invalid/\(name)")!,
                        title: "Saved article \(name.uppercased())",
                        content: content,
                        readPosition: position
                    )
                    articles.append(try await container.articleStore.saveArticle(article).article)
                }
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
