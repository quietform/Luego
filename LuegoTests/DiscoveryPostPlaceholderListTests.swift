import Testing

@MainActor
struct DiscoveryPostPlaceholderListTests {
    @Test(arguments: [false, true])
    func voiceOverHearsThatPostsAreLoading(showsSelection: Bool) {
        #expect(accessibilityLabels(in: DiscoveryPostPlaceholderList(showsSelection: showsSelection)) == ["Loading posts"])
    }
}
