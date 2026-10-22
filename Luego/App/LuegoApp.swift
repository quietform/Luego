//
//  LuegoApp.swift
//  Luego
//
//  Created by Arun Sasidharan on 10/11/25.
//

import SwiftUI
import CloudKit
import Observation

#if !LUEGO_BENCHMARK
@main
#endif
struct LuegoApp: App {
    @State private var diContainer: DIContainer?

    init() {
        AppTypography.registerFonts()
        Self.configurePlatformAppearance()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let diContainer {
                    ContentView()
                        .environment(\.diContainer, diContainer)
                        .environment(diContainer.syncObserver)
                        .task(id: "sdkInit") {
                            await diContainer.sdkManager.ensureSDKReady()
                        }
                        .task(id: "launchDiagnostics") {
                            await logLaunchDiagnostics()
                        }
                } else {
                    ProgressView()
                        .task { await initialize() }
                }
            }
        }
    }

    private func initialize() async {
        DiscoveryLegacyStorage.remove(from: .standard)
        do {
            let database = try await AppDatabase.makeDefault()
            let container = DIContainer(database: database)
            try await container.syncEngineManager.start()
            let legacyMigration = LegacySwiftDataArticleMigration(
                database: database,
                store: container.articleStore,
                syncEngineManager: container.syncEngineManager
            )
            do {
                let importedCount = try await legacyMigration.migrateIfNeeded()
                Logger.cloudKit.info("Launch migration — imported \(importedCount) legacy SwiftData articles")
            } catch {
                Logger.cloudKit.error("Launch migration — failed to import legacy SwiftData articles: \(error.localizedDescription)")
            }
            diContainer = container
        } catch {
            fatalError("Could not create AppDatabase: \(error)")
        }
    }
}

private extension LuegoApp {
    static func configurePlatformAppearance() {
        AppNavigationAppearance.configurePlatformAppearance()
    }
}

extension LuegoApp {
    @MainActor
    private func logLaunchDiagnostics() async {
        guard let diContainer else { return }
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        Logger.cloudKit.info("Launch diagnostics — App: \(bundleID) v\(appVersion) (\(buildNumber))")
        Logger.cloudKit.info("Launch diagnostics — CloudKit container: \(AppConfiguration.cloudKitContainerIdentifier)")

        let container = CKContainer(identifier: AppConfiguration.cloudKitContainerIdentifier)
        let diagnostics = await CloudKitRuntimeDiagnostics.collect(
            container: container,
            containerIdentifier: AppConfiguration.cloudKitContainerIdentifier
        )
        Logger.cloudKit.info("Launch diagnostics — \(diagnostics.summaryLine)")
        for line in diagnostics.detailLines {
            Logger.cloudKit.info("Launch diagnostics — \(line)")
        }

        do {
            let subscriptions = try await container.privateCloudDatabase.allSubscriptions()
            Logger.cloudKit.info("Launch diagnostics — active subscriptions: \(subscriptions.count)")
            for subscription in subscriptions {
                Logger.cloudKit.debug("Launch diagnostics — subscription: \(subscription.subscriptionID), type: \(subscription.subscriptionType.rawValue)")
            }
        } catch {
            Logger.cloudKit.warning("Launch diagnostics — failed to fetch subscriptions: \(error.localizedDescription)")
        }

        do {
            let count = try await diContainer.articleStore.countArticles()
            Logger.cloudKit.info("Launch diagnostics — article count at startup: \(count)")

            #if DEBUG
            do {
                let articles = try await diContainer.articleStore.fetchAllArticles()
                let sortedArticles = articles.sorted { lhs, rhs in
                    let lhsURL = lhs.url.absoluteString
                    let rhsURL = rhs.url.absoluteString

                    if lhsURL == rhsURL {
                        return lhs.id.uuidString < rhs.id.uuidString
                    }

                    return lhsURL < rhsURL
                }

                Logger.cloudKit.info("Launch diagnostics — article identity count: \(sortedArticles.count)")

                for article in sortedArticles {
                    Logger.cloudKit.info("Launch diagnostics — article identity: \(article.id.uuidString) | \(article.url.absoluteString)")
                }
            } catch {
                Logger.cloudKit.error("Launch diagnostics — failed to fetch article identities: \(error.localizedDescription)")
            }
            #endif
        } catch {
            Logger.cloudKit.error("Launch diagnostics — failed to count articles: \(error.localizedDescription)")
        }

        Logger.cloudKit.info("Launch diagnostics — Platform: iOS")
    }

}

private struct DIContainerKey: EnvironmentKey {
    @MainActor
    static let defaultValue: DIContainer? = nil
}

@MainActor
@Observable
final class IPhoneTabBarVisibilityController {
    var isVisible = true

    func show() {
        isVisible = true
    }

    func hide() {
        isVisible = false
    }
}

private struct IPhoneTabBarVisibilityControllerKey: EnvironmentKey {
    @MainActor
    static let defaultValue: IPhoneTabBarVisibilityController? = nil
}

extension EnvironmentValues {
    var diContainer: DIContainer? {
        get { self[DIContainerKey.self] }
        set { self[DIContainerKey.self] = newValue }
    }

    var iPhoneTabBarVisibilityController: IPhoneTabBarVisibilityController? {
        get { self[IPhoneTabBarVisibilityControllerKey.self] }
        set { self[IPhoneTabBarVisibilityControllerKey.self] = newValue }
    }
}
