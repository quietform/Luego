import Foundation
import Testing

struct FeedTextTests {
    @Test
    func ampersandInACDATATitleIsShownAsWritten() async {
        let post = await firstPost(ofItem: "<title><![CDATA[An Essay & Some Film Scans]]></title>")

        #expect(post?.title == "An Essay & Some Film Scans")
    }

    @Test
    func feedWithAStrayAmpersandStillParses() async {
        let post = await firstPost(ofItem: "<title>Salt & Pepper</title>")

        #expect(post?.title == "Salt & Pepper")
    }

    @Test
    func namedHTMLEntityInTheSummaryIsDecoded() async {
        let post = await firstPost(ofItem: "<description><![CDATA[<p>Last month&rsquo;s edition</p>]]></description>")

        #expect(post?.excerpt == "Last month’s edition")
    }

    @Test(arguments: [
        ("&lsquo;Hi&rsquo;", "‘Hi’"),
        ("&ldquo;Hi&rdquo;", "“Hi”"),
        ("Wait&hellip;", "Wait…"),
        ("One&mdash;two&ndash;three", "One—two–three"),
        ("Caf&eacute; &copy; &euro;5", "Café © €5")
    ])
    func commonNamedEntityInTheSummaryIsDecoded(html: String, text: String) async {
        let post = await firstPost(ofItem: "<description><![CDATA[<p>\(html)</p>]]></description>")

        #expect(post?.excerpt == text)
    }

    @Test
    func unknownEntityInTheSummaryIsLeftAsWritten() async {
        let post = await firstPost(ofItem: "<description><![CDATA[<p>A &madeup; entity</p>]]></description>")

        #expect(post?.excerpt == "A &madeup; entity")
    }

    @Test
    func escapedEntityInTheSummaryIsDecodedOnlyOnce() async {
        let post = await firstPost(ofItem: "<description><![CDATA[<p>Write &amp;lt;p&amp;gt;, &amp;quot; and &amp;rsquo;</p>]]></description>")

        #expect(post?.excerpt == "Write &lt;p&gt;, &quot; and &rsquo;")
    }

    private func firstPost(ofItem item: String) async -> BlogPostEntry? {
        let feed = """
            <rss><channel>
            <item><link>https://blog.luego.test/posts/post</link>\(item)</item>
            </channel></rss>
            """
        return await GenericRSSDataSource().parse(Data(feed.utf8)).first
    }
}
