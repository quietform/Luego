import CloudKit

@MainActor
final class TestSyncEngine: SyncEngineManagerProtocol {
    var savedRecordIDs: [CKRecord.ID] = []
    var onForegroundCatchUp: () async -> Void = {}

    func performForegroundCatchUp() async {
        await onForegroundCatchUp()
    }

    func enqueueSave(for recordID: CKRecord.ID) {
        savedRecordIDs.append(recordID)
    }

    func refresh(mode: SyncRefreshMode) async throws -> Int { 0 }
}
