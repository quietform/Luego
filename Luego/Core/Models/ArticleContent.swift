import Foundation

struct ArticleContent: Codable {
    let title: String
    let thumbnailURL: URL?
    let description: String?
    let content: String
    let publishedDate: Date?
    let wordCount: Int?

    init(
        title: String,
        thumbnailURL: URL? = nil,
        description: String? = nil,
        content: String,
        publishedDate: Date? = nil,
        wordCount: Int? = nil
    ) {
        self.title = title
        self.thumbnailURL = thumbnailURL
        self.description = description
        self.content = content
        self.publishedDate = publishedDate
        self.wordCount = wordCount
    }
}

extension ArticleContent {
    init(from result: ParserResult, url: URL) {
        self.init(
            title: result.metadata?.title ?? url.host() ?? url.absoluteString,
            thumbnailURL: Self.parseThumbnailURL(result.metadata?.thumbnail),
            description: result.metadata?.excerpt,
            content: result.content ?? "",
            publishedDate: Self.parseDate(result.metadata?.publishedDate),
            wordCount: Self.calculateWordCount(result.content)
        )
    }

    private static func parseThumbnailURL(_ urlString: String?) -> URL? {
        guard let urlString else { return nil }
        return URL(string: urlString)
    }

    private static func parseDate(_ dateString: String?) -> Date? {
        guard let dateString else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let date = formatter.date(from: dateString) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: dateString)
    }

    private static func calculateWordCount(_ content: String?) -> Int? {
        guard let content, !content.isEmpty else { return nil }
        return content.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
    }
}
