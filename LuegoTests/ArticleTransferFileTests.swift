import Foundation
import Testing

@MainActor
struct ArticleTransferFileTests {
    @Test(arguments: ["read", "write"])
    func acceptedTransferFinishesInCancelledTask(operation: String) async throws {
        let export = SavedArticlePlainTextExport(filename: "cancelled.txt", body: "Body", articleCount: 1, scope: .allArticles)
        let url = try await ArticleTransferFile.write(export)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let transfer = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            if operation == "read" {
                #expect(try await ArticleTransferFile.read(url) == export.body)
            } else {
                let written = try await ArticleTransferFile.write(export)
                #expect(try String(contentsOf: written, encoding: .utf8) == export.body)
                await ArticleTransferFile.remove(written)
            }
        }
        try await transfer.value
    }

    @Test(arguments: [String.Encoding.utf8, .utf16])
    func transferRoundTripsTextWithoutBlockingMainActor(encoding: String.Encoding) async throws {
        let export = SavedArticlePlainTextExport(filename: "luego-test-\(UUID()).txt", body: "https://example.com/one\nhttps://example.com/தமிழ்", articleCount: 2, scope: .allArticles)
        var mainActorRan = false
        let heartbeat = Task { @MainActor in mainActorRan = true }

        let url = try await ArticleTransferFile.write(export)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let progressedWhileWriting = mainActorRan
        await heartbeat.value
        try export.body.data(using: encoding)!.write(to: url)
        let text = try await ArticleTransferFile.read(url)
        await ArticleTransferFile.remove(url)

        #expect(progressedWhileWriting)
        #expect(text == export.body)
        #expect(url.lastPathComponent == export.filename)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}
