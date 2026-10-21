import Foundation

protocol LuegoSDKCacheDataSourceProtocol: Sendable {
    func loadBundles(names: [String]) async -> [String: String]?
    func saveBundle(name: String, data: Data) async
    func loadRules() async -> Data?
    func saveRules(_ data: Data) async
    func loadVersions() async -> SDKVersionsResponse?
    func saveVersions(_ versions: SDKVersionsResponse) async
    func bundleExists(name: String) async -> Bool
    func rulesExist() async -> Bool
    func allBundlesExist() async -> Bool
    func clearAll() async
}

@MainActor
final class LuegoSDKCacheDataSource: LuegoSDKCacheDataSourceProtocol {
    private let storage: FileCache
    private let sdkDirectory: URL

    init(storage: FileCache = FileCache(), directory: URL? = nil) {
        self.storage = storage
        sdkDirectory = directory ?? (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory).appendingPathComponent("LuegoSDK")
    }

    private func bundleURL(_ name: String) -> URL {
        sdkDirectory.appendingPathComponent("bundles/\(name).js")
    }

    func loadBundles(names: [String]) async -> [String: String]? {
        await storage.readStrings(from: Dictionary(uniqueKeysWithValues: names.map { ($0, bundleURL($0)) }))
    }

    func saveBundle(name: String, data: Data) async {
        await storage.writeData(data, to: bundleURL(name))
    }

    func loadRules() async -> Data? {
        await storage.readData(from: sdkDirectory.appendingPathComponent("rules.json"))
    }

    func saveRules(_ data: Data) async {
        await storage.writeData(data, to: sdkDirectory.appendingPathComponent("rules.json"))
    }

    func loadVersions() async -> SDKVersionsResponse? {
        await storage.readJSON(SDKVersionsResponse.self, from: sdkDirectory.appendingPathComponent("versions.json"))
    }

    func saveVersions(_ versions: SDKVersionsResponse) async {
        await storage.writeJSON(versions, to: sdkDirectory.appendingPathComponent("versions.json"))
    }

    func bundleExists(name: String) async -> Bool {
        await storage.contains([bundleURL(name)])
    }

    func rulesExist() async -> Bool {
        await storage.contains([sdkDirectory.appendingPathComponent("rules.json")])
    }

    func allBundlesExist() async -> Bool {
        await storage.contains(AppConfiguration.sdkBundleNames.map(bundleURL))
    }

    func clearAll() async {
        await storage.remove(sdkDirectory)
    }
}
