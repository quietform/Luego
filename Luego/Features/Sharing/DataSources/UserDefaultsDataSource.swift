import Foundation

@MainActor
protocol UserDefaultsDataSourceProtocol: Sendable {
    func getSharedURLs() throws -> [SharedURL]
    func replaceSharedURLs(_ sharedURLs: [SharedURL]) throws
}

@MainActor
final class UserDefaultsDataSource: UserDefaultsDataSourceProtocol {
    private let sharedStorage: SharedStorageDataSourceProtocol

    init(sharedStorage: SharedStorageDataSourceProtocol) {
        self.sharedStorage = sharedStorage
    }

    func getSharedURLs() throws -> [SharedURL] {
        try sharedStorage.getSharedURLs()
    }

    func replaceSharedURLs(_ sharedURLs: [SharedURL]) throws {
        try sharedStorage.replaceSharedURLs(sharedURLs)
    }
}
