import Foundation

struct SavedArticleImportFailureSample: Sendable, Equatable {
    let urlString: String
    let message: String
}

struct SavedArticleImportResult: Sendable, Equatable {
    let detectedURLCount: Int
    let uniqueURLCount: Int
    let importedCount: Int
    let skippedExistingCount: Int
    let skippedDuplicateInputCount: Int
    let failedCount: Int
    let failureSamples: [SavedArticleImportFailureSample]

    var didFindURLs: Bool {
        detectedURLCount > 0
    }
}

@MainActor
protocol SavedArticleImportServiceProtocol: Sendable {
    func importArticles(fromPlainText text: String) async -> SavedArticleImportResult
}

@MainActor
final class SavedArticleImportService: SavedArticleImportServiceProtocol {
    private let articleService: ArticleServiceProtocol

    init(articleService: ArticleServiceProtocol) {
        self.articleService = articleService
    }

    func importArticles(fromPlainText text: String) async -> SavedArticleImportResult {
        let detectedURLs = SharedTextURLExtractor.extractSupportedWebURLs(from: text)
        let deduplicatedInput = deduplicateInputURLs(detectedURLs)
        let baseSavedDate = Date()

        var skippedDuplicateInputCount = detectedURLs.count - deduplicatedInput.count
        var skippedExistingCount = 0
        var importedCount = 0
        var failedCount = 0
        var failureSamples: [SavedArticleImportFailureSample] = []
        var validatedSeen: Set<String> = []

        for (index, inputURL) in deduplicatedInput.enumerated() {
            do {
                let result = try await articleService.addArticle(
                    url: inputURL,
                    savedDate: baseSavedDate.addingTimeInterval(-Double(index))
                )
                if !validatedSeen.insert(result.article.url.absoluteString).inserted {
                    skippedDuplicateInputCount += 1
                } else if result.isNew {
                    importedCount += 1
                } else {
                    skippedExistingCount += 1
                }
            } catch {
                failedCount += 1
                appendFailure(
                    urlString: inputURL.absoluteString,
                    message: error.localizedDescription,
                    to: &failureSamples
                )
            }
        }

        let uniqueURLCount = max(0, detectedURLs.count - skippedDuplicateInputCount)

        return SavedArticleImportResult(
            detectedURLCount: detectedURLs.count,
            uniqueURLCount: uniqueURLCount,
            importedCount: importedCount,
            skippedExistingCount: skippedExistingCount,
            skippedDuplicateInputCount: skippedDuplicateInputCount,
            failedCount: failedCount,
            failureSamples: failureSamples
        )
    }

    private func deduplicateInputURLs(_ urls: [URL]) -> [URL] {
        var seen: Set<String> = []
        var deduplicated: [URL] = []

        for url in urls {
            if seen.insert(url.absoluteString).inserted {
                deduplicated.append(url)
            }
        }

        return deduplicated
    }

    private func appendFailure(
        urlString: String,
        message: String,
        to samples: inout [SavedArticleImportFailureSample]
    ) {
        guard samples.count < 5 else {
            return
        }

        samples.append(
            SavedArticleImportFailureSample(
                urlString: urlString,
                message: message
            )
        )
    }
}
