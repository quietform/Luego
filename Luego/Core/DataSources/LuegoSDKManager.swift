import Foundation

protocol LuegoSDKManagerProtocol: Sendable {
    func ensureSDKReady() async
    func checkForUpdates() async -> SDKUpdateResult
    func isSDKAvailable() async -> Bool
    func loadBundles() async -> [String: String]?
    func loadRules() async -> Data?
    func getVersionInfo() async -> SDKVersionInfo?
}

struct SDKVersionInfo: Sendable {
    let parserVersion: String
    let rulesVersion: String
}

enum SDKUpdateResult: Sendable {
    case updated(parserVersion: String, rulesVersion: String, bundlesUpdated: Int, rulesUpdated: Bool)
    case alreadyUpToDate(parserVersion: String, rulesVersion: String)
    case failed(Error)
}

@MainActor
final class LuegoSDKManager: LuegoSDKManagerProtocol {
    private let sdkDataSource: LuegoSDKDataSourceProtocol
    private let cacheDataSource: LuegoSDKCacheDataSourceProtocol

    init(
        sdkDataSource: LuegoSDKDataSourceProtocol,
        cacheDataSource: LuegoSDKCacheDataSourceProtocol
    ) {
        self.sdkDataSource = sdkDataSource
        self.cacheDataSource = cacheDataSource
    }

    func ensureSDKReady() async {
        _ = await checkForUpdates()
    }

    func checkForUpdates() async -> SDKUpdateResult {
        do {
            Logger.sdk.debug("─────────────────────────────────────────────")
            Logger.sdk.debug("Checking for updates...")

            let remoteVersions = try await sdkDataSource.fetchVersions()
            let localVersions = await cacheDataSource.loadVersions()

            logVersionComparison(remote: remoteVersions, local: localVersions)

            var downloadedBundles: [String] = []
            var skippedBundles: [String] = []

            for bundleName in AppConfiguration.sdkBundleNames {
                let remoteVersion = remoteVersions.bundles[bundleName]?.version
                let localVersion = localVersions?.bundles[bundleName]?.version
                let fileExists = await cacheDataSource.bundleExists(name: bundleName)

                let versionMismatch = localVersion != remoteVersion
                let needsDownload = versionMismatch || !fileExists

                if needsDownload {
                    let reason = !fileExists ? "missing" : "outdated"
                    Logger.sdk.debug("↓ Downloading \(bundleName) (\(reason))")

                    let data = try await sdkDataSource.downloadBundle(name: bundleName)
                    await cacheDataSource.saveBundle(name: bundleName, data: data)
                    downloadedBundles.append(bundleName)
                } else {
                    skippedBundles.append(bundleName)
                }
            }

            let rulesRefreshed = await refreshRulesIfNeeded(
                remoteVersion: remoteVersions.rules.version,
                localVersion: localVersions?.rules.version
            )
            await cacheDataSource.saveVersions(remoteVersions)

            logReadySummary(
                remoteVersions: remoteVersions,
                downloadedBundles: downloadedBundles,
                skippedBundles: skippedBundles,
                rulesRefreshed: rulesRefreshed
            )

            let parserVersion = remoteVersions.bundles["parser"]?.version ?? "?"
            let rulesVersion = remoteVersions.rules.version

            if downloadedBundles.isEmpty && !rulesRefreshed {
                return .alreadyUpToDate(parserVersion: parserVersion, rulesVersion: rulesVersion)
            } else {
                return .updated(
                    parserVersion: parserVersion,
                    rulesVersion: rulesVersion,
                    bundlesUpdated: downloadedBundles.count,
                    rulesUpdated: rulesRefreshed
                )
            }
        } catch {
            Logger.sdk.error("✗ Update failed: \(error.localizedDescription)")
            Logger.sdk.debug("─────────────────────────────────────────────")
            return .failed(error)
        }
    }

    private func refreshRulesIfNeeded(remoteVersion: String, localVersion: String?) async -> Bool {
        let versionMismatch = localVersion != remoteVersion
        let fileExists = await cacheDataSource.rulesExist()

        guard versionMismatch || !fileExists else { return false }

        let reason = !fileExists ? "missing" : "outdated"
        Logger.sdk.debug("↓ Downloading rules (\(reason))")

        do {
            let rules = try await sdkDataSource.fetchRules()
            await cacheDataSource.saveRules(rules)
            return true
        } catch {
            Logger.sdk.warning("⚠ Rules refresh failed: \(error)")
            return false
        }
    }

    func isSDKAvailable() async -> Bool {
        await cacheDataSource.allBundlesExist()
    }

    func loadBundles() async -> [String: String]? {
        await cacheDataSource.loadBundles(names: AppConfiguration.sdkBundleNames)
    }

    func loadRules() async -> Data? {
        await cacheDataSource.loadRules()
    }

    func getVersionInfo() async -> SDKVersionInfo? {
        guard let versions = await cacheDataSource.loadVersions(),
              let parserInfo = versions.bundles["parser"] else {
            return nil
        }

        return SDKVersionInfo(
            parserVersion: parserInfo.version,
            rulesVersion: versions.rules.version
        )
    }

    private func logVersionComparison(remote: SDKVersionsResponse, local: SDKVersionsResponse?) {
        let parserRemote = remote.bundles["parser"]?.version ?? "?"
        let rulesRemote = remote.rules.version

        if let local = local {
            let parserLocal = local.bundles["parser"]?.version ?? "?"
            let rulesLocal = local.rules.version

            let parserMatch = parserRemote == parserLocal
            let rulesMatch = rulesRemote == rulesLocal

            Logger.sdk.debug("Parser: \(parserLocal) → \(parserRemote) \(parserMatch ? "✓" : "↑")")
            Logger.sdk.debug("Rules:  \(rulesLocal) → \(rulesRemote) \(rulesMatch ? "✓" : "↑")")
        } else {
            Logger.sdk.debug("Parser: (none) → \(parserRemote) ↓")
            Logger.sdk.debug("Rules:  (none) → \(rulesRemote) ↓")
        }
    }

    private func logReadySummary(
        remoteVersions: SDKVersionsResponse,
        downloadedBundles: [String],
        skippedBundles: [String],
        rulesRefreshed: Bool
    ) {
        let parserVersion = remoteVersions.bundles["parser"]?.version ?? "?"
        let rulesVersion = remoteVersions.rules.version

        if downloadedBundles.isEmpty && !rulesRefreshed {
            Logger.sdk.debug("✓ Ready (v\(parserVersion), rules: \(rulesVersion)) - all cached")
        } else {
            var updates: [String] = []
            if !downloadedBundles.isEmpty {
                updates.append("\(downloadedBundles.count) bundle(s)")
            }
            if rulesRefreshed {
                updates.append("rules")
            }
            Logger.sdk.debug("✓ Ready (v\(parserVersion), rules: \(rulesVersion)) - updated: \(updates.joined(separator: ", "))")
        }
        Logger.sdk.debug("─────────────────────────────────────────────")
    }
}
