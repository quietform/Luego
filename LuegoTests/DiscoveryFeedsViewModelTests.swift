import Foundation
import Testing

@MainActor
struct DiscoveryFeedsViewModelTests {
    private let blog = DiscoveryFeed(url: URL(string: "https://blog.luego.test/feed.xml")!)
    private let service = ListedDiscoveryService()

    @Test
    func addedFeedIsListedAndTheFieldClears() async {
        service.addFeedResult = .success(blog)
        let viewModel = DiscoveryFeedsViewModel(discoveryService: service)
        viewModel.urlText = "blog.luego.test"

        await viewModel.addFeed()

        #expect(service.addedFeedTexts == ["blog.luego.test"])
        #expect(viewModel.feeds == [blog])
        #expect(viewModel.urlText.isEmpty)
        #expect(viewModel.errorMessage == nil)
    }

    @Test
    func failedAddExplainsWhyAndKeepsTheText() async {
        service.addFeedResult = .failure(DiscoveryFeedError.noFeedFound)
        let viewModel = DiscoveryFeedsViewModel(discoveryService: service)
        viewModel.urlText = "plain.luego.test"

        await viewModel.addFeed()

        #expect(viewModel.errorMessage == "No RSS or Atom feed found at this address")
        #expect(viewModel.urlText == "plain.luego.test")
        #expect(viewModel.feeds.isEmpty)
    }

    @Test
    func lookingUpTheFeedShowsProgress() async {
        service.addFeedResult = .success(blog)
        service.suspendsFetches = true
        let viewModel = DiscoveryFeedsViewModel(discoveryService: service)
        viewModel.urlText = "blog.luego.test"
        var started = service.started.stream.makeAsyncIterator()

        let add = Task { await viewModel.addFeed() }
        _ = await started.next()
        #expect(viewModel.isAdding)

        service.resumeFetch()
        await add.value
        #expect(!viewModel.isAdding)
    }

    @Test
    func switchingAFeedOffShowsItOff() {
        service.savedFeeds = [blog]
        let viewModel = DiscoveryFeedsViewModel(discoveryService: service)

        viewModel.setFeed(blog, isEnabled: false)

        #expect(viewModel.feeds.map(\.isEnabled) == [false])
    }

    @Test
    func deletedKagiSmallWebCanBeAddedBack() {
        service.savedFeeds = [blog]
        let viewModel = DiscoveryFeedsViewModel(discoveryService: service)

        #expect(viewModel.canAddKagiSmallWeb)
        viewModel.addKagiSmallWeb()

        #expect(viewModel.feeds == [blog, .kagiSmallWeb])
        #expect(!viewModel.canAddKagiSmallWeb)
    }

    @Test
    func feedsCannotBeClosedWhileAFeedIsBeingLookedUp() async {
        service.addFeedResult = .success(blog)
        service.suspendsFetches = true
        let viewModel = DiscoveryFeedsViewModel(discoveryService: service)
        viewModel.urlText = "blog.luego.test"
        var started = service.started.stream.makeAsyncIterator()
        #expect(viewModel.canClose)

        let add = Task { await viewModel.addFeed() }
        _ = await started.next()
        #expect(!viewModel.canClose)

        service.resumeFetch()
        await add.value
        #expect(viewModel.canClose)
    }

    @Test
    func openingListsYourSavedFeeds() {
        service.savedFeeds = [blog]

        #expect(DiscoveryFeedsViewModel(discoveryService: service).feeds == [blog])
    }

    @Test
    func removedFeedLeavesTheList() {
        service.savedFeeds = [blog]
        let viewModel = DiscoveryFeedsViewModel(discoveryService: service)

        viewModel.removeFeed(blog)

        #expect(viewModel.feeds.isEmpty)
        #expect(service.savedFeeds.isEmpty)
    }
}
