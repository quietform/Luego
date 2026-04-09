import Foundation
import Observation

enum SyncState: Equatable {
    case idle
    case syncing
    case restoring
    case success
    case error(message: String, needsSignIn: Bool)
}

@MainActor
protocol SyncStatusObservable: AnyObject {
    var state: SyncState { get }
    var lastSyncTime: Date? { get }
    var accountStatusDescription: String? { get }
    var cloudKitDiagnosticHint: String? { get }
    var cloudKitContainerIdentifier: String? { get }
    var cloudKitIdentityTokenState: String? { get }
    var cloudKitUserRecordID: String? { get }
    var cloudKitDiagnosticSummary: String? { get }
    var cloudKitNeedsAttention: Bool { get }
    var recentErrors: [String] { get }
    var recentFailedRecordDetails: [String] { get }
    func dismissError()
}

@Observable
@MainActor
final class SyncStatusObserver: NSObject, SyncStatusObservable {
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

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStatusChange(_:)),
            name: .luegoSyncEngineStatusDidChange,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func dismissError() {
        if case .error = state {
            state = .idle
        }
    }

    func apply(_ payload: Payload) {
        if let newState = payload.state {
            state = newState
            if case .error(let message, _) = newState {
                appendRecentError(message)
            }
        }

        if let lastSyncTime = payload.lastSyncTime {
            self.lastSyncTime = lastSyncTime
        }

        accountStatusDescription = payload.accountStatus

        if let diagnosticHint = payload.diagnosticHint {
            cloudKitDiagnosticHint = diagnosticHint
        }

        if let containerIdentifier = payload.cloudKitContainerIdentifier {
            cloudKitContainerIdentifier = containerIdentifier
        }

        if let identityTokenState = payload.cloudKitIdentityTokenState {
            cloudKitIdentityTokenState = identityTokenState
        }

        if let userRecordID = payload.cloudKitUserRecordID {
            cloudKitUserRecordID = userRecordID
        }

        if let errorMessage = payload.errorMessage,
           case .error = state {
            appendRecentError(errorMessage)
        }

        if let failedSaveDetails = payload.recentFailedSaveDetails {
            recentFailedRecordDetails = Array(failedSaveDetails.prefix(recentFailedRecordDetailLimit))
        }
    }

    @objc private func handleStatusChange(_ notification: Notification) {
        guard let payload = Self.payload(from: notification.userInfo) else { return }
        apply(payload)
    }

    private func appendRecentError(_ message: String) {
        guard !message.isEmpty else { return }
        recentErrors.removeAll { $0 == message }
        recentErrors.insert(message, at: 0)
        if recentErrors.count > recentErrorLimit {
            recentErrors = Array(recentErrors.prefix(recentErrorLimit))
        }
    }

    private static func payload(from userInfo: [AnyHashable: Any]?) -> Payload? {
        guard let userInfo else { return nil }
        return Payload(
            state: userInfo[SyncEngineStatusPayloadKey.state] as? SyncState,
            lastSyncTime: userInfo[SyncEngineStatusPayloadKey.lastSyncTime] as? Date,
            errorMessage: userInfo[SyncEngineStatusPayloadKey.errorMessage] as? String,
            accountStatus: userInfo[SyncEngineStatusPayloadKey.accountStatus] as? String,
            diagnosticHint: userInfo[SyncEngineStatusPayloadKey.diagnosticHint] as? String,
            cloudKitContainerIdentifier: userInfo[SyncEngineStatusPayloadKey.cloudKitContainerIdentifier] as? String,
            cloudKitIdentityTokenState: userInfo[SyncEngineStatusPayloadKey.cloudKitIdentityTokenState] as? String,
            cloudKitUserRecordID: userInfo[SyncEngineStatusPayloadKey.cloudKitUserRecordID] as? String,
            recentFailedSaveDetails: userInfo[SyncEngineStatusPayloadKey.recentFailedSaveDetails] as? [String]
        )
    }

    struct Payload: Sendable {
        let state: SyncState?
        let lastSyncTime: Date?
        let errorMessage: String?
        let accountStatus: String?
        let diagnosticHint: String?
        let cloudKitContainerIdentifier: String?
        let cloudKitIdentityTokenState: String?
        let cloudKitUserRecordID: String?
        let recentFailedSaveDetails: [String]?
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
