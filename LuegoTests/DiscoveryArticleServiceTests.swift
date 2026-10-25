import Foundation
import Testing

@MainActor
struct DiscoveryArticleServiceTests {
    @Test
    func articleLoadsWithoutFeedStorage() async throws {
        let parsedImage = URL(string: "https://article.luego.test/parsed.jpg")!
        let publishedDate = Date(timeIntervalSince1970: 1_000)
        let content = ArticleLoadingContentSource(response: ArticleContent(
            title: "Parsed title",
            thumbnailURL: parsedImage,
            content: "Article body",
            publishedDate: publishedDate
        ))
        let post = DiscoveryPost(
            url: URL(string: "https://article.luego.test/post")!,
            title: "Feed title",
            publishedDate: nil,
            thumbnailURL: URL(string: "https://article.luego.test/feed.jpg")!
        )
        let service = DiscoveryArticleService(contentDataSource: content)

        let article = try await service.fetchArticle(for: post)

        #expect(content.requestedURLs == [post.url])
        #expect(content.timeout == 10)
        #expect(content.forceRefresh == false)
        #expect(content.skipCache == true)
        #expect(article.url == post.url)
        #expect(article.title == post.title)
        #expect(article.content == "Article body")
        #expect(article.thumbnailURL == parsedImage)
        #expect(article.publishedDate == publishedDate)
        #expect(article.feedTitle == post.domain)
    }

    @Test
    func articleKeepsTheDateTheFeedListed() async throws {
        let feedDate = Date(timeIntervalSince1970: 1_000)
        let content = ArticleLoadingContentSource(response: ArticleContent(
            title: "Parsed title",
            content: "Article body",
            publishedDate: Date(timeIntervalSince1970: 2_000)
        ))
        let post = DiscoveryPost(
            url: URL(string: "https://article.luego.test/post")!,
            title: "Feed title",
            publishedDate: feedDate
        )
        let service = DiscoveryArticleService(contentDataSource: content)

        let article = try await service.fetchArticle(for: post)

        #expect(article.publishedDate == feedDate)
    }

    @Test
    func futureFeedDateFallsBackToTheArticlesOwnDate() async throws {
        let parsedDate = Date(timeIntervalSince1970: 2_000)
        let content = ArticleLoadingContentSource(response: ArticleContent(
            title: "Parsed title",
            content: "Article body",
            publishedDate: parsedDate
        ))
        let post = DiscoveryPost(
            url: URL(string: "https://article.luego.test/post")!,
            title: "Feed title",
            publishedDate: .distantFuture
        )
        let service = DiscoveryArticleService(contentDataSource: content)

        let article = try await service.fetchArticle(for: post)

        #expect(article.publishedDate == parsedDate)
    }
}

@MainActor
private final class ArticleLoadingContentSource: ContentDataSourceProtocol {
    let response: ArticleContent
    var requestedURLs: [URL] = []
    var timeout: TimeInterval?
    var forceRefresh: Bool?
    var skipCache: Bool?

    init(response: ArticleContent) {
        self.response = response
    }

    func validateURL(_ url: URL) async throws -> URL { url }

    func fetchMetadata(for url: URL, timeout: TimeInterval?) async throws -> ArticleMetadata {
        throw URLError(.unsupportedURL)
    }

    func fetchContent(for url: URL, timeout: TimeInterval?, forceRefresh: Bool, skipCache: Bool) async throws -> ArticleContent {
        requestedURLs.append(url)
        self.timeout = timeout
        self.forceRefresh = forceRefresh
        self.skipCache = skipCache
        return response
    }
}
