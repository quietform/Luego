import Foundation
import ImageIO
import Testing
import UIKit
import UniformTypeIdentifiers

@MainActor
struct ReaderImageDecoderTests {
    @Test
    func animationKeepsItsFramesWithinOneMemoryBudget() async throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1000, height: 1000), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1000, height: 1000))
        }
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, 20, nil))
        for _ in 0..<20 {
            CGImageDestinationAddImage(destination, try #require(image.cgImage), [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]
            ] as CFDictionary)
        }
        try #require(CGImageDestinationFinalize(destination))
        let result = try await ReaderImageDecoder.decode(data as Data)

        #expect(result.frames.count == 20)
        let decodedBytes = result.frames.reduce(0) { $0 + $1.bytesPerRow * $1.height }
        #expect(decodedBytes <= 24 * 1024 * 1024)
    }

    @Test(arguments: [false, true])
    func largePhotoUsesDisplaySizedPixels(cancelled: Bool) async throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let data = UIGraphicsImageRenderer(size: CGSize(width: 2000, height: 3418), format: format)
            .jpegData(withCompressionQuality: 0.8) { context in
                UIColor.blue.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 2000, height: 3418))
            }
        let decoding = Task {
            if cancelled { withUnsafeCurrentTask { $0?.cancel() } }
            return try await ReaderImageDecoder.decode(data)
        }
        let result = try await decoding.value
        let image = try #require(result.frames.first)

        #expect(max(image.width, image.height) <= 1200)
        #expect(image.bytesPerRow * image.height <= 1200 * 1200 * 4)
        #expect(abs(Double(image.width) / Double(image.height) - 2000.0 / 3418.0) < 0.002)
        #expect(result.size == CGSize(width: 2000, height: 3418))
    }
}
