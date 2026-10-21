import Foundation
import CryptoKit

@MainActor
protocol ParsedContentCacheDataSourceProtocol: Sendable {
    func get(for url: URL) async -> ArticleContent?
    func save(_ content: ArticleContent, for url: URL) async
    func clear() async
    func remove(for url: URL) async
}

@MainActor
final class ParsedContentCacheDataSource: ParsedContentCacheDataSourceProtocol {
    private let storage: FileCache
    private let cacheDirectory: URL

    init(storage: FileCache = FileCache(), directory: URL? = nil) {
        self.storage = storage
        cacheDirectory = directory ?? (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory).appendingPathComponent("ParsedContent")
    }

    func get(for url: URL) async -> ArticleContent? {
        await storage.readJSON(CachedContent.self, from: cacheFileURL(for: url))?.content
    }

    func save(_ content: ArticleContent, for url: URL) async {
        await storage.writeJSON(CachedContent(content: content), to: cacheFileURL(for: url))
    }

    func clear() async {
        await storage.remove(cacheDirectory)
    }

    func remove(for url: URL) async {
        await storage.remove(cacheFileURL(for: url))
    }

    private func cacheFileURL(for url: URL) -> URL {
        let hash = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = hash.map { String(format: "%02x", $0) }.joined()
        return cacheDirectory.appendingPathComponent("\(name).json")
    }
}

private nonisolated struct CachedContent: Codable, Sendable {
    let content: ArticleContent
}
