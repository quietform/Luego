import Foundation
import Testing

@MainActor
struct DiscoveryPostSourceTests {
    private let river = URL(string: "https://river.luego.test/feed")!
    private var riverFeed: DiscoveryFeed { DiscoveryFeed(url: river, postSelection: .all) }
    private let blog = DiscoveryFeed(url: URL(string: "https://blog.luego.test/feed.xml")!)
    private let feeds = StubFeedPosts()

    @Test(arguments: [
        ("https://river.luego.test/feed", "latestFive", 5),
        ("https://aggregator.luego.test/feed", "all", 8)
    ])
    func feedSelectionControlsHowManyPostsAreListed(address: String, selection: String, expectedCount: Int) async throws {
        let data = Data("{\"url\":\"\(address)\",\"isEnabled\":true,\"postSelection\":\"\(selection)\"}".utf8)
        let feed = try JSONDecoder().decode(DiscoveryFeed.self, from: data)
        feeds.posts[feed.url] = (1...8).map { .dated("post-\($0)", hour: $0) }

        let posts = try await makeSource().fetchPosts(from: [feed])

        #expect(posts.count == expectedCount)
        #expect(posts.first?.title == "post-8")
    }

    @Test
    func postsFromYourFeedsAreMergedWithTheRiverNewestFirst() async throws {
        feeds.posts[river] = [.dated("river-new", hour: 3), .dated("river-old", hour: 1)]
        feeds.posts[blog.url] = [.dated("blog", hour: 2)]

        let posts = try await makeSource().fetchPosts(from: [riverFeed, blog])

        #expect(posts.map(\.title) == ["river-new", "blog", "river-old"])
    }

    @Test
    func eachOfYourFeedsAddsOnlyItsFiveNewestPosts() async throws {
        feeds.posts[river] = []
        feeds.posts[blog.url] = (1...8).map { .dated("blog-\($0)", hour: $0) }

        let posts = try await makeSource().fetchPosts(from: [riverFeed, blog])

        #expect(posts.map(\.title) == ["blog-8", "blog-7", "blog-6", "blog-5", "blog-4"])
    }

    @Test
    func anUnreachableFeedIsSkipped() async throws {
        let broken = DiscoveryFeed(url: URL(string: "https://broken.luego.test/feed")!)
        feeds.posts[river] = [.dated("river", hour: 1)]
        feeds.posts[blog.url] = [.dated("blog", hour: 2)]

        let posts = try await makeSource().fetchPosts(from: [riverFeed, broken, blog])

        #expect(posts.map(\.title) == ["blog", "river"])
    }

    @Test
    func yourFeedsStillListWhenTheRiverIsUnavailable() async throws {
        feeds.posts[blog.url] = [.dated("blog", hour: 2)]

        let posts = try await makeSource().fetchPosts(from: [riverFeed, blog])

        #expect(posts.map(\.title) == ["blog"])
    }

    @Test
    func nothingToListReportsWhyTheRiverFailed() async {
        await #expect(throws: SmallWebError.self) {
            try await makeSource().fetchPosts(from: [riverFeed, blog])
        }
    }

    @Test
    func aPostInBothTheRiverAndYourFeedIsListedOnce() async throws {
        feeds.posts[river] = [.dated("shared", hour: 2), .dated("river", hour: 1)]
        feeds.posts[blog.url] = [.dated("shared", hour: 2)]

        let posts = try await makeSource().fetchPosts(from: [riverFeed, blog])

        #expect(posts.map(\.title) == ["shared", "river"])
    }

    @Test
    func withoutKagiOnlyYourFeedsAreFetched() async throws {
        feeds.posts[river] = [.dated("river", hour: 3)]
        feeds.posts[blog.url] = [.dated("blog", hour: 2)]

        let posts = try await makeSource().fetchPosts(from: [blog])

        #expect(posts.map(\.title) == ["blog"])
    }

    @Test
    func aFeedSwitchedOffIsLeftOut() async throws {
        var switchedOff = riverFeed
        switchedOff.isEnabled = false
        feeds.posts[river] = [.dated("river", hour: 3)]
        feeds.posts[blog.url] = [.dated("blog", hour: 2)]

        let posts = try await makeSource().fetchPosts(from: [switchedOff, blog])

        #expect(posts.map(\.title) == ["blog"])
    }

    private func makeSource() -> DiscoveryPostSource {
        DiscoveryPostSource(feedPosts: feeds)
    }
}

extension DiscoveryPost {
    static func dated(_ title: String, hour: Int) -> DiscoveryPost {
        DiscoveryPost(
            url: URL(string: "https://posts.luego.test/\(title)")!,
            title: title,
            publishedDate: Date(timeIntervalSince1970: TimeInterval(hour * 3_600))
        )
    }
}

@MainActor
final class StubFeedPosts: FeedPostsDataSourceProtocol {
    var posts: [URL: [DiscoveryPost]] = [:]

    func posts(from feedURL: URL) async throws -> [DiscoveryPost] {
        guard let posts = posts[feedURL] else { throw SmallWebError.fetchFailed(URLError(.cannotConnectToHost)) }
        return posts
    }

    func resolveFeedURL(from url: URL) async throws -> URL {
        throw DiscoveryFeedError.noFeedFound
    }
}
