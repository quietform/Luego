import Foundation

nonisolated struct BlogrollRSSDataSource: Sendable {
    @concurrent
    func parse(_ data: Data) async -> [SmallWebArticleEntry] {
        let parser = BlogrollRSSParser()
        return parser.parse(data.sanitizingXMLAmpersands())
    }

    @concurrent
    func parseHomepage(_ data: Data) async -> [SmallWebArticleEntry] {
        guard let html = String(data: data, encoding: .utf8),
              let regex = try? NSRegularExpression(
                  pattern: #"<a class="entry-main" href="([^"]+)"[^>]*>\s*<h1 class="entry-title">([^<]*)</h1>"#
              ) else {
            return []
        }
        return regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).compactMap { match in
            guard let urlRange = Range(match.range(at: 1), in: html),
                  let titleRange = Range(match.range(at: 2), in: html),
                  let siteURL = URL(string: String(html[urlRange])) else {
                return nil
            }
            let title = html[titleRange].trimmingCharacters(in: .whitespacesAndNewlines)
            return SmallWebArticleEntry(title: title, articleUrl: siteURL, htmlUrl: siteURL)
        }
    }
}

private nonisolated final class BlogrollRSSParser: NSObject, XMLParserDelegate {
    private var articles: [SmallWebArticleEntry] = []
    private var currentElement: String = ""
    private var currentTitle: String = ""
    private var currentLink: String = ""
    private var currentDescription: String = ""

    func parse(_ data: Data) -> [SmallWebArticleEntry] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return articles
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName

        if elementName == "item" {
            currentTitle = ""
            currentLink = ""
            currentDescription = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        switch currentElement {
        case "title":
            currentTitle += string
        case "link":
            currentLink += string
        case "description":
            currentDescription += string
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard currentElement == "description",
              let cdataString = String(data: CDATABlock, encoding: .utf8) else {
            return
        }
        currentDescription += cdataString
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == "item" {
            processCurrentItem()
        }
        currentElement = ""
    }

    private func processCurrentItem() {
        let trimmedTitle = currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLink = currentLink.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedTitle.isEmpty,
              let websiteURL = URL(string: trimmedLink) else {
            return
        }

        guard let feedURL = extractFeedURL(from: currentDescription) else {
            return
        }

        articles.append(SmallWebArticleEntry(
            title: trimmedTitle,
            articleUrl: feedURL,
            htmlUrl: websiteURL
        ))
    }

    private func extractFeedURL(from description: String) -> URL? {
        let pattern = #"href='\{([^}]+)\}'"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: description, range: NSRange(description.startIndex..., in: description)),
              let urlRange = Range(match.range(at: 1), in: description) else {
            return nil
        }
        return URL(string: String(description[urlRange]))
    }
}
