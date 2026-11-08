import Foundation
import Testing

@MainActor
struct LuegoSDKManagerTests {
    @Test
    func cachedBundleThatDoesNotMatchTheServersSizeIsDownloadedAgain() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let server = SDKServerFixture()
        let cache = LuegoSDKCacheDataSource(directory: directory)
        await cache.saveVersions(server.manifest)
        await cache.saveRules(Data("rules".utf8))
        for (name, data) in server.bundles {
            await cache.saveBundle(name: name, data: name == "parser" ? Data("stale parser from the URL cache".utf8) : data)
        }
        let manager = LuegoSDKManager(sdkDataSource: server, cacheDataSource: cache)

        _ = await manager.checkForUpdates()

        #expect(server.downloadedBundles == ["parser"])
        #expect(await cache.loadBundles(names: ["parser"])?["parser"] == "fresh parser")
    }
}

@MainActor
private final class SDKServerFixture: LuegoSDKDataSourceProtocol {
    let bundles: [String: Data] = Dictionary(uniqueKeysWithValues: AppConfiguration.sdkBundleNames.map { name in
        (name, Data("fresh \(name)".utf8))
    })
    private(set) var downloadedBundles: [String] = []

    var manifest: SDKVersionsResponse {
        SDKVersionsResponse(
            bundles: bundles.mapValues { SDKVersionsResponse.BundleInfo(version: "1.1.3", size: $0.count) },
            rules: SDKVersionsResponse.RulesInfo(version: "1.1.1")
        )
    }

    func fetchVersions() async throws -> SDKVersionsResponse {
        manifest
    }

    func downloadBundle(name: String) async throws -> Data {
        downloadedBundles.append(name)
        return bundles[name] ?? Data()
    }

    func fetchRules() async throws -> Data {
        Data("rules".utf8)
    }
}
