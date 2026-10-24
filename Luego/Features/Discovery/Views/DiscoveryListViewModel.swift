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
    @ObservationIgnored
    private var shuffledPostURLs: Set<URL> = []
    @ObservationIgnored
    private var lastShuffledPost: DiscoveryPost?

    private let discoveryService: DiscoveryServiceProtocol
    private let choosePost: ([DiscoveryPost]) -> DiscoveryPost?

    init(
        discoveryService: DiscoveryServiceProtocol,
        choosePost: @escaping ([DiscoveryPost]) -> DiscoveryPost? = { $0.randomElement() }
    ) {
        self.discoveryService = discoveryService
        self.choosePost = choosePost
    }

    func loadPosts() async {
        hasOpened = true
        await load(force: false)
    }

    func refresh() async {
        await load(force: true)
    }

    func canShuffle(excluding currentPost: DiscoveryPost? = nil) -> Bool {
        !hasNoFeedsOn && posts.contains { $0.url != currentPost?.url }
    }

    func randomPost(excluding currentPost: DiscoveryPost? = nil) -> DiscoveryPost? {
        guard canShuffle(excluding: currentPost) else { return nil }
        if let currentPost { shuffledPostURLs.insert(currentPost.url) }
        let availablePosts = posts.filter { $0.url != currentPost?.url }
        let previousPost = currentPost ?? lastShuffledPost
        var candidates = availablePosts.filter { !shuffledPostURLs.contains($0.url) }
        if candidates.isEmpty {
            shuffledPostURLs.removeAll()
            candidates = availablePosts.filter { $0.url != previousPost?.url }
            if candidates.isEmpty { candidates = availablePosts }
        }
        let otherDomains = candidates.filter { $0.domain != previousPost?.domain }
        guard let post = choosePost(otherDomains.isEmpty ? candidates : otherDomains) else { return nil }
        shuffledPostURLs.insert(post.url)
        lastShuffledPost = post
        return post
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
