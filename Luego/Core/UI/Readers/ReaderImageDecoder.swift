import Foundation
import ImageIO

nonisolated struct ReaderImage: Sendable, Hashable {
    let frames: [CGImage]
    let size: CGSize
    let frameDurations: [TimeInterval]
    let loopCount: Int
}

enum ReaderImageDecoder {
    @concurrent
    static func decode(_ data: Data) async throws -> ReaderImage {
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else {
            throw URLError(.cannotDecodeContentData)
        }
        let count = CGImageSourceGetCount(source)
        let pixelLimit = min(1200, max(1, Int(sqrt(Double(24 * 1024 * 1024) / Double(max(count, 1) * 8)))))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: pixelLimit,
            kCGImageSourceShouldCacheImmediately: true
        ]
        var frames: [CGImage] = []
        var durations: [TimeInterval] = []
        for index in 0..<count {
            try Task.checkCancellation()
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else {
                throw URLError(.cannotDecodeContentData)
            }
            frames.append(image)
            let frameProperties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] ?? [:]
            let animation = animationProperties(frameProperties)
            let delay = animation["UnclampedDelayTime"] as? Double ?? animation["DelayTime"] as? Double ?? 0.1
            durations.append(delay > 0.01 ? delay : 0.1)
        }
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        let size = (5...8).contains(orientation)
            ? CGSize(width: height, height: width)
            : CGSize(width: width, height: height)
        let globalProperties = CGImageSourceCopyProperties(source, nil) as? [CFString: Any] ?? [:]
        return ReaderImage(
            frames: frames,
            size: size,
            frameDurations: durations,
            loopCount: animationProperties(globalProperties)["LoopCount"] as? Int ?? 0
        )
    }

    private nonisolated static func animationProperties(_ properties: [CFString: Any]) -> [String: Any] {
        for key in [kCGImagePropertyGIFDictionary, kCGImagePropertyPNGDictionary, kCGImagePropertyWebPDictionary, kCGImagePropertyHEICSDictionary] {
            if let animation = properties[key] as? [String: Any] { return animation }
        }
        return [:]
    }
}
