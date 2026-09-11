import Foundation
import GRDB
import Testing

@MainActor
struct SharedStorageContentionTests {
    @Test(arguments: [0.2, 1.5])
    func sharingHandlesContentionWithoutBlockingMainActor(lockDuration: TimeInterval) async throws {
        let fixture = try SharedQueueFixture()
        defer { fixture.remove() }
        let queue = fixture.makeQueue()
        _ = try queue.getSharedURLs()
        let writer = try DatabaseQueue(path: fixture.directory.appendingPathComponent("queue.sqlite").path)
        let (lockEvents, lockSignal) = AsyncStream<Void>.makeStream()
        let competingWrite = Task {
            defer { lockSignal.finish() }
            try await writer.write { db in
                try db.execute(sql: "UPDATE sharedURLs SET timestamp = timestamp")
                lockSignal.yield(())
                Thread.sleep(forTimeInterval: lockDuration)
            }
        }
        var events = lockEvents.makeAsyncIterator()
        _ = await events.next()
        var mainActorWasResponsive = false
        let mainActorWork = Task { @MainActor in
            mainActorWasResponsive = true
        }
        var saveError: String?

        do {
            try await queue.saveSharedURL(URL(string: "https://example.com/concurrent")!)
        } catch {
            saveError = error.localizedDescription
        }
        let progressedWhileSaving = mainActorWasResponsive
        await mainActorWork.value
        try await competingWrite.value

        #expect(progressedWhileSaving)
        if lockDuration < 1 {
            #expect(saveError == nil)
            #expect(try queue.getSharedURLs().count == 1)
        } else {
            #expect(saveError?.contains("database is locked") == true)
            #expect(try queue.getSharedURLs().isEmpty)
        }
    }

    @Test
    func cancelledShareIsNotQueued() async throws {
        let fixture = try SharedQueueFixture()
        defer { fixture.remove() }
        let queue = fixture.makeQueue()
        let save = Task {
            try await queue.saveSharedURL(URL(string: "https://example.com/cancelled")!)
        }
        save.cancel()

        await #expect(throws: CancellationError.self) {
            try await save.value
        }
        #expect(try queue.getSharedURLs().isEmpty)
    }
}
