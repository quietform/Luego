import Foundation

protocol LuegoSDKDataSourceProtocol: Sendable {
    func fetchVersions() async throws -> SDKVersionsResponse
    func downloadBundle(name: String) async throws -> Data
    func fetchRules() async throws -> Data
}

@MainActor
final class LuegoSDKDataSource: LuegoSDKDataSourceProtocol {
    private let baseURL: URL
    private let apiKey: String
    private let timeout: TimeInterval
    private let userAgent: String
    private let session: URLSession

    init(
        baseURL: URL,
        apiKey: String,
        timeout: TimeInterval,
        userAgent: String = AppConfiguration.luegoAPIUserAgent,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.timeout = timeout
        self.userAgent = userAgent
        self.session = session
    }

    func fetchVersions() async throws -> SDKVersionsResponse {
        let endpoint = baseURL.appendingPathComponent("api/luego/sdk/versions")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.timeoutInterval = timeout

        let (data, response) = try await performRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LuegoSDKError.networkUnavailable
        }

        try validateHTTPResponse(httpResponse)

        do {
            return try JSONDecoder().decode(SDKVersionsResponse.self, from: data)
        } catch {
            Logger.sdk.error("⚠ Failed to decode versions: \(error)")
            throw LuegoSDKError.parsingFailed("Failed to decode SDK versions")
        }
    }

    func downloadBundle(name: String) async throws -> Data {
        let endpoint = baseURL.appendingPathComponent("api/luego/sdk/bundles/\(name)")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.timeoutInterval = timeout * 2

        let (data, response) = try await performRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LuegoSDKError.networkUnavailable
        }

        try validateHTTPResponse(httpResponse)

        return data
    }

    func fetchRules() async throws -> Data {
        let endpoint = baseURL.appendingPathComponent("api/luego/sdk/rules")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.timeoutInterval = timeout

        let (data, response) = try await performRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LuegoSDKError.networkUnavailable
        }

        try validateHTTPResponse(httpResponse)

        return data
    }

    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        var request = request
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            return try await session.data(for: request)
        } catch {
            Logger.sdk.error("⚠ Network error: \(error.localizedDescription)")
            throw LuegoSDKError.networkUnavailable
        }
    }

    private func validateHTTPResponse(_ httpResponse: HTTPURLResponse) throws {
        switch httpResponse.statusCode {
        case 200:
            return
        case 401:
            throw LuegoAPIError.unauthorized
        case 404:
            throw LuegoSDKError.bundlesNotAvailable
        case 429, 500, 502, 503:
            throw LuegoSDKError.networkUnavailable
        default:
            throw LuegoAPIError.serverError(statusCode: httpResponse.statusCode, message: nil)
        }
    }
}
