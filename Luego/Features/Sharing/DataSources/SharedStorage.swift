import Foundation

struct SharedURL: Codable, Sendable {
    let url: URL
    let timestamp: Date
}

enum SharedStorageError: LocalizedError, Sendable {
    case appGroupUnavailable
    case sharedQueueDecodeFailed
    case sharedQueueEncodeFailed

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            return "Shared storage is unavailable"
        case .sharedQueueDecodeFailed:
            return "Failed to read shared items"
        case .sharedQueueEncodeFailed:
            return "Failed to save shared items"
        }
    }
}

@MainActor
protocol SharedStorageDataSourceProtocol: Sendable {
    func saveSharedURL(_ url: URL) throws
    func getSharedURLs() throws -> [SharedURL]
    func replaceSharedURLs(_ sharedURLs: [SharedURL]) throws
    func clearSharedURLs() throws
}

@MainActor
final class SharedStorage: SharedStorageDataSourceProtocol {
    static let shared = SharedStorage()

    #if os(iOS)
    private let appGroupIdentifier = "group.com.esoxjem.Luego"
    private let sharedURLsKey = "sharedURLs"
    #endif

    private init() {}

    func saveSharedURL(_ url: URL) throws {
        #if os(iOS)
        var sharedURLs = try getSharedURLs()
        let sharedURL = SharedURL(url: url, timestamp: Date())
        sharedURLs.append(sharedURL)
        try replaceSharedURLs(sharedURLs)
        #endif
    }

    func getSharedURLs() throws -> [SharedURL] {
        #if os(iOS)
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier),
              let data = userDefaults.data(forKey: sharedURLsKey) else {
            return []
        }

        guard let sharedURLs = try? JSONDecoder().decode([SharedURL].self, from: data) else {
            throw SharedStorageError.sharedQueueDecodeFailed
        }

        return sharedURLs
        #else
        return []
        #endif
    }

    func replaceSharedURLs(_ sharedURLs: [SharedURL]) throws {
        #if os(iOS)
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            throw SharedStorageError.appGroupUnavailable
        }

        guard let encoded = try? JSONEncoder().encode(sharedURLs) else {
            throw SharedStorageError.sharedQueueEncodeFailed
        }

        userDefaults.set(encoded, forKey: sharedURLsKey)
        #endif
    }

    func clearSharedURLs() throws {
        #if os(iOS)
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            throw SharedStorageError.appGroupUnavailable
        }

        userDefaults.removeObject(forKey: sharedURLsKey)
        #endif
    }
}
