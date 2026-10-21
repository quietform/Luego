import Foundation
import Testing

@MainActor
struct SeenItemTrackerTests {
    @Test
    func acceptedHistoryUpdatePersistsInCancelledTask() async {
        let key = "LuegoTests.seen.\(UUID())"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let tracker = SeenItemTracker(storageKey: key)
        let update = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await tracker.markAsSeen("seen")
        }
        await update.value

        let reopened = SeenItemTracker(storageKey: key)
        #expect(await reopened.filterUnseen(["seen", "new"]) { $0 } == ["new"])
        #expect(tracker.seenCount == 1)
    }

    @Test
    func filteringRestoresSeenHistoryWithoutBlockingMainActor() async {
        let key = "LuegoTests.seen.\(UUID())"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let first = SeenItemTracker(storageKey: key)
        await first.markAsSeen("seen")
        let reopened = SeenItemTracker(storageKey: key)
        var mainActorRan = false
        let heartbeat = Task { @MainActor in mainActorRan = true }

        let unseen = await reopened.filterUnseen(["seen", "new"]) { $0 }
        let progressedWhileFiltering = mainActorRan
        await heartbeat.value

        #expect(progressedWhileFiltering)
        #expect(unseen == ["new"])
        #expect(reopened.seenCount == 1)
        #expect(await reopened.resetIfNeeded(totalCount: 2, unseenCount: 0))
        #expect(await reopened.filterUnseen(["seen", "new"]) { $0 } == ["seen", "new"])
        reopened.clear()
        #expect(UserDefaults.standard.data(forKey: key) == nil)
    }
}
