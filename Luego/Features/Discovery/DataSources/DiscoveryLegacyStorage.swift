import Foundation

enum DiscoveryLegacyStorage {
    private static let keys = [
        "smallweb_articles_v2",
        "smallweb_cache_timestamp_v2",
        "smallweb_shown_articles",
        "smallweb_shown_river_posts",
        "blogroll_articles_v1",
        "blogroll_cache_timestamp_v1",
        "blogroll_shown_blogs",
        "discovery_selected_source"
    ]

    static func remove(from defaults: UserDefaults) {
        for key in keys {
            defaults.removeObject(forKey: key)
        }
    }
}
