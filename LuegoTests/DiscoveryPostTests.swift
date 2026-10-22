import Foundation
import Testing

struct DiscoveryPostTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func pastPublishedDateIsShown() {
        let published = now.addingTimeInterval(-3600)
        let post = DiscoveryPost(url: URL(string: "https://river.luego.test/post")!, title: "Post", publishedDate: published)

        #expect(post.displayDate(relativeTo: now) == published)
    }

    @Test
    func futurePublishedDateIsHidden() {
        let post = DiscoveryPost(url: URL(string: "https://river.luego.test/post")!, title: "Post", publishedDate: now.addingTimeInterval(3600))

        #expect(post.displayDate(relativeTo: now) == nil)
    }
}
