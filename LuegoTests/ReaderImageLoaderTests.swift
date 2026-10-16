import Foundation
import Testing
import UIKit

@MainActor
struct ReaderImageLoaderTests {
    @Test
    func downloadedPhotoIsDownsampledBeforeDisplay() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ImageFixtureProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let image = try await ReaderImageLoader(session: session).image(for: URL(string: "https://example.com/photo")!)
        #expect(image.frames.count == 1)
        #expect(image.frames[0].width == 1200)
        #expect(image.size == CGSize(width: 2000, height: 2000))
    }
    @Test
    func failedDownloadDoesNotDisplayAnErrorResponseAsAnImage() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ImageFixtureProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        await #expect(throws: URLError(.badServerResponse)) {
            try await ReaderImageLoader(session: session).image(for: URL(string: "https://example.com/missing")!)
        }
    }

}

private nonisolated final class ImageFixtureProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Task { @MainActor in
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let data = UIGraphicsImageRenderer(size: CGSize(width: 2000, height: 2000), format: format).pngData { context in
                UIColor.blue.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 2000, height: 2000))
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: request.url?.path == "/missing" ? 404 : 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}
