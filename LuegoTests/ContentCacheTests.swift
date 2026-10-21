import Foundation
import Testing

@MainActor
struct ContentCacheTests {
    @Test
    func acceptedRemovalFinishesInCancelledTask() async {
        let cache = ParsedContentCacheDataSource()
        let url = URL(string: "https://example.com/\(UUID())")!
        await cache.save(ArticleContent(title: "Saved", content: "Saved body"), for: url)
        let removal = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await cache.remove(for: url)
        }
        await removal.value
        let content = await cache.get(for: url)
        await cache.remove(for: url)

        #expect(content == nil)
    }

    @Test
    func acceptedSaveFinishesInCancelledTask() async {
        let cache = ParsedContentCacheDataSource()
        let url = URL(string: "https://example.com/\(UUID())")!
        let save = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await cache.save(ArticleContent(title: "Cancelled", content: "Body"), for: url)
        }
        await save.value
        let content = await cache.get(for: url)
        await cache.remove(for: url)

        #expect(content?.content == "Body")
    }

    @Test
    func savingAndReadingContentKeepsMainActorResponsive() async {
        let cache = ParsedContentCacheDataSource()
        let url = URL(string: "https://example.com/\(UUID())")!
        let body = String(repeating: "Article body. ", count: 1_000)
        var mainActorRan = false
        let heartbeat = Task { @MainActor in mainActorRan = true }

        await cache.save(ArticleContent(title: "Article", content: body), for: url)
        let progressedWhileSaving = mainActorRan
        await heartbeat.value
        let saved = await cache.get(for: url)
        await cache.remove(for: url)

        #expect(progressedWhileSaving)
        #expect(saved?.content == body)
        #expect(await cache.get(for: url) == nil)
    }
}
