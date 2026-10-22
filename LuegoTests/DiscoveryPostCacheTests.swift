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
