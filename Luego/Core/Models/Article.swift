//
//  Article.swift
//  Luego
//
//  Created by Claude on 2025-11-10.
//

import Foundation
import Observation

@Observable
@MainActor
final class Article {
    var id: UUID
    var url: URL
    var title: String
    var content: String?
    var savedDate: Date
    var thumbnailURL: URL?
    var publishedDate: Date?
    var readPosition: Double
    var isFavorite: Bool
    var isArchived: Bool
    var wordCount: Int?

    var domain: String {
        url.host() ?? url.absoluteString
    }

    var readingMinutes: Int? {
        ReadingTime.minutes(wordCount: wordCount, content: content)
    }

    var estimatedReadingTime: String {
        "\(readingMinutes ?? 0) min"
    }

    init(id: UUID = UUID(), url: URL, title: String, content: String? = nil, savedDate: Date = Date(), thumbnailURL: URL? = nil, publishedDate: Date? = nil, readPosition: Double = 0.0, isFavorite: Bool = false, isArchived: Bool = false, wordCount: Int? = nil) {
        self.id = id
        self.url = url
        self.title = title
        self.content = content
        self.savedDate = savedDate
        self.thumbnailURL = thumbnailURL
        self.publishedDate = publishedDate
        self.readPosition = readPosition
        self.isFavorite = isFavorite
        self.isArchived = isArchived
        self.wordCount = wordCount
    }
}

extension Article: Identifiable, Equatable, Hashable {
    static func == (lhs: Article, rhs: Article) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension Article {
    var listMembership: ArticleListMembership {
        ArticleListMembership(isFavorite: isFavorite, isArchived: isArchived)
    }

    func applyListMembership(_ membership: ArticleListMembership) {
        if isFavorite != membership.isFavorite {
            isFavorite = membership.isFavorite
        }
        if isArchived != membership.isArchived {
            isArchived = membership.isArchived
        }
    }

    func toggleFavoriteMembership() {
        applyListMembership(listMembership.togglingFavorite())
    }

    func toggleArchiveMembership() {
        applyListMembership(listMembership.togglingArchive())
    }

    func normalizeListMembership() {
        applyListMembership(listMembership)
    }

    var excerpt: String {
        guard let content = content, !content.isEmpty else { return "" }

        let textToProcess = String(content.prefix(500))
        let stripped = textToProcess.strippingMarkdown()
        let cleaned = stripped
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        if cleaned.count <= 120 {
            return cleaned
        }

        let truncated = String(cleaned.prefix(120))
        if let lastSpace = truncated.lastIndex(of: " ") {
            return String(truncated[..<lastSpace]) + "…"
        }
        return truncated + "…"
    }
}

extension String {
    private static let codeBlockRegex = try! NSRegularExpression(
        pattern: #"```.*?```"#,
        options: [.dotMatchesLineSeparators]
    )

    private static let markdownPatterns: [(regex: NSRegularExpression, replacement: String)] = [
        (try! NSRegularExpression(pattern: #"^ {0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*$"#, options: [.anchorsMatchLines]), ""),
        (try! NSRegularExpression(pattern: #"!\[([^\]]*)\]\([^)]+\)"#, options: [.anchorsMatchLines]), ""),
        (try! NSRegularExpression(pattern: #"\[([^\]]+)\]\([^)]+\)"#, options: [.anchorsMatchLines]), "$1"),
        (try! NSRegularExpression(pattern: #"^#{1,6}\s+"#, options: [.anchorsMatchLines]), ""),
        (try! NSRegularExpression(pattern: #"\*\*([^*]+)\*\*"#, options: [.anchorsMatchLines]), "$1"),
        (try! NSRegularExpression(pattern: #"__([^_]+)__"#, options: [.anchorsMatchLines]), "$1"),
        (try! NSRegularExpression(pattern: #"\*([^*]+)\*"#, options: [.anchorsMatchLines]), "$1"),
        (try! NSRegularExpression(pattern: #"_([^_]+)_"#, options: [.anchorsMatchLines]), "$1"),
        (try! NSRegularExpression(pattern: #"~~([^~]+)~~"#, options: [.anchorsMatchLines]), "$1"),
        (try! NSRegularExpression(pattern: #"`([^`]+)`"#, options: [.anchorsMatchLines]), "$1"),
        (try! NSRegularExpression(pattern: #"^>\s+"#, options: [.anchorsMatchLines]), ""),
        (try! NSRegularExpression(pattern: #"^[-*+]\s+"#, options: [.anchorsMatchLines]), ""),
        (try! NSRegularExpression(pattern: #"^\d+\.\s+"#, options: [.anchorsMatchLines]), ""),
    ]

    func strippingMarkdown() -> String {
        var result = self

        result = Self.codeBlockRegex.stringByReplacingMatches(
            in: result,
            options: [],
            range: NSRange(result.startIndex..., in: result),
            withTemplate: ""
        )

        for (regex, replacement) in Self.markdownPatterns {
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: NSRange(result.startIndex..., in: result),
                withTemplate: replacement
            )
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension Article {
    static let sampleArticles: [Article] = [
        Article(
            url: URL(string: "https://www.example.com/article1")!,
            title: "Understanding SwiftUI State Management",
            content: "Sample content about SwiftUI state...",
            savedDate: Date().addingTimeInterval(-86400),
            thumbnailURL: URL(string: "https://www.example.com/image1.jpg"),
            publishedDate: Date().addingTimeInterval(-172800)
        ),
        Article(
            url: URL(string: "https://www.medium.com/article2")!,
            title: "Building iOS Apps in 2025",
            content: "Sample content about iOS development...",
            savedDate: Date().addingTimeInterval(-3600),
            thumbnailURL: URL(string: "https://www.medium.com/image2.jpg"),
            publishedDate: Date().addingTimeInterval(-7200)
        ),
        Article(
            url: URL(string: "https://www.blog.com/article3")!,
            title: "The Future of Mobile Development",
            savedDate: Date(),
            publishedDate: Date().addingTimeInterval(-604800)
        )
    ]
}
