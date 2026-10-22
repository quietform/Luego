import Foundation

@MainActor
protocol DiscoveryFeedStoreProtocol: Sendable {
    func feeds() -> [DiscoveryFeed]
    func save(_ feeds: [DiscoveryFeed])
}

@MainActor
final class DiscoveryFeedStore: DiscoveryFeedStoreProtocol {
    private let defaults: UserDefaults
    private let key = "discovery_feeds_v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func feeds() -> [DiscoveryFeed] {
        guard let data = defaults.data(forKey: key),
              let stored = try? JSONDecoder().decode([StoredFeed].self, from: data) else {
            return [.kagiSmallWeb]
        }
        return stored.map(\.feed)
    }

    func save(_ feeds: [DiscoveryFeed]) {
        defaults.set(try? JSONEncoder().encode(feeds.map(StoredFeed.init)), forKey: key)
    }
}

private nonisolated struct StoredFeed: Codable {
    let url: URL
    let title: String?
    let isEnabled: Bool?
    let postSelection: DiscoveryFeed.PostSelection?

    init(_ feed: DiscoveryFeed) {
        url = feed.url
        title = feed.title
        isEnabled = feed.isEnabled
        postSelection = feed.postSelection
    }

    var feed: DiscoveryFeed {
        DiscoveryFeed(url: url, title: title, isEnabled: isEnabled ?? true, postSelection: postSelection)
    }
}
