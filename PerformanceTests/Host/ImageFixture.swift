import CryptoKit
import Foundation
import os
import Synchronization

nonisolated enum ImageFixture {
    private static let counters = Mutex(Counters())

    static func install() {
        URLCache.shared = URLCache(memoryCapacity: 64 * 1024 * 1024, diskCapacity: 0)
        precondition(URLProtocol.registerClass(ImageFixtureProtocol.self))
    }

    @concurrent
    static func prepare() async throws -> String {
        let manifestURL = Bundle.main.url(forResource: "ImageFixtureManifest", withExtension: "json")!
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
        let warm = ProcessInfo.processInfo.arguments.contains("--benchmark-images-warm")
        URLCache.shared.removeAllCachedResponses()
        for photo in manifest.images {
            let data = try Data(contentsOf: Bundle.main.url(forResource: String(photo.name.dropLast(4)), withExtension: "jpg")!)
            let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard hash == photo.sha256 else { throw URLError(.cannotDecodeContentData) }
            if warm {
                let url = URL(string: "https://images.fixture.invalid/\(photo.name)")!
                URLCache.shared.storeCachedResponse(CachedURLResponse(response: response(for: url), data: data), for: URLRequest(url: url))
            }
        }
        counters.withLock {
            $0.warm = warm
            $0.primed = warm ? manifest.images.count : 0
        }
        return "FIXTURE_START Fixed offline photographs use the production reader and image decoder.\n\n" + manifest.images.enumerated().map { index, photo in
            "## Photo \(index + 1)\n\n![IMAGE_FIXTURE_\(String(format: "%03d", index + 1))](https://images.fixture.invalid/\(photo.name))\n\nThe next photograph uses the same reader layout, loading and visibility rules."
        }.joined(separator: "\n\n") + "\n\nFIXTURE_END"
    }

    static var status: String {
        counters.withLock { "\($0.warm ? "warm" : "cold")|\($0.primed)|\($0.requests)|\($0.duringScroll)|\($0.failures)|\($0.bytes)|\($0.cacheHits)|\($0.cacheHitsDuringScroll)" }
    }

    static func scrolling(_ active: Bool) {
        counters.withLock {
            if active {
                $0.startReads = $0.duringScroll
                $0.startHits = $0.cacheHitsDuringScroll
            } else {
                $0.scrolls.append("\($0.duringScroll - $0.startReads):\($0.cacheHitsDuringScroll - $0.startHits)")
            }
            $0.scrolling = active
        }
    }

    static var scrolls: String {
        counters.withLock { $0.scrolls.joined(separator: ";") }
    }

    static func beganRequest() {
        counters.withLock {
            $0.requests += 1
            if $0.scrolling { $0.duringScroll += 1 }
        }
    }

    static func finished(bytes: Int) {
        counters.withLock { $0.bytes += bytes }
    }

    static func hitCache() {
        counters.withLock {
            $0.cacheHits += 1
            if $0.scrolling { $0.cacheHitsDuringScroll += 1 }
        }
    }

    static func failed() {
        counters.withLock { $0.failures += 1 }
    }

    static func response(for url: URL) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "image/jpeg", "Cache-Control": "public, max-age=3600"])!
    }

    private struct Counters {
        var requests = 0
        var warm = false
        var primed = 0
        var duringScroll = 0
        var failures = 0
        var bytes = 0
        var scrolling = false
        var cacheHits = 0
        var cacheHitsDuringScroll = 0
        var startReads = 0
        var startHits = 0
        var scrolls: [String] = []
    }

    private struct Manifest: Decodable {
        let images: [Photo]
    }

    private struct Photo: Decodable {
        let name: String
        let sha256: String
    }
}

private nonisolated final class ImageFixtureProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "images.fixture.invalid"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        precondition(!Thread.isMainThread)
        let interval = BenchmarkSignposts.signposter.beginInterval("FixtureImageResponse", id: BenchmarkSignposts.signposter.makeSignpostID())
        defer { BenchmarkSignposts.signposter.endInterval("FixtureImageResponse", interval) }
        if let cached = URLCache.shared.cachedResponse(for: request) {
            ImageFixture.hitCache()
            client?.urlProtocol(self, didReceive: cached.response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: cached.data)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        ImageFixture.beganRequest()
        do {
            let url = request.url!
            guard let file = Bundle.main.url(forResource: url.deletingPathExtension().lastPathComponent, withExtension: "jpg") else { throw URLError(.fileDoesNotExist) }
            let data = try Data(contentsOf: file)
            client?.urlProtocol(self, didReceive: ImageFixture.response(for: url), cacheStoragePolicy: .allowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
            ImageFixture.finished(bytes: data.count)
        } catch {
            ImageFixture.failed()
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
