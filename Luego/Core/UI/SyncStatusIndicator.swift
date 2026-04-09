import SwiftUI

enum SyncPresentationState: Equatable {
    case upToDate
    case syncing
    case restoring
    case signInRequired
    case restricted
    case temporarilyUnavailable
    case syncFailed
}

struct SyncStatusPresentation {
    let state: SyncPresentationState
    let lastSyncTime: Date?
    let detailMessage: String?

    init(
        state: SyncState,
        accountStatusDescription: String?,
        cloudKitIdentityTokenState: String?,
        cloudKitUserRecordID: String?,
        cloudKitNeedsAttention: Bool,
        lastSyncTime: Date?
    ) {
        self.lastSyncTime = lastSyncTime

        switch state {
        case .idle, .success:
            if let attentionState = Self.attentionState(
                accountStatusDescription: accountStatusDescription,
                needsSignIn: false,
                cloudKitIdentityTokenState: cloudKitIdentityTokenState,
                cloudKitUserRecordID: cloudKitUserRecordID,
                cloudKitNeedsAttention: cloudKitNeedsAttention
            ) {
                self.state = attentionState
            } else {
                self.state = .upToDate
            }
            detailMessage = nil
        case .syncing:
            self.state = .syncing
            detailMessage = nil
        case .restoring:
            self.state = .restoring
            detailMessage = nil
        case .error(let message, let needsSignIn):
            if let attentionState = Self.attentionState(
                accountStatusDescription: accountStatusDescription,
                needsSignIn: needsSignIn,
                cloudKitIdentityTokenState: cloudKitIdentityTokenState,
                cloudKitUserRecordID: cloudKitUserRecordID,
                cloudKitNeedsAttention: cloudKitNeedsAttention
            ) {
                self.state = attentionState
                detailMessage = nil
            } else {
                self.state = .syncFailed
                detailMessage = message
            }
        }
    }

    private static func attentionState(
        accountStatusDescription: String?,
        needsSignIn: Bool,
        cloudKitIdentityTokenState: String?,
        cloudKitUserRecordID: String?,
        cloudKitNeedsAttention: Bool
    ) -> SyncPresentationState? {
        if needsSignIn || isEffectiveSignInRequired(
            accountStatusDescription: accountStatusDescription,
            cloudKitIdentityTokenState: cloudKitIdentityTokenState,
            cloudKitUserRecordID: cloudKitUserRecordID,
            cloudKitNeedsAttention: cloudKitNeedsAttention
        ) {
            return .signInRequired
        }

        switch accountStatusDescription {
        case "restricted":
            return .restricted
        case "couldNotDetermine":
            return .temporarilyUnavailable
        case "temporarilyUnavailable":
            return .temporarilyUnavailable
        default:
            return nil
        }
    }

    private static func isEffectiveSignInRequired(
        accountStatusDescription: String?,
        cloudKitIdentityTokenState: String?,
        cloudKitUserRecordID: String?,
        cloudKitNeedsAttention: Bool
    ) -> Bool {
        if isSignInStatus(accountStatusDescription) {
            return true
        }

        guard cloudKitNeedsAttention else { return false }
        guard accountStatusDescription == "temporarilyUnavailable" else { return false }
        return cloudKitIdentityTokenState == "absent"
            && cloudKitUserRecordID?.hasPrefix("unavailable:") == true
    }

    private static func isSignInStatus(_ accountStatusDescription: String?) -> Bool {
        switch accountStatusDescription {
        case "noAccount", "signed out", "switched accounts":
            return true
        default:
            return false
        }
    }

    private var formattedTime: String? {
        guard let lastSyncTime else { return nil }
        return DateFormatters.time.string(from: lastSyncTime)
    }

    var settingsStatusText: String {
        switch state {
        case .upToDate:
            "Up to date"
        case .syncing:
            "Syncing..."
        case .restoring:
            "Restoring..."
        case .signInRequired:
            "Sign in to iCloud to sync"
        case .restricted:
            "iCloud Sync is restricted"
        case .temporarilyUnavailable:
            "iCloud is temporarily unavailable"
        case .syncFailed:
            detailMessage ?? "Sync failed"
        }
    }

    var settingsSubtitle: String {
        switch state {
        case .upToDate:
            if let formattedTime {
                return "Last synced at \(formattedTime)"
            }
            return "Your sync status will appear after the first successful update."
        case .syncing:
            return "Uploading and downloading your reading list."
        case .restoring:
            return "Downloading your reading list from iCloud."
        case .signInRequired:
            return "Back up and sync your reading list across devices with iCloud."
        case .restricted:
            return "Check Screen Time, parental controls, or device management settings."
        case .temporarilyUnavailable:
            return "Try again in a moment."
        case .syncFailed:
            if let formattedTime {
                return "Last synced at \(formattedTime)"
            }
            return "Use troubleshooting tools if items seem out of sync."
        }
    }

    var settingsStatusColor: AnyShapeStyle {
        switch state {
        case .upToDate:
            AnyShapeStyle(.secondary)
        case .syncing, .restoring:
            AnyShapeStyle(.blue)
        case .signInRequired, .restricted, .temporarilyUnavailable:
            AnyShapeStyle(.orange)
        case .syncFailed:
            AnyShapeStyle(.red)
        }
    }

    var accessibilityValue: String {
        switch state {
        case .upToDate:
            if let formattedTime {
                return "\(settingsStatusText). Last synced at \(formattedTime)"
            }
            return settingsStatusText
        case .syncFailed:
            if let formattedTime {
                return "\(settingsStatusText). Last synced at \(formattedTime)"
            }
            return settingsStatusText
        default:
            return settingsStatusText
        }
    }

    var compactText: String? {
        switch state {
        case .upToDate:
            guard let formattedTime else { return nil }
            return "Synced at \(formattedTime)"
        case .syncing:
            return "Syncing with iCloud"
        case .restoring:
            return "Restoring from iCloud"
        case .signInRequired:
            return "iCloud sign-in required"
        case .restricted:
            return "iCloud Sync is restricted"
        case .temporarilyUnavailable:
            return "iCloud unavailable"
        case .syncFailed:
            if let detailMessage, !detailMessage.isEmpty {
                return detailMessage
            }
            if let formattedTime {
                return "Synced at \(formattedTime)"
            }
            return "Sync failed"
        }
    }

    var compactTextColor: AnyShapeStyle {
        switch state {
        case .upToDate:
            AnyShapeStyle(.tertiary)
        case .syncing, .restoring:
            AnyShapeStyle(.secondary)
        case .signInRequired, .restricted, .temporarilyUnavailable:
            AnyShapeStyle(.orange)
        case .syncFailed:
            AnyShapeStyle(.red)
        }
    }

    var showsSignInNotice: Bool {
        state == .signInRequired
    }

    var showsAttentionNotice: Bool {
        switch state {
        case .signInRequired, .restricted, .temporarilyUnavailable:
            true
        default:
            false
        }
    }

    var noticeIconName: String {
        switch state {
        case .signInRequired:
            "icloud.slash"
        case .restricted:
            "hand.raised"
        case .temporarilyUnavailable:
            "exclamationmark.icloud"
        default:
            "icloud"
        }
    }

    var noticeTitle: String {
        switch state {
        case .signInRequired:
            "iCloud Sync is unavailable"
        case .restricted:
            "iCloud Sync is restricted"
        case .temporarilyUnavailable:
            "iCloud is temporarily unavailable"
        default:
            settingsStatusText
        }
    }

    var noticeBody: String {
        switch state {
        case .signInRequired:
            "Sign in to iCloud in Settings to back up and sync your reading list across devices."
        case .restricted:
            "This device cannot access iCloud Sync right now. Check Screen Time, parental controls, or device management settings."
        case .temporarilyUnavailable:
            "Luego will keep your reading list on this device and reconnect when iCloud becomes available again."
        default:
            settingsSubtitle
        }
    }

    var noticeFootnote: String? {
        switch state {
        case .signInRequired:
            nil
        case .restricted:
            "If this is a managed or family device, those settings may be controlled elsewhere."
        case .temporarilyUnavailable:
            nil
        default:
            nil
        }
    }

    var noticeActionTitle: String? {
        switch state {
        case .signInRequired:
            "Open Settings"
        default:
            nil
        }
    }

    var noticeAccessibilityHint: String? {
        switch state {
        case .signInRequired:
            "Opens the Settings app so you can sign in to iCloud."
        default:
            nil
        }
    }

    var showsRepairAction: Bool {
        state != .signInRequired
    }
}

struct SyncStatusIndicator: View {
    let state: SyncState
    var onErrorTap: (() -> Void)?

    var body: some View {
        Group {
            switch state {
            case .idle:
                EmptyView()
            case .syncing:
                SyncActivityIndicator(systemName: "arrow.triangle.2.circlepath", label: "Syncing")
            case .restoring:
                SyncActivityIndicator(systemName: "arrow.down.circle", label: "Restoring from iCloud")
            case .success:
                SyncSuccessIndicator()
            case .error(_, let needsSignIn):
                SyncErrorButton(
                    onTap: onErrorTap,
                    systemName: needsSignIn ? "icloud.slash" : "exclamationmark.icloud",
                    tint: needsSignIn ? .orange : .red,
                    label: needsSignIn ? "iCloud sign-in required" : "Sync error, tap for details"
                )
            }
        }
        .animation(.easeInOut(duration: 0.3), value: state)
    }
}

private struct SyncActivityIndicator: View {
    let systemName: String
    let label: String

    var body: some View {
        Image(systemName: systemName)
            .symbolEffect(.rotate, isActive: true)
            .foregroundStyle(.secondary)
            .accessibilityLabel(label)
    }
}

private struct SyncSuccessIndicator: View {
    var body: some View {
        Image(systemName: "checkmark.icloud")
            .foregroundStyle(.green)
            .transition(.scale.combined(with: .opacity))
            .accessibilityLabel("Sync complete")
    }
}

private struct SyncErrorButton: View {
    var onTap: (() -> Void)?
    let systemName: String
    let tint: Color
    let label: String

    var body: some View {
        Button(action: { onTap?() }) {
            Image(systemName: systemName)
                .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
