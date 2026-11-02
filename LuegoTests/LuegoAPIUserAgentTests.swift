import Foundation
import Testing

@MainActor
struct LuegoAPIUserAgentTests {
    private let baseURL = URL(string: "https://api.luego.test")!

    @Test
    func userAgentNamesTheAppVersionBuildAndSystem() {
        let userAgent = AppConfiguration.luegoAPIUserAgent(
            info: ["CFBundleShortVersionString": "2026.10.25", "CFBundleVersion": "7"],
            system: "iOS 26.1.0"
        )

        #expect(userAgent == "Luego/2026.10.25 (build 7; iOS 26.1.0)")
    }

    @Test
    func userAgentMarksMissingVersionsAsUnknown() {
        let userAgent = AppConfiguration.luegoAPIUserAgent(info: [:], system: "iOS 26.1.0")

        #expect(userAgent == "Luego/unknown (build unknown; iOS 26.1.0)")
    }

    @Test
    func articleRequestsIdentifyTheApp() async throws {
        try await withEchoSession { session in
            let dataSource = LuegoAPIDataSource(baseURL: baseURL, apiKey: "key", timeout: 5, userAgent: "Luego/test", session: session)

            let response = try await dataSource.fetchArticle(for: URL(string: "https://example.com/post")!)

            #expect(response.content == "Luego/test")
        }
    }

    @Test
    func sdkRequestsIdentifyTheApp() async throws {
        try await withEchoSession { session in
            let dataSource = LuegoSDKDataSource(baseURL: baseURL, apiKey: "key", timeout: 5, userAgent: "Luego/test", session: session)

            let bundle = try await dataSource.downloadBundle(name: "parser")

            #expect(String(decoding: bundle, as: UTF8.self) == "Luego/test")
        }
    }

    private func withEchoSession(operation: (URLSession) async throws -> Void) async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UserAgentEchoFixture.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        try await operation(session)
    }
}

private nonisolated final class UserAgentEchoFixture: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let userAgent = request.value(forHTTPHeaderField: "User-Agent") ?? ""
        let body = request.url?.path == "/api/luego/parse" ? articleResponse(content: userAgent) : Data(userAgent.utf8)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private func articleResponse(content: String) -> Data {
        let response: [String: Any] = [
            "content": content,
            "metadata": ["source_url": "https://example.com/post", "domain": "example.com"]
        ]
        return (try? JSONSerialization.data(withJSONObject: response)) ?? Data()
    }
}
