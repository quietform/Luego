import Foundation

struct BlogPostEntry: Sendable {
    let title: String?
    let postURL: URL
    let publishedDate: Date?
    var excerpt: String?
    var imageURL: URL?
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
    private var currentSummary: String = ""
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
            currentSummary = ""
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
        case "summary", "description", "content":
            currentSummary += string
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard isInItem, let cdataString = String(data: CDATABlock, encoding: .utf8) else { return }
        switch currentElement {
        case "title":
            currentTitle += cdataString
        case "summary", "description", "content":
            currentSummary += cdataString
        default:
            break
        }
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
            publishedDate: date,
            excerpt: SummaryHTML.excerpt(from: currentSummary),
            imageURL: SummaryHTML.firstImageURL(in: currentSummary)
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

private nonisolated enum SummaryHTML {
    private static let entities = [
        "&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'"
    ]

    static func excerpt(from html: String) -> String? {
        var text = html.replacingOccurrences(of: #"<[^>]*>"#, with: " ", options: .regularExpression)
        text = decodingNumericEntities(in: text)
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        let words = text.split { $0.isWhitespace }.prefix(60)
        guard !words.isEmpty else { return nil }
        return words.joined(separator: " ")
    }

    static func firstImageURL(in html: String) -> URL? {
        guard let imageRegex = try? NSRegularExpression(pattern: #"<img\b[^>]*>"#, options: .caseInsensitive) else { return nil }
        for match in imageRegex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let tagRange = Range(match.range, in: html) else { continue }
            let tag = String(html[tagRange])
            guard !isTrackingPixel(tag),
                  let source = attribute("src", in: tag),
                  let url = URL(string: source),
                  url.scheme == "https" || url.scheme == "http" else {
                continue
            }
            return url
        }
        return nil
    }

    private static func isTrackingPixel(_ tag: String) -> Bool {
        attribute("width", in: tag) == "1" || attribute("height", in: tag) == "1"
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"\b\#(name)\s*=\s*["']([^"']*)["']"#, options: .caseInsensitive),
              let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
              let range = Range(match.range(at: 1), in: tag) else {
            return nil
        }
        return String(tag[range])
    }

    private static func decodingNumericEntities(in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"&#(x?)([0-9a-fA-F]+);"#) else { return text }
        var result = text
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range, in: result),
                  let hexRange = Range(match.range(at: 1), in: text),
                  let digitsRange = Range(match.range(at: 2), in: text),
                  let value = UInt32(text[digitsRange], radix: text[hexRange].isEmpty ? 10 : 16),
                  let scalar = Unicode.Scalar(value) else {
                continue
            }
            result.replaceSubrange(range, with: String(Character(scalar)))
        }
        return result
    }
}
