import Foundation
import Observation

@Observable
@MainActor
final class DiscoveryFeedsViewModel {
    var feeds: [DiscoveryFeed] = []
    var urlText = ""
    var errorMessage: String?
    var isAdding = false

    private let discoveryService: DiscoveryServiceProtocol

    init(discoveryService: DiscoveryServiceProtocol) {
        self.discoveryService = discoveryService
        feeds = discoveryService.feeds()
    }

    func setFeed(_ feed: DiscoveryFeed, isEnabled: Bool) {
        discoveryService.setFeed(feed, isEnabled: isEnabled)
        feeds = discoveryService.feeds()
    }

    var canClose: Bool { !isAdding }

    var canAddKagiSmallWeb: Bool {
        !feeds.contains { $0.id == DiscoveryFeed.kagiSmallWeb.id }
    }

    func addKagiSmallWeb() {
        try? discoveryService.addFeed(.kagiSmallWeb)
        feeds = discoveryService.feeds()
    }

    func removeFeed(_ feed: DiscoveryFeed) {
        discoveryService.removeFeed(feed)
        feeds = discoveryService.feeds()
    }

    func addFeed() async {
        isAdding = true
        defer { isAdding = false }
        do {
            _ = try await discoveryService.addFeed(from: urlText)
            feeds = discoveryService.feeds()
            urlText = ""
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
