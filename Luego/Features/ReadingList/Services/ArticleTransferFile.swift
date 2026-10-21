import Foundation

nonisolated enum ArticleTransferFile {
    private static var exportDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("LuegoExports", isDirectory: true)
    }

    @concurrent
    static func read(_ url: URL) async throws -> String {
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer { if didStartAccess { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        for encoding in [String.Encoding.utf8, .unicode, .utf16, .utf16LittleEndian, .utf16BigEndian] {
            if let text = String(data: data, encoding: encoding) {
                return text
            }
        }
        throw CocoaError(.fileReadInapplicableStringEncoding)
    }

    @concurrent
    static func write(_ export: SavedArticlePlainTextExport) async throws -> URL {
        let directory = exportDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(export.filename)
        do {
            try export.body.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    @concurrent
    static func remove(_ url: URL) async {
        let directory = url.deletingLastPathComponent()
        guard directory.deletingLastPathComponent() == exportDirectory else { return }
        try? FileManager.default.removeItem(at: directory)
    }
}
