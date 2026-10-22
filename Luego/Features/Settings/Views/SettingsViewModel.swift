import CloudKit
import Foundation
import UIKit

enum SettingsImportSource {
    case file
    case pastedText
}

struct SettingsAlertContent {
    let title: String
    let message: String
}

struct SettingsExportPresentation: Identifiable {
    let id = UUID()
    let fileURL: URL
}

@Observable
@MainActor
final class SettingsViewModel {
    var isCheckingForUpdates = false
    var updateResult: SDKUpdateResult?
    var showUpdateAlert = false
    var isForceSyncing = false
    var didForceSync = false
    var forceSyncCount = 0
    var forceSyncErrorMessage: String?
    var isImporting = false
    var isPreparingExport = false
    var isShowingPasteImportSheet = false
    var pasteImportText = ""
    var alertContent: SettingsAlertContent?
    var showAlert = false
    var exportPresentation: SettingsExportPresentation?
    var totalSavedArticleCount = 0
    var readingListArticleCount = 0

    private let sdkManager: LuegoSDKManagerProtocol
    private let articleService: ArticleServiceProtocol
    private let savedArticleImportService: SavedArticleImportServiceProtocol
    private let savedArticleExportService: SavedArticleExportServiceProtocol

    init(
        sdkManager: LuegoSDKManagerProtocol,
        articleService: ArticleServiceProtocol,
        savedArticleImportService: SavedArticleImportServiceProtocol,
        savedArticleExportService: SavedArticleExportServiceProtocol
    ) {
        self.sdkManager = sdkManager
        self.articleService = articleService
        self.savedArticleImportService = savedArticleImportService
        self.savedArticleExportService = savedArticleExportService
    }

    private(set) var sdkVersionString: String?

    private func refreshSDKVersion() async {
        guard let info = await sdkManager.getVersionInfo() else {
            sdkVersionString = nil
            return
        }
        sdkVersionString = "Parser \(info.parserVersion) · Rules \(info.rulesVersion)"
    }

    func checkForSDKUpdates() async {
        isCheckingForUpdates = true
        updateResult = await sdkManager.checkForUpdates()
        isCheckingForUpdates = false
        showUpdateAlert = true
    }

    var updateAlertTitle: String {
        guard let result = updateResult else { return "" }
        switch result {
        case .updated: return "Parsing Rules Updated"
        case .alreadyUpToDate: return "Up to Date"
        case .failed: return "Update Failed"
        }
    }

    var updateAlertMessage: String {
        guard let result = updateResult else { return "" }
        switch result {
        case .updated(let parser, let rules, let bundlesUpdated, let rulesUpdated):
            var components: [String] = []
            if bundlesUpdated > 0 { components.append("\(bundlesUpdated) bundle(s)") }
            if rulesUpdated { components.append("rules") }
            let updatedText = components.isEmpty ? "" : "\nUpdated: \(components.joined(separator: ", "))"
            return "Parser \(parser) · Rules \(rules)\(updatedText)"
        case .alreadyUpToDate(let parser, let rules):
            return "Parser \(parser) · Rules \(rules)"
        case .failed(let error):
            return error.localizedDescription
        }
    }

    func forceReSync() async {
        isForceSyncing = true
        didForceSync = false
        forceSyncErrorMessage = nil

        let syncStartTime = Date()

        do {
            let count = try await articleService.forceReSyncAllArticles()
            forceSyncCount = count
            await refreshTransferCounts()

            let elapsed = Date().timeIntervalSince(syncStartTime)
            let minDuration: TimeInterval = 1.5
            if elapsed < minDuration {
                try? await Task.sleep(nanoseconds: UInt64((minDuration - elapsed) * 1_000_000_000))
            }

            didForceSync = true
        } catch {
            let message = error.localizedDescription
            forceSyncErrorMessage = message
            Logger.cloudKit.error("Repair sync failed: \(message)")
        }

        isForceSyncing = false

        if didForceSync {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                didForceSync = false
            }
        }
    }

    func beginPasteImport() {
        isShowingPasteImportSheet = true
    }

    func refreshTransferCounts() async {
        await refreshSDKVersion()
        do {
            let articles = try await articleService.getAllArticles()
            totalSavedArticleCount = articles.count
            readingListArticleCount = articles.reduce(into: 0) { count, article in
                if !article.isArchived {
                    count += 1
                }
            }
        } catch {
            Logger.article.error("Failed to refresh transfer counts: \(error.localizedDescription)")
        }
    }

    func dismissPasteImport() {
        isShowingPasteImportSheet = false
    }

    func importArticlesFromPasteText() async {
        let text = pasteImportText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            presentAlert(
                title: "Nothing to Import",
                message: "Paste article links before importing."
            )
            return
        }

        await importArticles(from: text, source: .pastedText)
        if !isImporting {
            pasteImportText = ""
            isShowingPasteImportSheet = false
        }
    }

    func importArticlesFromFileText(_ text: String) async {
        await importArticles(from: text, source: .file)
    }

    func prepareExport(scope: SavedArticleExportScope) async {
        guard !isPreparingExport else { return }

        isPreparingExport = true
        defer { isPreparingExport = false }

        do {
            let export = try await savedArticleExportService.makePlainTextExport(scope: scope)

            guard export.articleCount > 0 else {
                presentAlert(
                    title: "Nothing to Export",
                    message: exportEmptyStateMessage(for: scope)
                )
                return
            }

            removeExportedFileIfNeeded()
            let fileURL = try await ArticleTransferFile.write(export)
            exportPresentation = SettingsExportPresentation(fileURL: fileURL)
        } catch {
            presentAlert(
                title: "Export Failed",
                message: error.localizedDescription
            )
        }
    }

    func dismissExportPresentation() {
        removeExportedFileIfNeeded()
        exportPresentation = nil
    }

    func presentImportReadError(_ error: Error) {
        presentAlert(
            title: "Import Failed",
            message: error.localizedDescription
        )
    }

    func gatherDiagnostics(syncStatusObserver: SyncStatusObserver?) async -> String {
        var lines: [String] = []
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        lines.append("=== Luego Diagnostics ===")
        lines.append("Generated: \(dateFormatter.string(from: Date()))")
        lines.append("")

        let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        lines.append("App Bundle ID: \(bundleID)")
        lines.append("OSLog Subsystem: \(bundleID)")
        lines.append("App Version: \(version)")
        lines.append("Build Number: \(build)")
        lines.append("Platform: iOS \(UIDevice.current.systemVersion)")
        lines.append("")

        let container = CKContainer(identifier: AppConfiguration.cloudKitContainerIdentifier)
        async let cloudKitDiagnosticsTask = CloudKitRuntimeDiagnostics.collect(
            container: container,
            containerIdentifier: AppConfiguration.cloudKitContainerIdentifier
        )
        async let subscriptionsTask = fetchSubscriptions(for: container)
        async let articlesTask = articleService.getAllArticles()

        let cloudKitDiagnostics = await cloudKitDiagnosticsTask
        let subscriptions = await subscriptionsTask
        let articles = (try? await articlesTask) ?? []

        lines.append(contentsOf: cloudKitDiagnostics.detailLines)
        lines.append("Local Article Count: \(articles.count)")
        lines.append("Last Repair Sync Error: \(forceSyncErrorMessage ?? "none")")
        lines.append("")

        if let syncStatusObserver {
            lines.append("Sync Engine State: \(syncStateDescription(syncStatusObserver.state))")
            lines.append("Last Successful Sync: \(formattedDate(syncStatusObserver.lastSyncTime, dateFormatter: dateFormatter))")
            lines.append("Sync Account Status: \(syncStatusObserver.accountStatusDescription ?? "unknown")")
            if let diagnosticSummary = syncStatusObserver.cloudKitDiagnosticSummary {
                lines.append("Sync CloudKit Summary: \(diagnosticSummary)")
            }
            if let diagnosticHint = syncStatusObserver.cloudKitDiagnosticHint {
                lines.append("Sync CloudKit Hint: \(diagnosticHint)")
            }
            if syncStatusObserver.recentErrors.isEmpty {
                lines.append("Recent Sync Errors: none")
            } else {
                lines.append("Recent Sync Errors:")
                for error in syncStatusObserver.recentErrors.prefix(5) {
                    lines.append("  - \(error)")
                }
            }
            if syncStatusObserver.recentFailedRecordDetails.isEmpty {
                lines.append("Recent Failed Record Saves: none")
            } else {
                lines.append("Recent Failed Record Saves:")
                for detail in syncStatusObserver.recentFailedRecordDetails.prefix(5) {
                    lines.append("  - \(detail)")
                }
            }
            lines.append("")
        }

        lines.append("Active CloudKit Subscriptions: \(subscriptions.subscriptions.count)")
        for sub in subscriptions.subscriptions {
            lines.append("  - \(sub.subscriptionID) (type: \(sub.subscriptionType.rawValue))")
        }
        if let fetchError = subscriptions.errorMessage {
            lines.append("Subscription Fetch Error: \(fetchError)")
        }
        lines.append("")

        lines.append("--- Recent Logs (last 500 entries) ---")
        let logDateFormatter = DateFormatter()
        logDateFormatter.dateFormat = "HH:mm:ss"
        let recentLogs = LogStream.shared.entries.suffix(500)
        if recentLogs.isEmpty {
            lines.append("No logs captured yet.")
        } else {
            for entry in recentLogs {
                let time = logDateFormatter.string(from: entry.timestamp)
                lines.append("[\(time)] [\(entry.category)] [\(entry.level.rawValue)] \(entry.message)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private func importArticles(
        from text: String,
        source: SettingsImportSource
    ) async {
        let cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedText.isEmpty else {
            presentAlert(
                title: "Nothing to Import",
                message: source == .file
                    ? "The selected file was empty."
                    : "Paste article links before importing."
            )
            return
        }

        guard !isImporting else { return }

        isImporting = true
        let result = await savedArticleImportService.importArticles(fromPlainText: cleanedText)
        isImporting = false
        await refreshTransferCounts()

        presentAlert(
            title: importAlertTitle(for: result),
            message: importAlertMessage(for: result)
        )
    }

    private func fetchSubscriptions(for container: CKContainer) async -> CloudKitSubscriptionSnapshot {
        do {
            return CloudKitSubscriptionSnapshot(
                subscriptions: try await container.privateCloudDatabase.allSubscriptions(),
                errorMessage: nil
            )
        } catch {
            return CloudKitSubscriptionSnapshot(
                subscriptions: [],
                errorMessage: error.localizedDescription
            )
        }
    }

    private func syncStateDescription(_ state: SyncState) -> String {
        switch state {
        case .idle:
            return "idle"
        case .syncing:
            return "syncing"
        case .restoring:
            return "restoring"
        case .success:
            return "success"
        case .error(let message, let needsSignIn):
            return needsSignIn ? "error: \(message) (sign in required)" : "error: \(message)"
        }
    }

    private func formattedDate(_ date: Date?, dateFormatter: DateFormatter) -> String {
        guard let date else { return "never" }
        return dateFormatter.string(from: date)
    }

    private func presentAlert(title: String, message: String) {
        alertContent = SettingsAlertContent(title: title, message: message)
        showAlert = true
    }

    private func importAlertTitle(for result: SavedArticleImportResult) -> String {
        if !result.didFindURLs {
            return "No URLs Found"
        }
        if result.importedCount > 0 {
            return "Import Complete"
        }
        if result.skippedExistingCount > 0 && result.failedCount == 0 {
            return "Nothing New to Import"
        }
        return "Import Finished"
    }

    private func importAlertMessage(for result: SavedArticleImportResult) -> String {
        guard result.didFindURLs else {
            return "No supported http or https URLs were found."
        }

        var lines = [
            "Detected \(result.detectedURLCount) URL\(result.detectedURLCount == 1 ? "" : "s").",
            "Unique \(result.uniqueURLCount).",
            "Imported \(result.importedCount).",
            "Already saved \(result.skippedExistingCount).",
            "Duplicate input \(result.skippedDuplicateInputCount).",
            "Failed \(result.failedCount)."
        ]

        if !result.failureSamples.isEmpty {
            lines.append("")
            lines.append("Sample failures:")
            for failure in result.failureSamples {
                lines.append("\(failure.urlString): \(failure.message)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private func exportEmptyStateMessage(for scope: SavedArticleExportScope) -> String {
        switch scope {
        case .allArticles:
            return "There are no saved articles to export yet."
        case .readingList:
            return "There are no active reading-list articles to export yet."
        }
    }

    private func removeExportedFileIfNeeded() {
        guard let fileURL = exportPresentation?.fileURL else { return }
        Task { await ArticleTransferFile.remove(fileURL) }
    }
}

private struct CloudKitSubscriptionSnapshot {
    let subscriptions: [CKSubscription]
    let errorMessage: String?
}
