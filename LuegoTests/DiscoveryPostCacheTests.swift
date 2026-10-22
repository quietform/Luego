import Foundation
import Testing

@MainActor
struct DiscoveryPostCacheTests {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DiscoveryPostCacheTests-\(UUID())")

    @Test
    func savedSnapshotReadsBackUnchanged() async {
        let cache = DiscoveryPostCache(directory: directory)
        let snapshot = DiscoveryPostSnapshot(posts: [.first, .withPreview], fetchedAt: Date(timeIntervalSince1970: 1_000))

        await cache.save(snapshot)

        #expect(await cache.load() == snapshot)
    }

    @Test
    func snapshotSavedBeforePostSelectionStillLoads() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = Data(#"{"formatVersion":2,"snapshot":{"posts":[{"url":"https://river.luego.test/first","title":"First"}],"fetchedAt":0,"feeds":[{"url":"https://kagi.com/api/v1/smallweb/feed/","title":"Kagi Small Web","isEnabled":true},{"url":"https://blog.luego.test/feed","isEnabled":true}]}}"#.utf8)
        try data.write(to: directory.appendingPathComponent("river.json"))

        let snapshot = await DiscoveryPostCache(directory: directory).load()

        #expect(snapshot?.posts == [.first])
        #expect(snapshot?.feeds == [.kagiSmallWeb, DiscoveryFeed(url: URL(string: "https://blog.luego.test/feed")!)])
    }

    @Test
    func snapshotFromAnOlderFormatIsIgnored() async {
        let older = DiscoveryPostCache(directory: directory, formatVersion: 1)
        await older.save(DiscoveryPostSnapshot(posts: [.first], fetchedAt: .now))

        let newer = DiscoveryPostCache(directory: directory, formatVersion: 2)

        #expect(await newer.load() == nil)
    }
}

extension DiscoveryPost {
    static let withPreview = DiscoveryPost(
        url: URL(string: "https://river.luego.test/preview")!,
        title: "Preview",
        publishedDate: Date(timeIntervalSince1970: 500),
        excerpt: "A short excerpt",
        thumbnailURL: URL(string: "https://river.luego.test/preview.jpg")
    )
}
