import Foundation
import Testing

struct DiscoveryLegacyStorageTests {
    @Test
    func removingLegacyStorageLeavesOtherPreferencesAlone() throws {
        let suiteName = "DiscoveryLegacyStorageTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let legacyKeys = [
            "smallweb_articles_v2",
            "smallweb_cache_timestamp_v2",
            "smallweb_shown_articles",
            "smallweb_shown_river_posts",
            "blogroll_articles_v1",
            "blogroll_cache_timestamp_v1",
            "blogroll_shown_blogs",
            "discovery_selected_source"
        ]
        for key in legacyKeys {
            defaults.set(Data("cached".utf8), forKey: key)
        }
        defaults.set(true, forKey: "unrelated_preference")

        DiscoveryLegacyStorage.remove(from: defaults)

        #expect(legacyKeys.filter { defaults.object(forKey: $0) != nil }.isEmpty)
        #expect(defaults.bool(forKey: "unrelated_preference"))
    }
}
