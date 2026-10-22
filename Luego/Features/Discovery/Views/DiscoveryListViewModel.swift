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

    private let discoveryService: DiscoveryServiceProtocol

    init(discoveryService: DiscoveryServiceProtocol) {
        self.discoveryService = discoveryService
    }

    func loadPosts() async {
        let requestID = UUID()
        loadingRequestID = requestID
        isLoading = true
        defer {
            if loadingRequestID == requestID { isLoading = false }
        }
        do {
            let fetchedPosts = try await discoveryService.fetchPosts()
            try Task.checkCancellation()
            posts = fetchedPosts
            errorMessage = nil
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }
}
