import Foundation
import Testing

@MainActor
struct SDKCacheTests {
    @Test
    func sdkFilesRoundTripWithoutBlockingMainActor() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = LuegoSDKCacheDataSource(directory: directory)
        let names = AppConfiguration.sdkBundleNames
        let versions = SDKVersionsResponse(bundles: [:], rules: .init(version: "1"))
        var mainActorRan = false
        let heartbeat = Task { @MainActor in mainActorRan = true }

        await cache.saveVersions(versions)
        let progressedWhileSaving = mainActorRan
        await heartbeat.value
        for name in names { await cache.saveBundle(name: name, data: Data(name.utf8)) }
        await cache.saveRules(Data("rules".utf8))

        #expect(progressedWhileSaving)
        #expect(await cache.loadVersions()?.rules.version == "1")
        #expect(await cache.loadRules() == Data("rules".utf8))
        #expect(await cache.allBundlesExist())
        #expect(await cache.loadBundles(names: names) == Dictionary(uniqueKeysWithValues: names.map { ($0, $0) }))
        await cache.clearAll()
        #expect(await cache.loadVersions() == nil)
        #expect(await cache.allBundlesExist() == false)
    }
}
