import Foundation

nonisolated struct OPMLDataSource: Sendable {
    @concurrent
    func parse(_ data: Data) async -> [SmallWebArticleEntry] {
        OPMLParser().parse(data)
    }
}

private nonisolated final class OPMLParser: NSObject, XMLParserDelegate {
    private var articles: [SmallWebArticleEntry] = []

    func parse(_ data: Data) -> [SmallWebArticleEntry] {
        articles = []
        let parser = XMLParser(data: data.sanitizingXMLAmpersands())
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
        guard elementName == "outline" else { return }
        guard let urlString = attributeDict["xmlUrl"],
              let articleUrl = URL(string: urlString) else { return }

        let title = attributeDict["title"] ?? attributeDict["text"] ?? articleUrl.host() ?? "Unknown"
        let htmlUrl = attributeDict["htmlUrl"].flatMap { URL(string: $0) }

        articles.append(SmallWebArticleEntry(title: title, articleUrl: articleUrl, htmlUrl: htmlUrl))
    }
}
