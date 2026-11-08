import Testing

@MainActor
struct DiscoveryToolbarTests {
    @Test(arguments: [
        (false, false, DiscoverySaveButton(title: "Save to Reading List", systemImage: "plus", isEnabled: false)),
        (false, true, DiscoverySaveButton(title: "Save to Reading List", systemImage: "plus", isEnabled: true)),
        (true, true, DiscoverySaveButton(title: "Saved to Reading List", systemImage: "checkmark", isEnabled: false))
    ])
    func saveButtonWaitsForContentAndConfirmsOnceSaved(isSaved: Bool, canSave: Bool, expected: DiscoverySaveButton) {
        #expect(DiscoverySaveButton(isSaved: isSaved, canSave: canSave) == expected)
    }
}
