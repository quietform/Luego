import CloudKit
import Foundation

nonisolated struct SyncEngineStatePayload: Codable, Sendable {
    var stateSerialization: CKSyncEngine.State.Serialization?
    var lastSyncTime: Date?
}
