import CloudKit

enum SyncRefreshMode {
    case smart
    case fullRepair
}

@MainActor
protocol SyncEngineManagerProtocol: AnyObject, Sendable {
    func performForegroundCatchUp() async
    func enqueueSave(for recordID: CKRecord.ID)
    func refresh(mode: SyncRefreshMode) async throws -> Int
}
