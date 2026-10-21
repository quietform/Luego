import Foundation
import Testing

@MainActor
struct DiscoveryParsingTests {
    @Test(arguments: ["rss", "opml", "blogroll"])
    func parsingFinishesInCancelledTask(source: String) async {
        let parsing = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            switch source {
            case "rss":
                return await GenericRSSDataSource().parse(Data("<rss><channel><item><title>Article</title><link>https://example.com</link></item></channel></rss>".utf8)).map(\.title)
            case "opml":
                return await OPMLDataSource().parse(Data("<opml><body><outline title=\"Article\" xmlUrl=\"https://example.com/feed\"/></body></opml>".utf8)).map(\.title)
            default:
                return await BlogrollRSSDataSource().parse(Data("<rss><channel><item><title>Article</title><link>https://example.com</link><description><![CDATA[<a href='{https://example.com/feed}'>Feed</a>]]></description></item></channel></rss>".utf8)).map(\.title)
            }
        }
        #expect(await parsing.value == ["Article"])
    }

    @Test(arguments: ["rss", "opml", "blogroll"])
    func parsingKeepsMainActorResponsive(source: String) async {
        var mainActorRan = false
        let heartbeat = Task { @MainActor in mainActorRan = true }
        let urls: [URL]
        switch source {
        case "rss":
            let item = "<item><title>Example & title</title><link>https://example.com/post</link><pubDate>Fri, 16 Oct 2026 12:00:00 +0000</pubDate></item>"
            let data = Data(("<rss><channel>" + String(repeating: item, count: 100) + "</channel></rss>").utf8)
            let posts = await GenericRSSDataSource().parse(data)
            #expect(posts.first?.title == "Example & title")
            #expect(posts.first?.publishedDate != nil)
            urls = posts.map(\.postURL)
        case "opml":
            let item = "<outline title=\"Example & title\" xmlUrl=\"https://example.com/post\"/>"
            let data = Data(("<opml><body>" + String(repeating: item, count: 100) + "</body></opml>").utf8)
            let posts = await OPMLDataSource().parse(data)
            #expect(posts.first?.title == "Example & title")
            urls = posts.map(\.articleUrl)
        default:
            let item = "<item><title>Example & title</title><link>https://example.com</link><description><![CDATA[<a href='{https://example.com/post}'>Feed</a>]]></description></item>"
            let data = Data(("<rss><channel>" + String(repeating: item, count: 100) + "</channel></rss>").utf8)
            let posts = await BlogrollRSSDataSource().parse(data)
            #expect(posts.first?.title == "Example & title")
            urls = posts.map(\.articleUrl)
        }
        let progressedWhileParsing = mainActorRan
        await heartbeat.value

        #expect(progressedWhileParsing)
        #expect(urls.count == 100)
        #expect(urls.first?.absoluteString == "https://example.com/post")
    }
}
