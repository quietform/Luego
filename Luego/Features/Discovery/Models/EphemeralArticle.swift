import Foundation

struct EphemeralArticle: Sendable {
    let url: URL
    let title: String
    let content: String
    let thumbnailURL: URL?
    let publishedDate: Date?
    let feedTitle: String
}
