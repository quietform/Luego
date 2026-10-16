import SwiftUI
import Testing
import Textual
import UIKit

@MainActor
@Suite(.serialized)
struct ReaderVisibilityTests {
    @Test
    func openingLongArticleLoadsOnlyNearbyImages() async throws {
        let counter = ImageLoadCounter()
        let markdown = (0..<100).map { "![Photo \($0)](https://example.com/\($0).jpg)" }.joined(separator: "\n\n")
        let document = try ReaderDocument(markdown: markdown, baseURL: URL(string: "https://example.com")!)
        let controller = UIHostingController(rootView:
            ScrollView {
                VStack {
                    Text("Article title")
                    ReaderBlocksView(document: document, imageLoader: CountingImageLoader(counter: counter))
                        .textual.imageAttachmentLoader(CountingImageLoader(counter: counter))
                }
            }
        )
        let window = UIWindow()
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        controller.view.layoutIfNeeded()
        for _ in 0..<30 {
            try await Task.sleep(for: .milliseconds(100))
            controller.view.layoutIfNeeded()
        }
        let count = await counter.count
        #expect(count > 0)
        #expect(count < 10)
    }
    @Test
    func scrollingAwayReleasesDecodedAttachments() async throws {
        let counter = ImageLoadCounter()
        let markdown = (0..<100).map { "![Photo \($0)](https://example.com/\($0).jpg)" }.joined(separator: "\n\n")
        let document = try ReaderDocument(markdown: markdown, baseURL: URL(string: "https://example.com")!)
        let controller = UIHostingController(rootView:
            ScrollView {
                VStack {
                    Text("Article title")
                    ReaderBlocksView(document: document, imageLoader: CountingImageLoader(counter: counter))
                        .textual.imageAttachmentLoader(CountingImageLoader(counter: counter))
                }
            }
        )
        let window = UIWindow()
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .seconds(2))
        let initialCount = await counter.count
        let scroll = try #require(findScrollView(controller.view))
        scroll.setContentOffset(CGPoint(x: 0, y: 6000), animated: false)
        for _ in 0..<20 {
            try await Task.sleep(for: .milliseconds(100))
            controller.view.layoutIfNeeded()
        }
        let count = await counter.count
        let released = await counter.released
        #expect(count > initialCount)
        #expect(released > 0)
        #expect(count - released < 12)
        scroll.setContentOffset(.zero, animated: false)
        for _ in 0..<20 {
            try await Task.sleep(for: .milliseconds(100))
            controller.view.layoutIfNeeded()
        }
        #expect(await counter.count > count)
        #expect(await counter.count - counter.released < 12)
    }

    @Test
    func replacingArticleReloadsItsImages() async throws {
        let counter = ImageLoadCounter()
        func content(_ document: ReaderDocument) -> some View {
            ScrollView {
                ReaderBlocksView(document: document, imageLoader: CountingImageLoader(counter: counter))
                    .textual.imageAttachmentLoader(CountingImageLoader(counter: counter))
            }
        }
        let first = try ReaderDocument(markdown: "![First](https://example.com/first.jpg)", baseURL: URL(string: "https://example.com")!)
        let controller = UIHostingController(rootView: content(first))
        let window = UIWindow()
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .seconds(1))
        let second = try ReaderDocument(markdown: "![Second](https://example.com/second.jpg)", baseURL: URL(string: "https://example.com")!)
        controller.rootView = content(second)
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .seconds(1))
        #expect(await counter.urls.contains(URL(string: "https://example.com/second.jpg")!))
    }

    @Test
    func loadsImagesOneScreenAheadBeforeTheyBecomeVisible() async throws {
        let counter = ImageLoadCounter()
        let markdown = (0..<100).map { "![Photo \($0)](https://example.com/\($0).jpg)" }.joined(separator: "\n\n")
        let document = try ReaderDocument(markdown: markdown, baseURL: URL(string: "https://example.com")!)
        let controller = UIHostingController(rootView:
            ScrollView {
                ReaderBlocksView(document: document, imageLoader: CountingImageLoader(counter: counter))
                    .textual.imageAttachmentLoader(CountingImageLoader(counter: counter))
            }
        )
        let window = UIWindow()
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .seconds(2))
        let urls = await counter.urls
        #expect(urls.contains(URL(string: "https://example.com/4.jpg")!))
        #expect(!urls.contains(URL(string: "https://example.com/8.jpg")!))
    }

    @Test
    func retainsLoadedImagesUntilTheyAreTwoScreensAway() async throws {
        let counter = ImageLoadCounter()
        let markdown = (0..<100).map { "![Photo \($0)](https://example.com/\($0).jpg)" }.joined(separator: "\n\n")
        let document = try ReaderDocument(markdown: markdown, baseURL: URL(string: "https://example.com")!)
        let controller = UIHostingController(rootView:
            ScrollView {
                ReaderBlocksView(document: document, imageLoader: CountingImageLoader(counter: counter))
                    .textual.imageAttachmentLoader(CountingImageLoader(counter: counter))
            }
        )
        let window = UIWindow()
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .seconds(2))
        let scroll = try #require(findScrollView(controller.view))
        let first = URL(string: "https://example.com/0.jpg")!
        scroll.setContentOffset(CGPoint(x: 0, y: 1600), animated: false)
        try await Task.sleep(for: .seconds(1))
        #expect(!(await counter.releasedURLs).contains(first))
        scroll.setContentOffset(CGPoint(x: 0, y: 2300), animated: false)
        try await Task.sleep(for: .seconds(1))
        #expect(await counter.releasedURLs.contains(first))
    }

    @Test
    func textOnlyBlocksKeepTheirLayoutWhenOffscreen() async throws {
        let markdown = (0..<100).map { "Paragraph \($0)" }.joined(separator: "\n\n")
        let document = try ReaderDocument(markdown: markdown, baseURL: URL(string: "https://example.com")!)
        let controller = UIHostingController(rootView: ScrollView { ReaderBlocksView(document: document) })
        let window = UIWindow()
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .seconds(2))
        let scroll = try #require(findScrollView(controller.view))
        let height = scroll.contentSize.height
        #expect(height < 10000)
        scroll.setContentOffset(CGPoint(x: 0, y: 2500), animated: false)
        try await Task.sleep(for: .seconds(1))
        #expect(abs(scroll.contentSize.height - height) < 1)
    }

    @Test
    func reloadingTallImagePreservesItsMeasuredHeight() async throws {
        let counter = ImageLoadCounter()
        let markdown = "![Tall photo](https://example.com/tall.jpg)\n\n" + (0..<100).map { "Paragraph \($0)" }.joined(separator: "\n\n")
        let document = try ReaderDocument(markdown: markdown, baseURL: URL(string: "https://example.com")!)
        let controller = UIHostingController(rootView:
            ScrollView {
                ReaderBlocksView(document: document, imageLoader: CountingImageLoader(counter: counter, height: 800, reloadDelay: .seconds(1)))
                    .textual.imageAttachmentLoader(CountingImageLoader(counter: counter, height: 800, reloadDelay: .seconds(1)))
            }
        )
        let window = UIWindow()
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .seconds(2))
        let scroll = try #require(findScrollView(controller.view))
        let height = scroll.contentSize.height
        scroll.setContentOffset(CGPoint(x: 0, y: 3000), animated: false)
        try await Task.sleep(for: .seconds(1))
        let released = await counter.released
        #expect(released > 0)
        #expect(released == (await counter.count))
        scroll.setContentOffset(.zero, animated: false)
        try await Task.sleep(for: .milliseconds(300))
        #expect(abs(scroll.contentSize.height - height) < 1)
        try await Task.sleep(for: .seconds(1))
        #expect(abs(scroll.contentSize.height - height) < 1)
    }

    private func findScrollView(_ view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView { return scroll }
        return view.subviews.lazy.compactMap(findScrollView).first
    }

}

private actor ImageLoadCounter {
    var count = 0
    private var attachmentReleases: [URL] = []
    private var images: [(URL, WeakReaderImage)] = []
    var released: Int { releasedURLs.count }
    var urls: [URL] = []
    var releasedURLs: [URL] { attachmentReleases + images.filter { $0.1.image == nil }.map { $0.0 } }
    func observe(_ image: CGImage, url: URL) { images.append((url, WeakReaderImage(image))) }
    func record(_ url: URL) -> Int { count += 1; urls.append(url); return urls.filter { $0 == url }.count }
    func release(_ url: URL) { attachmentReleases.append(url) }
}

private struct CountingImageLoader: AttachmentLoader, ReaderImageLoading {
    let counter: ImageLoadCounter
    var height: CGFloat = 300
    var reloadDelay: Duration = .zero

    func image(for url: URL) async throws -> ReaderImage {
        let attempt = await counter.record(url)
        if attempt > 1 { try await Task.sleep(for: reloadDelay) }
        let context = CGContext(data: nil, width: 390, height: Int(height), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image = context.makeImage()!
        await counter.observe(image, url: url)
        return ReaderImage(frames: [image], size: CGSize(width: 390, height: height), frameDurations: [0.1], loopCount: 0)
    }

    func attachment(for url: URL, text: String, environment: ColorEnvironmentValues) async throws -> TestImageAttachment {
        let attempt = await counter.record(url)
        if attempt > 1 { try await Task.sleep(for: reloadDelay) }
        return TestImageAttachment(description: text, token: ImageLifetimeToken(counter: counter, url: url), height: height)
    }
}

private struct TestImageAttachment: Textual.Attachment {
    let description: String
    let token: ImageLifetimeToken
    var height: CGFloat = 300
    var body: some View { Color.blue }
    func sizeThatFits(_ proposal: ProposedViewSize, in environment: TextEnvironmentValues) -> CGSize {
        CGSize(width: proposal.width ?? 300, height: height)
    }
}

private nonisolated final class ImageLifetimeToken: Sendable, Hashable {
    let counter: ImageLoadCounter
    let url: URL
    init(counter: ImageLoadCounter, url: URL) { self.counter = counter; self.url = url }
    deinit {
        let counter = counter
        let url = url
        Task { await counter.release(url) }
    }
    static func == (lhs: ImageLifetimeToken, rhs: ImageLifetimeToken) -> Bool { lhs === rhs }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}

private nonisolated final class WeakReaderImage {
    weak var image: CGImage?
    init(_ image: CGImage) { self.image = image }
}
