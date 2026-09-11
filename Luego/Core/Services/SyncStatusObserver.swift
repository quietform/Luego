import Foundation
import Observation

enum SyncState: Equatable {
    case idle
    case syncing
    case restoring
    case success
    case error(message: String, needsSignIn: Bool)
}

@Observable
@MainActor
final class SyncStatusObserver {
    private(set) var state: SyncState = .idle
    private(set) var lastSyncTime: Date?
    private(set) var accountStatusDescription: String?
    private(set) var cloudKitDiagnosticHint: String?
    private(set) var cloudKitContainerIdentifier: String?
    private(set) var cloudKitIdentityTokenState: String?
    private(set) var cloudKitUserRecordID: String?
    private(set) var recentErrors: [String] = []
    private(set) var recentFailedRecordDetails: [String] = []

    @ObservationIgnored
    private let recentErrorLimit = 5

    @ObservationIgnored
    private let recentFailedRecordDetailLimit = 5

    func apply(_ payload: Payload) {
        state = payload.state
        if case .error(let message, _) = state {
            appendRecentError(message)
        }

        lastSyncTime = payload.lastSyncTime
        accountStatusDescription = payload.accountStatus
        cloudKitDiagnosticHint = payload.diagnosticHint
        cloudKitContainerIdentifier = payload.cloudKitContainerIdentifier
        cloudKitIdentityTokenState = payload.cloudKitIdentityTokenState
        cloudKitUserRecordID = payload.cloudKitUserRecordID

        recentFailedRecordDetails = Array(payload.recentFailedSaveDetails.prefix(recentFailedRecordDetailLimit))
    }

    private func appendRecentError(_ message: String) {
        guard !message.isEmpty else { return }
        recentErrors.removeAll { $0 == message }
        recentErrors.insert(message, at: 0)
        if recentErrors.count > recentErrorLimit {
            recentErrors = Array(recentErrors.prefix(recentErrorLimit))
        }
    }

    struct Payload: Sendable {
        let state: SyncState
        let lastSyncTime: Date?
        let accountStatus: String?
        let diagnosticHint: String?
        let cloudKitContainerIdentifier: String?
        let cloudKitIdentityTokenState: String?
        let cloudKitUserRecordID: String?
        let recentFailedSaveDetails: [String]
    }

    var cloudKitDiagnosticSummary: String? {
        var parts: [String] = []

        if let cloudKitContainerIdentifier {
            parts.append(cloudKitContainerIdentifier)
        }

        if let accountStatusDescription {
            parts.append("account: \(accountStatusDescription)")
        }

        if let cloudKitIdentityTokenState {
            parts.append("identity token: \(cloudKitIdentityTokenState)")
        }

        if let cloudKitUserRecordID {
            parts.append("user record: \(cloudKitUserRecordID)")
        }

        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    var cloudKitNeedsAttention: Bool {
        if case .error = state {
            return true
        }

        guard let accountStatusDescription else { return false }

        return [
            "noAccount",
            "restricted",
            "couldNotDetermine",
            "temporarilyUnavailable",
            "signed out",
            "switched accounts",
            "unknown"
        ].contains(accountStatusDescription)
    }
}
