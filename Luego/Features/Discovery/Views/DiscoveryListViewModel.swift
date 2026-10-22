import Foundation
import Observation

@Observable
@MainActor
final class DiscoveryListViewModel {
    var posts: [DiscoveryPost] = []
    var isLoading = false
    var errorMessage: String?
    var hasNoFeedsOn = false
    @ObservationIgnored
    private var loadingRequestID = UUID()
    @ObservationIgnored
    private var hasOpened = false
    @ObservationIgnored
    private var feedChangesTask: Task<Void, Never>?

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

    func startObservingFeedChanges() {
        guard feedChangesTask == nil else { return }
        let feedChanges = discoveryService.feedChanges()
        feedChangesTask = Task { [weak self] in
            for await _ in feedChanges {
                await self?.refreshIfStale()
            }
        }
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
            let refresh = try await discoveryService.refreshPosts(force: force)
            try Task.checkCancellation()
            switch refresh {
            case .posts(let refreshedPosts):
                posts = refreshedPosts
            case .unchanged:
                break
            case .noFeedsOn:
                posts = []
            }
            hasNoFeedsOn = refresh == .noFeedsOn
            errorMessage = nil
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
            hasNoFeedsOn = false
        }
    }
}
