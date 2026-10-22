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
    enum PostSelection: String, Codable, Hashable, Sendable {
        case latestFive
        case all
    }

    private static let kagiSmallWebURL = URL(string: "https://kagi.com/api/v1/smallweb/feed/")!

    static let kagiSmallWeb = DiscoveryFeed(
        url: kagiSmallWebURL,
        title: "Kagi Small Web"
    )

    let url: URL
    var title: String?
    var isEnabled = true
    var postSelection: PostSelection

    init(url: URL, title: String? = nil, isEnabled: Bool = true, postSelection: PostSelection? = nil) {
        self.url = url
        self.title = title
        self.isEnabled = isEnabled
        self.postSelection = postSelection ?? (url == Self.kagiSmallWebURL ? .all : .latestFive)
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            url: try values.decode(URL.self, forKey: .url),
            title: try values.decodeIfPresent(String.self, forKey: .title),
            isEnabled: try values.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true,
            postSelection: try values.decodeIfPresent(PostSelection.self, forKey: .postSelection)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case url, title, isEnabled, postSelection
    }

    var id: URL { url }

    var name: String {
        title ?? url.host() ?? url.absoluteString
    }
}
