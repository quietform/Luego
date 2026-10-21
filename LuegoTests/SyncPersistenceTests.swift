import Foundation
import GRDB
import Testing

@MainActor
struct SyncPersistenceTests {
    @Test
    func concurrentStateUpdatesPreserveUnrelatedFields() async throws {
        let database = try AppDatabase(DatabaseQueue())
        let timestamp = Date(timeIntervalSinceReferenceDate: 123)
        let timestampUpdate = Task {
            try await database.updateSyncEngineStatePayload { $0.lastSyncTime = timestamp }
        }
        let stateUpdates = (0..<8).map { _ in
            Task {
                try await database.updateSyncEngineStatePayload { $0.stateSerialization = nil }
            }
        }
        try await timestampUpdate.value
        for update in stateUpdates { try await update.value }

        #expect(try await database.syncEngineStatePayload()?.lastSyncTime == timestamp)
    }
}
