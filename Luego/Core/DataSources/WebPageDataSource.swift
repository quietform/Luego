import Foundation

@MainActor
protocol WebPageDataSourceProtocol: Sendable {
    func validateURL(_ url: URL) async throws -> URL
    func fetchHTML(from url: URL, timeout: TimeInterval?) async throws -> String
}

@MainActor
final class WebPageDataSource: WebPageDataSourceProtocol {
    func validateURL(_ url: URL) async throws -> URL {
        let urlString = url.absoluteString
        guard let validatedURL = validateURLString(urlString) else {
            throw ArticleMetadataError.invalidURL
        }
        return validatedURL
    }

    func fetchHTML(from url: URL, timeout: TimeInterval?) async throws -> String {
        try validateHTTPScheme(url)
        return try await fetchHTMLContent(from: url, timeout: timeout)
    }

    private func validateURLString(_ urlString: String) -> URL? {
        let trimmedURL = urlString.trimmingCharacters(in: .whitespaces)
        let urlWithScheme = addHTTPSSchemeIfNeeded(to: trimmedURL)

        guard let url = URL(string: urlWithScheme),
              (url.scheme == "http" || url.scheme == "https"),
              url.host() != nil else {
            return nil
        }

        return url
    }

    private func validateHTTPScheme(_ url: URL) throws {
        guard url.scheme == "http" || url.scheme == "https" else {
            throw ArticleMetadataError.invalidURL
        }
    }

    private func fetchHTMLContent(from url: URL, timeout: TimeInterval?) async throws -> String {
        do {
            let data: Data
            if let timeout {
                var request = URLRequest(url: url)
                request.timeoutInterval = timeout
                (data, _) = try await URLSession.shared.data(for: request)
            } else {
                (data, _) = try await URLSession.shared.data(from: url)
            }
            guard let content = String(data: data, encoding: .utf8) else {
                throw ArticleMetadataError.noMetadata
            }
            return content
        } catch {
            throw ArticleMetadataError.networkError(error)
        }
    }

    private func addHTTPSSchemeIfNeeded(to urlString: String) -> String {
        for scheme in ["http://", "https://"] {
            if urlString.lowercased().hasPrefix(scheme) {
                return scheme + urlString.dropFirst(scheme.count)
            }
        }
        return "https://" + urlString
    }
}
