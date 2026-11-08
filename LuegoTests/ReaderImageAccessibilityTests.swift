import CoreGraphics
import SwiftUI
import Testing

@MainActor
struct ReaderImageAccessibilityTests {
    @Test(arguments: [
        ("Photo of Ratik in his halloween costume", ["Photo of Ratik in his halloween costume"]),
        ("", [])
    ])
    func voiceOverReadsAPhotoByItsDescription(description: String, expectedLabels: [String]) throws {
        let attachment = ReaderImageAttachment(description: description, image: try singlePixelImage())

        #expect(accessibilityLabels(in: attachment.body.frame(width: 100, height: 100)) == expectedLabels)
    }

    @Test(arguments: [
        ("Photo of Ratik in his halloween costume", [AccessibleElement.image("Photo of Ratik in his halloween costume")]),
        ("", [])
    ])
    func voiceOverReadsALoadingPhotoAsTheImageItWillBecome(description: String, expectedElements: [AccessibleElement]) {
        let placeholder = ReaderImagePlaceholder(description: description, height: 100)

        #expect(accessibleElements(in: placeholder.body.frame(width: 100, height: 100)) == expectedElements)
    }

    private func singlePixelImage() throws -> ReaderImage {
        let context = try #require(CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let image = try #require(context.makeImage())
        return ReaderImage(frames: [image], size: CGSize(width: 1, height: 1), frameDurations: [0.1], loopCount: 0)
    }
}
