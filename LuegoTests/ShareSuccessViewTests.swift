import SwiftUI
import Testing
import UIKit

@MainActor
struct ShareSuccessViewTests {
    @Test(arguments: [UIUserInterfaceStyle.light, .dark])
    func dismissButtonUsesSharedControlFill(style: UIUserInterfaceStyle) throws {
        let view = SuccessView()
        let button = try #require(view.subviews.compactMap { $0 as? UIButton }.first)
        let traits = UITraitCollection(userInterfaceStyle: style)
        let expected = UIColor(Color.mascotPurple).resolvedColor(with: traits)

        #expect(button.backgroundColor?.resolvedColor(with: traits) == expected)
    }

    @Test(arguments: [UIUserInterfaceStyle.light, .dark])
    func dismissButtonTextRemainsReadable(style: UIUserInterfaceStyle) throws {
        let view = SuccessView()
        let button = try #require(view.subviews.compactMap { $0 as? UIButton }.first)
        let traits = UITraitCollection(userInterfaceStyle: style)
        let background = try #require(button.backgroundColor).resolvedColor(with: traits)
        let foreground = try #require(button.titleColor(for: .normal)).resolvedColor(with: traits)
        let backgroundLuminance = try luminance(of: background)
        let foregroundLuminance = try luminance(of: foreground)
        let contrast = (max(backgroundLuminance, foregroundLuminance) + 0.05)
            / (min(backgroundLuminance, foregroundLuminance) + 0.05)

        #expect(contrast >= 4.5)
    }

    private func luminance(of color: UIColor) throws -> Double {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        try #require(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        let components = [red, green, blue].map { value in
            value <= 0.04045 ? Double(value) / 12.92 : pow((Double(value) + 0.055) / 1.055, 2.4)
        }
        return components[0] * 0.2126 + components[1] * 0.7152 + components[2] * 0.0722
    }
}
