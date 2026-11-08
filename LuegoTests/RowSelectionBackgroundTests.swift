import SwiftUI
import Testing
import UIKit

@MainActor
struct RowSelectionBackgroundTests {
    @Test(arguments: [ColorScheme.light, .dark])
    func selectedRowsFillWithTheBrandSelection(colorScheme: ColorScheme) throws {
        let style: UIUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        let expected = AppUIColor.regularSelectionFill.resolvedColor(with: UITraitCollection(userInterfaceStyle: style))

        let pixel = try centerPixel(of: RowSelectionBackground(isSelected: true), colorScheme: colorScheme)

        for (rendered, wanted) in zip(pixel, components(of: expected)) {
            #expect(abs(rendered - wanted) < 2 / 255, "Rendered: \(pixel), expected: \(components(of: expected))")
        }
    }

    @Test
    func unselectedRowsLetTheListBackgroundShowThrough() throws {
        let pixel = try centerPixel(of: RowSelectionBackground(isSelected: false).background(Color.black), colorScheme: .light)

        #expect(pixel == [0, 0, 0, 1])
    }

    private func centerPixel(of view: some View, colorScheme: ColorScheme) throws -> [CGFloat] {
        let renderer = ImageRenderer(content: view.frame(width: 100, height: 60).environment(\.colorScheme, colorScheme))
        let image = try #require(renderer.cgImage)
        var bytes = [UInt8](repeating: 0, count: 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(
                data: buffer.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(image, in: CGRect(x: -CGFloat(image.width) / 2, y: -CGFloat(image.height) / 2, width: CGFloat(image.width), height: CGFloat(image.height)))
        }
        let alpha = CGFloat(bytes[3]) / 255
        guard alpha > 0 else { return [0, 0, 0, 0] }
        return bytes[0..<3].map { CGFloat($0) / 255 / alpha } + [alpha]
    }

    private func components(of color: UIColor) -> [CGFloat] {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return [red, green, blue, alpha]
    }
}
