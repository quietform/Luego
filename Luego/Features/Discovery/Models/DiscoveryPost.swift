import Foundation

struct DiscoveryPost: Hashable, Identifiable, Sendable {
    let url: URL
    let title: String
    let publishedDate: Date?
    var excerpt: String?
    var thumbnailURL: URL?

    var id: URL { url }

    var domain: String {
        url.host() ?? url.absoluteString
    }

    func displayDate(relativeTo now: Date) -> Date? {
        guard let publishedDate, publishedDate <= now else { return nil }
        return publishedDate
    }
}
