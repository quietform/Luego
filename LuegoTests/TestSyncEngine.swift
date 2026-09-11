import CloudKit

@MainActor
final class TestSyncEngine: SyncEngineManagerProtocol {
    var savedRecordIDs: [CKRecord.ID] = []

    func enqueueSave(for recordID: CKRecord.ID) {
        savedRecordIDs.append(recordID)
    }

    func refresh(mode: SyncRefreshMode) async throws -> Int { 0 }
}
