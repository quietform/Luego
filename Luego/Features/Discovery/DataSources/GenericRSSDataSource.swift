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
    private var currentContent: String = ""
    private var currentDeclaredImages: [String] = []
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
            currentContent = ""
            currentDeclaredImages = []
        }

        if isInItem, let url = attributeDict["url"], Self.declaresImage(elementName, attributes: attributeDict) {
            currentDeclaredImages.append(url)
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
        case "content:encoded":
            currentContent += string
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
        case "content:encoded":
            currentContent += cdataString
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
            imageURL: FeedThumbnail.url(
                for: postURL,
                summary: currentSummary,
                declaredImages: currentDeclaredImages,
                content: currentContent
            )
        ))
    }

    private static func declaresImage(_ elementName: String, attributes: [String: String]) -> Bool {
        switch elementName {
        case "media:thumbnail":
            return true
        case "media:content":
            return attributes["medium"] == "image" || attributes["type"]?.hasPrefix("image/") == true
        case "enclosure":
            return attributes["type"]?.hasPrefix("image/") == true
        default:
            return false
        }
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

private nonisolated enum FeedThumbnail {
    static func url(for postURL: URL, summary: String, declaredImages: [String], content: String) -> URL? {
        firstUsable(SummaryHTML.imageSources(in: summary), relativeTo: postURL)
            ?? firstUsable(declaredImages, relativeTo: postURL)
            ?? firstUsable(SummaryHTML.imageSources(in: content), relativeTo: postURL)
    }

    private static func firstUsable(_ sources: [String], relativeTo postURL: URL) -> URL? {
        sources.lazy
            .compactMap { URL(string: $0, relativeTo: postURL)?.absoluteURL }
            .first(where: isUsable)
    }

    private static func isUsable(_ url: URL) -> Bool {
        (url.scheme == "https" || url.scheme == "http") && url.host()?.hasSuffix("gravatar.com") != true
    }
}

private nonisolated enum SummaryHTML {
    static func excerpt(from html: String) -> String? {
        var text = html.replacingOccurrences(of: #"<[^>]*>"#, with: " ", options: .regularExpression)
        text = decodingEntities(in: text)
        let words = text.split { $0.isWhitespace }.prefix(60)
        guard !words.isEmpty else { return nil }
        return words.joined(separator: " ")
    }

    static func imageSources(in html: String) -> [String] {
        guard let imageRegex = try? NSRegularExpression(pattern: #"<img\b[^>]*>"#, options: .caseInsensitive) else { return [] }
        return imageRegex.matches(in: html, range: NSRange(html.startIndex..., in: html)).compactMap { match in
            guard let tagRange = Range(match.range, in: html) else { return nil }
            let tag = String(html[tagRange])
            return isTrackingPixel(tag) ? nil : attribute("src", in: tag)
        }
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

    private static func decodingEntities(in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"&(?:#([xX]?)([0-9a-fA-F]+)|([a-zA-Z][a-zA-Z0-9]*));"#) else { return text }
        var result = text
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range, in: result),
                  let replacement = replacement(for: match, in: text) else {
                continue
            }
            result.replaceSubrange(range, with: replacement)
        }
        return result
    }

    private static func replacement(for match: NSTextCheckingResult, in text: String) -> String? {
        if let nameRange = Range(match.range(at: 3), in: text) {
            return HTMLEntity.named[String(text[nameRange])]
        }
        guard let radixRange = Range(match.range(at: 1), in: text),
              let digitsRange = Range(match.range(at: 2), in: text),
              let value = UInt32(text[digitsRange], radix: text[radixRange].isEmpty ? 10 : 16),
              let scalar = Unicode.Scalar(value) else {
            return nil
        }
        return String(Character(scalar))
    }
}

private nonisolated enum HTMLEntity {
    static let named: [String: String] = [
        "nbsp": "\u{A0}", "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "lsquo": "‘",
        "rsquo": "’", "sbquo": "‚", "ldquo": "“", "rdquo": "”", "bdquo": "„", "laquo": "«", "raquo": "»",
        "lsaquo": "‹", "rsaquo": "›", "hellip": "…", "mdash": "—", "ndash": "–", "bull": "•", "middot": "·",
        "prime": "′", "Prime": "″", "ensp": "\u{2002}", "emsp": "\u{2003}", "thinsp": "\u{2009}",
        "shy": "\u{AD}", "iexcl": "¡", "iquest": "¿",
        "copy": "©", "reg": "®", "trade": "™", "deg": "°", "times": "×", "divide": "÷", "plusmn": "±",
        "frac14": "¼", "frac12": "½", "frac34": "¾", "sup1": "¹", "sup2": "²", "sup3": "³", "micro": "µ",
        "euro": "€", "pound": "£", "yen": "¥", "cent": "¢", "curren": "¤", "sect": "§", "para": "¶",
        "dagger": "†", "Dagger": "‡", "permil": "‰", "larr": "←", "rarr": "→", "uarr": "↑", "darr": "↓",
        "Agrave": "À", "Aacute": "Á", "Acirc": "Â", "Atilde": "Ã", "Auml": "Ä", "Aring": "Å", "AElig": "Æ",
        "Ccedil": "Ç", "Egrave": "È", "Eacute": "É", "Ecirc": "Ê", "Euml": "Ë", "Igrave": "Ì", "Iacute": "Í",
        "Icirc": "Î", "Iuml": "Ï", "ETH": "Ð", "Ntilde": "Ñ", "Ograve": "Ò", "Oacute": "Ó", "Ocirc": "Ô",
        "Otilde": "Õ", "Ouml": "Ö", "Oslash": "Ø", "Ugrave": "Ù", "Uacute": "Ú", "Ucirc": "Û", "Uuml": "Ü",
        "Yacute": "Ý", "THORN": "Þ", "szlig": "ß", "agrave": "à", "aacute": "á", "acirc": "â", "atilde": "ã",
        "auml": "ä", "aring": "å", "aelig": "æ", "ccedil": "ç", "egrave": "è", "eacute": "é", "ecirc": "ê",
        "euml": "ë", "igrave": "ì", "iacute": "í", "icirc": "î", "iuml": "ï", "eth": "ð", "ntilde": "ñ",
        "ograve": "ò", "oacute": "ó", "ocirc": "ô", "otilde": "õ", "ouml": "ö", "oslash": "ø", "ugrave": "ù",
        "uacute": "ú", "ucirc": "û", "uuml": "ü", "yacute": "ý", "thorn": "þ", "yuml": "ÿ", "OElig": "Œ",
        "oelig": "œ", "Scaron": "Š", "scaron": "š", "Yuml": "Ÿ", "fnof": "ƒ"
    ]
}
