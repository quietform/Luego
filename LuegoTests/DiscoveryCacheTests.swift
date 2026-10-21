import Foundation
import Testing

@MainActor
struct DiscoveryCacheTests {
    @Test(arguments: ["kagi", "blogroll"])
    func cachedFeedCodingKeepsMainActorResponsive(source: String) async throws {
        let field = source == "kagi" ? "articleUrl" : "feedUrl"
        let data = Data("[{\"title\":\"Blog\",\"\(field)\":\"https://example.com/feed\",\"htmlUrl\":\"https://example.com\"}]".utf8)
        var mainActorRan = false
        let heartbeat = Task { @MainActor in mainActorRan = true }
        let entries: [SmallWebArticleEntry]
        let encoded: Data?
        if source == "kagi" {
            entries = await KagiSmallWebDataSource.decodeCachedArticles(data)
            encoded = await KagiSmallWebDataSource.encodeCachedArticles(entries)
        } else {
            entries = await BlogrollDataSource.decodeCachedBlogs(data)
            encoded = await BlogrollDataSource.encodeCachedBlogs(entries)
        }
        let progressedWhileCoding = mainActorRan
        await heartbeat.value

        #expect(progressedWhileCoding)
        #expect(entries.count == 1)
        #expect(entries.first?.title == "Blog")
        #expect(entries.first?.articleUrl.absoluteString == "https://example.com/feed")
        #expect(entries.first?.htmlUrl?.absoluteString == "https://example.com")
        let roundTrip = try JSONSerialization.jsonObject(with: #require(encoded)) as? [[String: String]]
        #expect(roundTrip?.first?[field] == "https://example.com/feed")
    }
}
