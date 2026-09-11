import Foundation
import Testing

@MainActor
struct SyncStatusTests {
    @Test
    func replacementStatusClearsStaleDiagnostics() {
        let observer = SyncStatusObserver()
        observer.apply(SyncStatusObserver.Payload(
            state: .error(message: "Sign in", needsSignIn: true),
            lastSyncTime: nil,
            accountStatus: "noAccount",
            diagnosticHint: "Sign in to iCloud",
            cloudKitContainerIdentifier: "old-container",
            cloudKitIdentityTokenState: "absent",
            cloudKitUserRecordID: "old-user",
            recentFailedSaveDetails: []
        ))

        observer.apply(SyncStatusObserver.Payload(
            state: .success,
            lastSyncTime: Date(timeIntervalSinceReferenceDate: 10),
            accountStatus: "available",
            diagnosticHint: nil,
            cloudKitContainerIdentifier: nil,
            cloudKitIdentityTokenState: nil,
            cloudKitUserRecordID: nil,
            recentFailedSaveDetails: []
        ))

        #expect(observer.state == .success)
        #expect(observer.cloudKitDiagnosticHint == nil)
        #expect(observer.cloudKitContainerIdentifier == nil)
        #expect(observer.cloudKitIdentityTokenState == nil)
        #expect(observer.cloudKitUserRecordID == nil)
        #expect(observer.recentErrors == ["Sign in"])
    }
    @Test
    func unrelatedStatusBroadcastDoesNotChangeObserver() {
        let observer = SyncStatusObserver()

        NotificationCenter.default.post(
            name: Notification.Name("com.esoxjem.Luego.syncEngineStatusDidChange"),
            object: nil,
            userInfo: ["state": SyncState.error(message: "Another session failed", needsSignIn: false)]
        )

        #expect(observer.state == .idle)
        #expect(observer.recentErrors.isEmpty)
    }

}
