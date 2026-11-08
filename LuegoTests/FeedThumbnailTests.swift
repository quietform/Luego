import Foundation
import Testing

struct FeedThumbnailTests {
    @Test
    func firstImageInTheFullContentBecomesTheThumbnail() async {
        let thumbnail = await thumbnail(ofItem: """
            <description>A short excerpt.</description>
            <content:encoded><![CDATA[<p>Intro</p><img src="https://blog.luego.test/photo.jpg" />]]></content:encoded>
            """)

        #expect(thumbnail == "https://blog.luego.test/photo.jpg")
    }

    @Test(arguments: [
        #"<media:thumbnail url="https://blog.luego.test/featured.jpg" width="640" height="480" />"#,
        #"<media:content url="https://blog.luego.test/featured.jpg" medium="image"><media:title>Featured</media:title></media:content>"#,
        #"<media:content url="https://blog.luego.test/featured.jpg" type="image/jpeg" />"#,
        #"<enclosure url="https://blog.luego.test/featured.jpg" type="image/webp" length="0" />"#
    ])
    func imageThePublisherDeclaresBecomesTheThumbnail(declaration: String) async {
        let thumbnail = await thumbnail(ofItem: "<description>A short excerpt.</description>\(declaration)")

        #expect(thumbnail == "https://blog.luego.test/featured.jpg")
    }

    @Test(arguments: [
        #"<enclosure url="https://blog.luego.test/episode.mp3" type="audio/mpeg" length="1024" />"#,
        #"<media:content url="https://blog.luego.test/clip.mp4" medium="video" />"#
    ])
    func declaredMediaThatIsNotAnImageIsIgnored(declaration: String) async {
        let thumbnail = await thumbnail(ofItem: "<description>A short excerpt.</description>\(declaration)")

        #expect(thumbnail == nil)
    }

    @Test
    func declaredImageIsPreferredOverTheFirstImageInTheFullContent() async {
        let thumbnail = await thumbnail(ofItem: """
            <content:encoded><![CDATA[<img src="https://blog.luego.test/inline.jpg" />]]></content:encoded>
            <media:content url="https://blog.luego.test/featured.jpg" medium="image" />
            """)

        #expect(thumbnail == "https://blog.luego.test/featured.jpg")
    }

    @Test
    func imageInTheSummaryIsPreferredOverADeclaredImage() async {
        let thumbnail = await thumbnail(ofItem: """
            <description>&lt;img src="https://blog.luego.test/full-size.jpg" /&gt;</description>
            <media:thumbnail url="https://blog.luego.test/s72-c/small.jpg" width="72" height="72" />
            """)

        #expect(thumbnail == "https://blog.luego.test/full-size.jpg")
    }

    @Test(arguments: [
        #"<media:content url="https://0.gravatar.com/avatar/abc123?s=96&amp;d=identicon" medium="image"><media:title type="html">author</media:title></media:content>"#,
        #"<description>&lt;img src="https://secure.gravatar.com/avatar/abc123?s=96" /&gt;</description>"#
    ])
    func authorAvatarIsNotUsedAsTheThumbnail(avatar: String) async {
        let thumbnail = await thumbnail(ofItem: """
            \(avatar)
            <media:content url="https://blog.luego.test/featured.jpg" medium="image" />
            """)

        #expect(thumbnail == "https://blog.luego.test/featured.jpg")
    }

    @Test
    func relativeImageAddressIsResolvedAgainstThePost() async {
        let thumbnail = await thumbnail(ofItem: """
            <content:encoded><![CDATA[<img src="/images/photo.jpg" />]]></content:encoded>
            """)

        #expect(thumbnail == "https://blog.luego.test/images/photo.jpg")
    }

    private func thumbnail(ofItem item: String) async -> String? {
        let feed = """
            <rss xmlns:content="http://purl.org/rss/1.0/modules/content/" xmlns:media="http://search.yahoo.com/mrss/"><channel>
            <item><title>Post</title><link>https://blog.luego.test/posts/post</link>\(item)</item>
            </channel></rss>
            """
        return await GenericRSSDataSource().parse(Data(feed.utf8)).first?.imageURL?.absoluteString
    }
}
