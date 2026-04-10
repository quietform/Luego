import Foundation

enum SharedTextURLExtractor {
    nonisolated static func isSupportedWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else {
            return false
        }

        return scheme == "http" || scheme == "https"
    }

    nonisolated static func extractSupportedWebURLs(from text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }

        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, options: [], range: range)
            .compactMap(\.url)
            .filter(isSupportedWebURL)
    }

    nonisolated static func extractFirstSupportedWebURL(from text: String) -> URL? {
        extractSupportedWebURLs(from: text).first
    }
}
