import Foundation
import Testing

@MainActor
struct DiscoveryFeedStoreTests {
    private let defaults = UserDefaults(suiteName: "DiscoveryFeedStoreTests-\(UUID())")!

    @Test
    func kagiSmallWebIsTheFirstFeed() {
        #expect(DiscoveryFeedStore(defaults: defaults).feeds() == [.kagiSmallWeb])
    }

    @Test
    func savedFeedsAreThereOnNextLaunch() {
        let feeds = [
            DiscoveryFeed(url: URL(string: "https://one.luego.test/feed")!),
            DiscoveryFeed(url: URL(string: "https://two.luego.test/atom.xml")!)
        ]

        DiscoveryFeedStore(defaults: defaults).save(feeds)

        #expect(DiscoveryFeedStore(defaults: defaults).feeds() == feeds)
    }

    @Test
    func feedsSavedBeforeFeedsHadTitlesOrSwitchesStillLoad() {
        defaults.set(Data(#"[{"url":"https:\/\/one.luego.test\/feed"}]"#.utf8), forKey: "discovery_feeds_v1")

        let feeds = DiscoveryFeedStore(defaults: defaults).feeds()

        #expect(feeds == [DiscoveryFeed(url: URL(string: "https://one.luego.test/feed")!)])
    }
}
