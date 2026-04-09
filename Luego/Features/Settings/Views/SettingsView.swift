import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var viewModel: SettingsViewModel
    var syncStatusObserver: SyncStatusObserver?
    @Environment(SyncStatusObserver.self) private var envSyncStatusObserver
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingFileImporter = false

    private var resolvedObserver: SyncStatusObserver {
        syncStatusObserver ?? envSyncStatusObserver
    }

    var body: some View {
        Form {
            SyncStatusSection(
                state: resolvedObserver.state,
                lastSyncTime: resolvedObserver.lastSyncTime,
                syncStatusObserver: resolvedObserver,
                isSyncing: viewModel.isForceSyncing,
                didSync: viewModel.didForceSync,
                repairErrorMessage: viewModel.forceSyncErrorMessage,
                onSync: { Task { await viewModel.forceReSync() } }
            )

            DiscoverySettingsSection(
                selectedSource: $viewModel.selectedDiscoverySource,
                onSourceChanged: viewModel.updateDiscoverySource
            )

            LibrarySettingsSection(
                isImporting: viewModel.isImporting,
                isPreparingExport: viewModel.isPreparingExport,
                totalSavedArticleCount: viewModel.totalSavedArticleCount,
                readingListArticleCount: viewModel.readingListArticleCount,
                onImportFromFile: {
                    isShowingFileImporter = true
                },
                onPasteArticleList: {
                    viewModel.beginPasteImport()
                },
                onExportAllArticles: {
                    viewModel.prepareExport(scope: .allArticles)
                },
                onExportReadingList: {
                    viewModel.prepareExport(scope: .readingList)
                }
            )

            TroubleshootingSettingsSection(
                didRefresh: viewModel.didRefreshPool,
                isChecking: viewModel.isCheckingForUpdates,
                onRefresh: viewModel.refreshArticlePool,
                onCheck: { Task { await viewModel.checkForSDKUpdates() } },
                viewModel: viewModel,
                syncStatusObserver: resolvedObserver
            )

            AppVersionSection(sdkVersionString: viewModel.sdkVersionString)
        }
        .formStyle(.grouped)
        .tint(Color.regularSelectionInk)
        .appNavigationStyle(.inlineTransparent)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .alert(
            viewModel.updateAlertTitle,
            isPresented: $viewModel.showUpdateAlert
        ) {
            Button("OK") { }
        } message: {
            Text(viewModel.updateAlertMessage)
        }
        .alert(
            viewModel.alertContent?.title ?? "",
            isPresented: $viewModel.showAlert
        ) {
            Button("OK") { }
        } message: {
            Text(viewModel.alertContent?.message ?? "")
        }
        .sheet(
            isPresented: $viewModel.isShowingPasteImportSheet,
            onDismiss: {
                viewModel.dismissPasteImport()
            }
        ) {
            SavedArticlePasteImportSheet(viewModel: viewModel)
        }
        .sheet(
            item: $viewModel.exportPresentation,
            onDismiss: {
                viewModel.dismissExportPresentation()
            }
        ) { presentation in
            SettingsShareSheet(activityItems: [presentation.fileURL])
        }
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: [.plainText, .text]
        ) { result in
            handleFileImport(result)
        }
        .task {
            await viewModel.refreshTransferCounts()
        }
    }

    private func handleFileImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            Task {
                do {
                    let text = try readPlainTextFile(at: url)
                    await viewModel.importArticlesFromFileText(text)
                } catch {
                    await MainActor.run {
                        viewModel.presentImportReadError(error)
                    }
                }
            }
        case .failure(let error):
            guard !isUserCancelledFileImport(error) else { return }
            viewModel.presentImportReadError(error)
        }
    }

    private func isUserCancelledFileImport(_ error: Error) -> Bool {
        if let cocoaError = error as? CocoaError, cocoaError.code == .userCancelled {
            return true
        }

        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain
            && nsError.code == CocoaError.Code.userCancelled.rawValue
    }

    private func readPlainTextFile(at url: URL) throws -> String {
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: url)
        let encodings: [String.Encoding] = [
            .utf8,
            .unicode,
            .utf16,
            .utf16LittleEndian,
            .utf16BigEndian
        ]

        for encoding in encodings {
            if let string = String(data: data, encoding: encoding) {
                return string
            }
        }

        throw CocoaError(.fileReadInapplicableStringEncoding)
    }
}

struct IOSSettingsRow<TitleAccessory: View, Trailing: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var showsIcon: Bool = true
    var iconColor: Color = .secondary
    @ViewBuilder var titleAccessory: TitleAccessory
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            if showsIcon {
                Image(systemName: systemImage)
                    .font(.body.weight(.medium))
                    .foregroundStyle(iconColor)
                    .frame(width: 20)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)

                    titleAccessory
                }

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            trailing
        }
        .contentShape(Rectangle())
    }
}

extension IOSSettingsRow where TitleAccessory == EmptyView {
    init(
        title: String,
        subtitle: String,
        systemImage: String,
        showsIcon: Bool = true,
        iconColor: Color = .secondary,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.showsIcon = showsIcon
        self.iconColor = iconColor
        self.titleAccessory = EmptyView()
        self.trailing = trailing()
    }
}

struct IOSDiscoverySourceRow: View {
    let source: DiscoverySource
    let isSelected: Bool
    let onTap: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button(action: onTap) {
            IOSSettingsRow(
                title: source.displayName,
                subtitle: source.descriptionText,
                systemImage: "safari",
                showsIcon: false
            ) {
                if let websiteURL = source.websiteURL {
                    SourceWebsiteLinkButton(url: websiteURL, openURL: openURL)
                }
            } trailing: {
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.regularSelectionInk)
                        .font(.body.weight(.semibold))
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct DiscoverySettingsSection: View {
    @Binding var selectedSource: DiscoverySource
    let onSourceChanged: (DiscoverySource) -> Void

    var body: some View {
        Section {
            DiscoverySettingsContent(
                selectedSource: $selectedSource,
                onSourceChanged: onSourceChanged
            )
        } header: {
            settingsSectionHeader("Discovery")
        } footer: {
            Text("Choose where new recommendations come from.")
        }
    }
}

struct DiscoverySettingsContent: View {
    @Binding var selectedSource: DiscoverySource
    let onSourceChanged: (DiscoverySource) -> Void

    var body: some View {
        ForEach(DiscoverySource.allCases, id: \.self) { source in
            IOSDiscoverySourceRow(
                source: source,
                isSelected: selectedSource == source,
                onTap: {
                    selectedSource = source
                    onSourceChanged(source)
                }
            )
        }
    }
}

struct SourceWebsiteLinkButton: View {
    let url: URL
    let openURL: OpenURLAction

    var body: some View {
        Button {
            openURL(url)
        } label: {
            Image(systemName: "arrow.up.right.square")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open source website")
    }
}

struct TroubleshootingSettingsSection: View {
    let didRefresh: Bool
    let isChecking: Bool
    let onRefresh: () -> Void
    let onCheck: () -> Void
    let viewModel: SettingsViewModel
    let syncStatusObserver: SyncStatusObserver?

    var body: some View {
        Section {
            Button(action: onRefresh) {
                IOSSettingsRow(
                    title: "Refresh Discovery Cache",
                    subtitle: "Reloads discovery suggestions from the source.",
                    systemImage: "arrow.clockwise",
                    showsIcon: false
                ) {
                    SettingsActionAccessory(
                        isLoading: false,
                        isComplete: didRefresh
                    )
                }
            }
            .buttonStyle(.plain)
            .disabled(didRefresh || isChecking)

            Button(action: onCheck) {
                IOSSettingsRow(
                    title: "Update Parsing Rules",
                    subtitle: "Downloads the latest parsing rules for saved links.",
                    systemImage: "arrow.triangle.2.circlepath",
                    showsIcon: false
                ) {
                    SettingsActionAccessory(isLoading: isChecking)
                }
            }
            .buttonStyle(.plain)
            .disabled(isChecking)

            CopyDiagnosticsButton(
                viewModel: viewModel,
                syncStatusObserver: syncStatusObserver
            )
        } header: {
            settingsSectionHeader("Troubleshooting")
        } footer: {
            Text("Use these tools if something looks out of date or out of sync.")
        }
    }
}

struct LibrarySettingsSection: View {
    let isImporting: Bool
    let isPreparingExport: Bool
    let totalSavedArticleCount: Int
    let readingListArticleCount: Int
    let onImportFromFile: () -> Void
    let onPasteArticleList: () -> Void
    let onExportAllArticles: () -> Void
    let onExportReadingList: () -> Void

    var body: some View {
        Section {
            Button(action: onImportFromFile) {
                IOSSettingsRow(
                    title: "Import Links",
                    subtitle: "Import a text file with one link per line.",
                    systemImage: "square.and.arrow.down",
                    showsIcon: false
                ) {
                    SettingsActionAccessory(isLoading: isImporting)
                }
            }
            .buttonStyle(.plain)
            .disabled(isImporting || isPreparingExport)

            Button(action: onPasteArticleList) {
                IOSSettingsRow(
                    title: "Paste Links from Clipboard",
                    subtitle: "Import links from pasted text.",
                    systemImage: "doc.on.clipboard",
                    showsIcon: false
                ) {
                    SettingsActionAccessory(isLoading: isImporting)
                }
            }
            .buttonStyle(.plain)
            .disabled(isImporting || isPreparingExport)

            Button(action: onExportAllArticles) {
                IOSSettingsRow(
                    title: "Export All Saved Links",
                    subtitle: "Export every saved link as a text file.",
                    systemImage: "square.and.arrow.up",
                    showsIcon: false
                ) {
                    SettingsActionAccessory(
                        isLoading: isPreparingExport,
                        countLabel: transferCountLabel(totalSavedArticleCount)
                    )
                }
            }
            .buttonStyle(.plain)
            .disabled(isImporting || isPreparingExport)

            Button(action: onExportReadingList) {
                IOSSettingsRow(
                    title: "Export Unread Links",
                    subtitle: "Export links that are still in your reading list.",
                    systemImage: "text.badge.checkmark",
                    showsIcon: false
                ) {
                    SettingsActionAccessory(
                        isLoading: isPreparingExport,
                        countLabel: transferCountLabel(readingListArticleCount)
                    )
                }
            }
            .buttonStyle(.plain)
            .disabled(isImporting || isPreparingExport)
        } header: {
            settingsSectionHeader("Library")
        } footer: {
            Text("Import links into Luego or export what you have saved.")
        }
    }

    private func transferCountLabel(_ count: Int) -> String {
        let noun = count == 1 ? "link" : "links"
        return "\(count.formatted()) \(noun)"
    }
}

private struct TransferCountBadge: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }
}

private struct SettingsActionAccessory: View {
    let isLoading: Bool
    var isComplete: Bool = false
    var countLabel: String? = nil

    var body: some View {
        if isLoading {
            ProgressView()
                .controlSize(.small)
        } else {
            HStack(spacing: 8) {
                if let countLabel {
                    TransferCountBadge(label: countLabel)
                }

                if isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

struct SavedArticlePasteImportSheet: View {
    @Bindable var viewModel: SettingsViewModel

    private var canImport: Bool {
        !viewModel.pasteImportText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isImporting
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $viewModel.pasteImportText)
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.elevatedPanelBackground)
                        )

                    if viewModel.pasteImportText.isEmpty {
                        Text("Paste links or any text that contains links.")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 20)
                            .allowsHitTesting(false)
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .padding(20)
            .background(Color.regularPanelBackground)
            .navigationTitle("Paste Links")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.dismissPasteImport()
                    }
                    .disabled(viewModel.isImporting)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            await viewModel.importArticlesFromPasteText()
                        }
                    } label: {
                        if viewModel.isImporting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Import")
                        }
                    }
                    .disabled(!canImport)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct SyncStatusSection: View {
    let state: SyncState
    let lastSyncTime: Date?
    let syncStatusObserver: SyncStatusObserver?
    let isSyncing: Bool
    let didSync: Bool
    let repairErrorMessage: String?
    let onSync: () -> Void

    private var presentation: SyncStatusPresentation {
        SyncStatusPresentation(
            state: state,
            accountStatusDescription: syncStatusObserver?.accountStatusDescription,
            cloudKitIdentityTokenState: syncStatusObserver?.cloudKitIdentityTokenState,
            cloudKitUserRecordID: syncStatusObserver?.cloudKitUserRecordID,
            cloudKitNeedsAttention: syncStatusObserver?.cloudKitNeedsAttention == true,
            lastSyncTime: lastSyncTime
        )
    }

    var body: some View {
        Section {
            IOSSettingsRow(
                title: "iCloud Sync",
                subtitle: presentation.settingsSubtitle,
                systemImage: "icloud",
                showsIcon: false
            ) {
                Text(presentation.settingsStatusText)
                    .font(.subheadline)
                    .foregroundStyle(presentation.settingsStatusColor)
                    .multilineTextAlignment(.trailing)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("iCloud Sync")
            .accessibilityValue(presentation.accessibilityValue)

            if presentation.showsAttentionNotice {
                SyncAttentionNoticeCard(
                    presentation: presentation
                )
            }

            if presentation.showsRepairAction {
                ForceReSyncButton(
                    isSyncing: isSyncing,
                    didSync: didSync,
                    onSync: onSync
                )
            }
        } header: {
            settingsSectionHeader("Sync")
        } footer: {
            SyncSectionFooter(
                repairErrorMessage: repairErrorMessage
            )
        }
    }
}

struct AppVersionSection: View {
    let sdkVersionString: String?

    private var appVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Version \(version) (\(build))"
    }

    var body: some View {
        Section {
            VStack(spacing: 4) {
                Text(appVersionString)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if let sdkVersion = sdkVersionString {
                    Text(sdkVersion)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity)
        } header: {
            settingsSectionHeader("About")
        }
    }
}

struct CopyDiagnosticsButton: View {
    let viewModel: SettingsViewModel
    let syncStatusObserver: SyncStatusObserver?
    @State private var showCopiedToast = false
    @State private var isLoading = false

    var body: some View {
        Button(action: {
            Task { await copyDiagnostics() }
        }) {
            IOSSettingsRow(
                title: "Copy Troubleshooting Details",
                subtitle: "Copy sync and device details for support.",
                systemImage: "doc.on.doc",
                showsIcon: false
            ) {
                SettingsActionAccessory(isLoading: isLoading, isComplete: showCopiedToast)
            }
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

    private func copyDiagnostics() async {
        isLoading = true
        defer { isLoading = false }

        let diagnostics = await viewModel.gatherDiagnostics(syncStatusObserver: syncStatusObserver)

        await MainActor.run {
            UIPasteboard.general.string = diagnostics
            showCopiedToast = true
        }

        try? await Task.sleep(nanoseconds: 2_000_000_000)

        await MainActor.run {
            showCopiedToast = false
        }
    }
}

struct ForceReSyncButton: View {
    let isSyncing: Bool
    let didSync: Bool
    let onSync: () -> Void

    var body: some View {
        Button(action: onSync) {
            IOSSettingsRow(
                title: isSyncing ? "Repairing iCloud Sync..." : "Repair iCloud Sync",
                subtitle: "Use this if items seem missing or out of sync.",
                systemImage: "arrow.clockwise.icloud",
                showsIcon: false
            ) {
                SettingsActionAccessory(isLoading: isSyncing, isComplete: didSync)
            }
        }
        .buttonStyle(.plain)
        .disabled(isSyncing)
    }
}

private struct SyncSectionFooter: View {
    let repairErrorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let repairErrorMessage {
                Text(repairErrorMessage)
                    .foregroundStyle(.red)
            }
        }
    }
}

private struct SyncAttentionNoticeCard: View {
    let presentation: SyncStatusPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: presentation.noticeIconName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text(presentation.noticeTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(presentation.noticeBody)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let noticeFootnote = presentation.noticeFootnote {
                        Text(noticeFootnote)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.orange.opacity(0.22), lineWidth: 1)
        )
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .accessibilityElement(children: .contain)
    }
}

private func settingsSectionHeader(_ title: String) -> some View {
    Text(title)
        .textCase(.uppercase)
}

struct SettingsShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
    }
}
