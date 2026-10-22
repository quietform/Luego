import Foundation

enum DiscoveryFeedError: LocalizedError, Equatable {
    case invalidURL
    case noFeedFound
    case alreadyAdded
    case unreachable

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Enter a valid web address"
        case .noFeedFound:
            return "No RSS or Atom feed found at this address"
        case .alreadyAdded:
            return "This feed is already in your list"
        case .unreachable:
            return "Couldn't reach this address"
        }
    }
}

nonisolated struct DiscoveryFeed: Codable, Hashable, Identifiable, Sendable {
    static let kagiSmallWeb = DiscoveryFeed(
        url: URL(string: "https://kagi.com/api/v1/smallweb/feed/")!,
        title: "Kagi Small Web"
    )

    let url: URL
    var title: String?
    var isEnabled = true

    var id: URL { url }

    var name: String {
        title ?? url.host() ?? url.absoluteString
    }
}
