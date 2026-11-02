import Foundation

protocol LuegoAPIDataSourceProtocol: Sendable {
    func fetchArticle(for url: URL) async throws -> LuegoAPIResponse
}

final class LuegoAPIDataSource: LuegoAPIDataSourceProtocol, Sendable {
    private let baseURL: URL
    private let apiKey: String
    private let timeout: TimeInterval
    private let userAgent: String
    private let session: URLSession

    init(
        baseURL: URL = AppConfiguration.luegoAPIBaseURL,
        apiKey: String = AppConfiguration.luegoAPIKey,
        timeout: TimeInterval = AppConfiguration.luegoAPITimeout,
        userAgent: String = AppConfiguration.luegoAPIUserAgent,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.timeout = timeout
        self.userAgent = userAgent
        self.session = session
    }

    func fetchArticle(for url: URL) async throws -> LuegoAPIResponse {
        let endpoint = baseURL.appendingPathComponent("api/luego/parse")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = timeout

        let body = ["url": url.absoluteString]
        request.httpBody = try JSONEncoder().encode(body)

        Logger.api.debug("Fetching: \(url.absoluteString)")

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            Logger.api.error("Network error: \(error.localizedDescription)")
            throw LuegoAPIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LuegoAPIError.networkError(URLError(.badServerResponse))
        }

        Logger.api.debug("Status: \(httpResponse.statusCode)")

        switch httpResponse.statusCode {
        case 200:
            return try decodeResponse(from: data)
        case 400:
            throw LuegoAPIError.invalidURL
        case 401:
            throw LuegoAPIError.unauthorized
        case 422:
            let errorMessage = extractErrorMessage(from: data)
            throw LuegoAPIError.serverError(statusCode: 422, message: errorMessage)
        case 429:
            throw LuegoAPIError.serviceUnavailable
        case 500, 502, 503:
            throw LuegoAPIError.serviceUnavailable
        default:
            throw LuegoAPIError.serverError(statusCode: httpResponse.statusCode, message: nil)
        }
    }

    private func decodeResponse(from data: Data) throws -> LuegoAPIResponse {
        do {
            let decoder = JSONDecoder()
            let response = try decoder.decode(LuegoAPIResponse.self, from: data)
            Logger.api.debug("[ThumbnailDebug] API Response - thumbnail: '\(response.metadata.thumbnail ?? "nil")'")
            return response
        } catch {
            Logger.api.error("Decoding error: \(error)")
            throw LuegoAPIError.decodingError(error)
        }
    }

    private func extractErrorMessage(from data: Data) -> String? {
        struct ErrorResponse: Decodable {
            let error: String
        }
        return try? JSONDecoder().decode(ErrorResponse.self, from: data).error
    }
}
