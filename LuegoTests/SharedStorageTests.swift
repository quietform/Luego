import Foundation
import Testing

@MainActor
struct SharedStorageTests {
    @Test
    func migratesLegacyQueueOnce() throws {
        let fixture = try SharedQueueFixture()
        defer { fixture.remove() }
        let legacyData = Data(#"[{"url":"https://example.com/legacy","timestamp":0}]"#.utf8)
        fixture.defaults.set(legacyData, forKey: "sharedURLs")

        let items = try fixture.makeQueue().getSharedURLs()
        let reopenedItems = try fixture.makeQueue().getSharedURLs()

        #expect(items.count == 1)
        #expect(items.first?.url.absoluteString == "https://example.com/legacy")
        #expect(items.first?.timestamp == Date(timeIntervalSinceReferenceDate: 0))
        #expect(reopenedItems.map(\.id) == items.map(\.id))
        #expect(fixture.defaults.data(forKey: "sharedURLs") == nil)
    }

    @Test
    func corruptLegacyDataIsPreservedForRetry() throws {
        let fixture = try SharedQueueFixture()
        defer { fixture.remove() }
        let corruptData = Data("invalid JSON".utf8)
        fixture.defaults.set(corruptData, forKey: "sharedURLs")
        let queue = fixture.makeQueue()

        #expect(throws: SharedStorageError.self) { try queue.getSharedURLs() }
        #expect(fixture.defaults.data(forKey: "sharedURLs") == corruptData)

        fixture.defaults.set(Data(#"[{"url":"https://example.com/recovered","timestamp":0}]"#.utf8), forKey: "sharedURLs")
        #expect(try queue.getSharedURLs().count == 1)
    }

    @Test
    func acknowledgingAnItemKeepsALaterShareOfTheSameURL() async throws {
        let fixture = try SharedQueueFixture()
        defer { fixture.remove() }
        let appQueue = fixture.makeQueue()
        let extensionQueue = fixture.makeQueue()
        let url = URL(string: "https://example.com/article")!
        try await appQueue.saveSharedURL(url)
        let first = try #require(appQueue.getSharedURLs().first)
        try await extensionQueue.saveSharedURL(url)

        try appQueue.acknowledgeSharedURL(id: first.id)
        try appQueue.acknowledgeSharedURL(id: first.id)

        let remaining = try fixture.makeQueue().getSharedURLs()
        #expect(remaining.count == 1)
        #expect(remaining.first?.url == url)
        #expect(remaining.first?.id != first.id)
    }

    @Test
    func acknowledgedItemsStayRemovedAfterReopening() async throws {
        let fixture = try SharedQueueFixture()
        defer { fixture.remove() }
        let queue = fixture.makeQueue()
        try await queue.saveSharedURL(URL(string: "https://example.com/article")!)
        let item = try #require(queue.getSharedURLs().first)

        try queue.acknowledgeSharedURL(id: item.id)

        #expect(try fixture.makeQueue().getSharedURLs().isEmpty)
    }

    @Test
    func unavailableAppGroupDoesNotSilentlyAcceptItems() async {
        let queue = SharedStorage(databaseURL: nil, legacyDefaults: nil)

        await #expect(throws: SharedStorageError.self) {
            try await queue.saveSharedURL(URL(string: "https://example.com/article")!)
        }
    }
}

@MainActor
struct SharedQueueFixture {
    let directory: URL
    let suiteName: String
    let defaults: UserDefaults

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "LuegoTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    func makeQueue() -> SharedStorage {
        SharedStorage(databaseURL: directory.appendingPathComponent("queue.sqlite"), legacyDefaults: defaults)
    }

    func remove() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }
}
