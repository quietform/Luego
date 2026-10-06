import Foundation
import Testing

@MainActor
struct ReaderViewModelTests {
    @Test(arguments: [false, true], [false, true])
    func canceledReaderRequestDoesNotPublishLateResult(forceRefresh: Bool, networkError: Bool) async {
        let article = Article(url: URL(string: "https://example.com/article")!, title: "Original")
        let service = SuspendedReaderService()
        let viewModel = ReaderViewModel(article: article, readerService: service)
        let previousContent = forceRefresh ? "Previously loaded body" : nil
        viewModel.articleContent = previousContent
        let task = Task {
            if forceRefresh {
                await viewModel.refreshContent()
            } else {
                await viewModel.loadContent()
            }
        }
        var started = service.started.stream.makeAsyncIterator()
        _ = await started.next()
        task.cancel()
        service.completeFetch(networkError: networkError)
        await task.value

        #expect(service.canceledRequests[0] == true)
        #expect(viewModel.article === article)
        #expect(viewModel.articleContent == previousContent)
        #expect(viewModel.errorMessage == nil)
        #expect(!viewModel.isLoading)
        #expect(service.requestedRefreshes == [forceRefresh])
    }

    @Test
    func canceledPreviousLoadDoesNotClearNewRefreshState() async {
        let article = Article(url: URL(string: "https://example.com/article")!, title: "Original")
        let service = SuspendedReaderService()
        let viewModel = ReaderViewModel(article: article, readerService: service)
        var started = service.started.stream.makeAsyncIterator()
        let first = Task { await viewModel.loadContent() }
        _ = await started.next()
        let refresh = Task { await viewModel.refreshContent() }
        _ = await started.next()

        service.completeFetch(at: 0)
        await first.value

        #expect(service.canceledRequests[0] == true)
        #expect(viewModel.isLoading)
        #expect(viewModel.articleContent == nil)
        #expect(viewModel.errorMessage == nil)

        service.completeFetch(at: 1)
        await refresh.value

        #expect(viewModel.articleContent == "Loaded body 1")
        #expect(!viewModel.isLoading)
        #expect(service.requestedRefreshes == [false, true])
    }


}

@MainActor
private final class SuspendedReaderService: ReaderServiceProtocol {
    let started = AsyncStream<Void>.makeStream()
    private(set) var requestedRefreshes: [Bool] = []
    private(set) var canceledRequests: [Int: Bool] = [:]
    private var completions: [Int: CheckedContinuation<Void, Error>] = [:]

    func fetchContent(for article: Article, forceRefresh: Bool) async throws -> Article {
        let index = requestedRefreshes.count
        requestedRefreshes.append(forceRefresh)
        defer { canceledRequests[index] = Task.isCancelled }
        try await withCheckedThrowingContinuation { continuation in
            completions[index] = continuation
            started.continuation.yield(())
        }
        return Article(id: article.id, url: article.url, title: "Updated", content: "Loaded body \(index)")
    }

    func completeFetch(at index: Int = 0, networkError: Bool = false) {
        if networkError {
            completions.removeValue(forKey: index)?.resume(throwing: LuegoAPIError.networkError(URLError(.cancelled)))
        } else {
            completions.removeValue(forKey: index)?.resume()
        }
    }

    func updateReadPosition(articleId: UUID, position: Double) async throws {}
}
