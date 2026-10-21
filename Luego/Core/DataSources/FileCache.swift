import Foundation

actor FileCache {
    private let fileManager = FileManager.default

    func readJSON<Value: Decodable & Sendable>(_ type: Value.Type, from url: URL) -> Value? {
        guard let data = readData(from: url) else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            try? fileManager.removeItem(at: url)
            return nil
        }
    }

    func writeJSON<Value: Encodable & Sendable>(_ value: Value, to url: URL) {
        do {
            let data = try JSONEncoder().encode(value)
            writeData(data, to: url)
        } catch {
            Logger.cache.error("Failed to write cache: \(error)")
        }
    }

    func readData(from url: URL) -> Data? {
        try? Data(contentsOf: url)
    }

    func readStrings(from urls: [String: URL]) -> [String: String]? {
        var strings: [String: String] = [:]
        for (name, url) in urls {
            guard let data = readData(from: url), let string = String(data: data, encoding: .utf8) else { return nil }
            strings[name] = string
        }
        return strings
    }

    func writeData(_ data: Data, to url: URL) {
        do {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            Logger.cache.error("Failed to write cache: \(error)")
        }
    }

    func contains(_ urls: [URL]) -> Bool {
        urls.allSatisfy { fileManager.fileExists(atPath: $0.path) }
    }

    func remove(_ url: URL) {
        try? fileManager.removeItem(at: url)
    }
}
