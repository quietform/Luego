import Foundation

struct BlogPostEntry: Sendable {
    let title: String?
    let postURL: URL
    let publishedDate: Date?
}

nonisolated struct GenericRSSDataSource: Sendable {
    @concurrent
    func parse(_ data: Data) async -> [BlogPostEntry] {
        let parser = GenericRSSParser()
        return parser.parse(data.sanitizingXMLAmpersands())
    }

    @concurrent
    func discoverFeedURL(in data: Data, baseURL: URL) async -> URL? {
        guard let html = String(data: data, encoding: .utf8),
              let linkRegex = try? NSRegularExpression(pattern: #"<link\b[^>]*>"#, options: .caseInsensitive),
              let hrefRegex = try? NSRegularExpression(pattern: #"href\s*=\s*["']([^"']+)["']"#, options: .caseInsensitive) else {
            return nil
        }
        for match in linkRegex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let tagRange = Range(match.range, in: html) else { continue }
            let tag = String(html[tagRange])
            let lowercasedTag = tag.lowercased()
            guard lowercasedTag.contains("alternate"),
                  lowercasedTag.contains("application/rss+xml") || lowercasedTag.contains("application/atom+xml"),
                  let hrefMatch = hrefRegex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
                  let hrefRange = Range(hrefMatch.range(at: 1), in: tag) else {
                continue
            }
            return URL(string: String(tag[hrefRange]), relativeTo: baseURL)?.absoluteURL
        }
        return nil
    }
}

private nonisolated final class GenericRSSParser: NSObject, XMLParserDelegate {
    private var posts: [BlogPostEntry] = []
    private var currentElement: String = ""
    private var currentTitle: String = ""
    private var currentLink: String = ""
    private var currentPubDate: String = ""
    private var isAtomFeed = false
    private var isInItem = false

    func parse(_ data: Data) -> [BlogPostEntry] {
        posts = []
        isAtomFeed = false
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return posts
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName

        if elementName == "feed" {
            isAtomFeed = true
        }

        if elementName == "item" || elementName == "entry" {
            isInItem = true
            currentTitle = ""
            currentLink = ""
            currentPubDate = ""
        }

        if isAtomFeed && elementName == "link" && isInItem {
            let relation = attributeDict["rel"] ?? "alternate"
            if let href = attributeDict["href"], relation == "alternate" {
                currentLink = href
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard isInItem else { return }

        switch currentElement {
        case "title":
            currentTitle += string
        case "link" where !isAtomFeed:
            currentLink += string
        case "pubDate", "published", "updated":
            currentPubDate += string
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard isInItem, currentElement == "title",
              let cdataString = String(data: CDATABlock, encoding: .utf8) else {
            return
        }
        currentTitle += cdataString
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == "item" || elementName == "entry" {
            processCurrentItem()
            isInItem = false
        }
        currentElement = ""
    }

    private func processCurrentItem() {
        let trimmedLink = currentLink.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let postURL = URL(string: trimmedLink) else { return }

        let title = currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let date = parsePublishedDate(currentPubDate)

        posts.append(BlogPostEntry(
            title: title.isEmpty ? nil : title,
            postURL: postURL,
            publishedDate: date
        ))
    }

    private func parsePublishedDate(_ dateString: String) -> Date? {
        let trimmed = dateString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let rfc822Formatter = DateFormatter()
        rfc822Formatter.locale = Locale(identifier: "en_US_POSIX")
        rfc822Formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        if let date = rfc822Formatter.date(from: trimmed) {
            return date
        }

        rfc822Formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let date = rfc822Formatter.date(from: trimmed) {
            return date
        }

        let iso8601Formatter = ISO8601DateFormatter()
        iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso8601Formatter.date(from: trimmed) {
            return date
        }

        iso8601Formatter.formatOptions = [.withInternetDateTime]
        return iso8601Formatter.date(from: trimmed)
    }
}
