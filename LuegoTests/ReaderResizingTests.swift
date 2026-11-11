import SwiftUI
import Testing
import UIKit

@MainActor
struct ReaderResizingTests {
    @Test
    func aLoadedPhotoFitsTheReaderAfterItNarrows() async throws {
        let loads = PhotoLoads()
        let document = try ReaderDocument(
            markdown: "First paragraph.\n\n![A photo](https://example.com/photo.jpg)\n\nSecond paragraph.",
            baseURL: URL(string: "https://example.com")!
        )
        let host = PageHost(
            ScrollView {
                ReaderBlocksView(document: document, imageLoader: WideImageLoader(loads: loads))
                    .readerContentStyle()
                    .padding(.horizontal, 40)
                    .frame(maxWidth: .infinity)
            }
        )
        defer { host.close() }
        await host.settle { loads.completed > 0 }
        let scroll = try #require(host.scrollView)

        host.resize(width: 844)
        await host.settle { scroll.contentSize.width > 800 }
        host.resize(width: 390)
        await host.settle { scroll.contentSize.width <= 390 }

        #expect(scroll.contentSize.width <= host.view.bounds.width)
    }
}

@MainActor
private final class PhotoLoads {
    var completed = 0
}

private struct WideImageLoader: ReaderImageLoading {
    let loads: PhotoLoads

    func image(for url: URL) async throws -> ReaderImage {
        let context = CGContext(data: nil, width: 1200, height: 800, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        await MainActor.run { loads.completed += 1 }
        return ReaderImage(frames: [context.makeImage()!], size: CGSize(width: 1200, height: 800), frameDurations: [0.1], loopCount: 0)
    }
}
