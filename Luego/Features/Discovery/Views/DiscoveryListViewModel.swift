import Foundation
import Observation

@Observable
@MainActor
final class DiscoveryListViewModel {
    var posts: [DiscoveryPost] = []
    var isLoading = false
    var errorMessage: String?
    @ObservationIgnored
    private var loadingRequestID = UUID()
    @ObservationIgnored
    private var hasOpened = false

    private let discoveryService: DiscoveryServiceProtocol

    init(discoveryService: DiscoveryServiceProtocol) {
        self.discoveryService = discoveryService
    }

    func loadPosts() async {
        hasOpened = true
        await load(force: false)
    }

    func refresh() async {
        await load(force: true)
    }

    func refreshIfStale() async {
        guard hasOpened else { return }
        await load(force: false)
    }

    private func load(force: Bool) async {
        let requestID = UUID()
        loadingRequestID = requestID
        isLoading = true
        defer {
            if loadingRequestID == requestID { isLoading = false }
        }
        if posts.isEmpty, let cachedPosts = await discoveryService.cachedPosts(), !Task.isCancelled {
            posts = cachedPosts
        }
        do {
            let refreshedPosts = try await discoveryService.refreshPosts(force: force)
            try Task.checkCancellation()
            if let refreshedPosts {
                posts = refreshedPosts
            }
            errorMessage = nil
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }
}
