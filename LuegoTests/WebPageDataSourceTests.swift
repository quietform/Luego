import Foundation
import Testing

@MainActor
struct WebPageDataSourceTests {
    @Test
    func uppercaseHTTPSPreservesHostAndPath() async throws {
        let source = WebPageDataSource()
        let url = try await source.validateURL(URL(string: "HTTPS://example.com/Article?q=MixedCase")!)

        #expect(url.absoluteString == "https://example.com/Article?q=MixedCase")
    }
}
