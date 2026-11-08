import Foundation
import Testing

@MainActor
struct LuegoSDKDataSourceCacheTests {
    private let baseURL = URL(string: "https://api.luego.test")!
    private let bypassingLocalCache = "\(URLRequest.CachePolicy.reloadIgnoringLocalCacheData.rawValue)"

    @Test
    func sdkRequestsBypassResponsesTheServerAllowsCachingForAYear() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CachePolicyEchoFixture.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let dataSource = LuegoSDKDataSource(baseURL: baseURL, apiKey: "key", timeout: 5, userAgent: "Luego/test", session: session)

        let versionsPolicy = try await dataSource.fetchVersions().rules.version
        let bundlePolicy = String(decoding: try await dataSource.downloadBundle(name: "parser"), as: UTF8.self)
        let rulesPolicy = String(decoding: try await dataSource.fetchRules(), as: UTF8.self)

        #expect(versionsPolicy == bypassingLocalCache)
        #expect(bundlePolicy == bypassingLocalCache)
        #expect(rulesPolicy == bypassingLocalCache)
    }
}

private nonisolated final class CachePolicyEchoFixture: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let policy = "\(request.cachePolicy.rawValue)"
        let body = request.url?.lastPathComponent == "versions" ? versionsResponse(rulesVersion: policy) : Data(policy.utf8)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private func versionsResponse(rulesVersion: String) -> Data {
        let response: [String: Any] = ["bundles": [String: Any](), "rules": ["version": rulesVersion]]
        return (try? JSONSerialization.data(withJSONObject: response)) ?? Data()
    }
}
