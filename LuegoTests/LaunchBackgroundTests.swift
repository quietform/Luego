import Foundation
import Testing
import UIKit

struct LaunchBackgroundTests {
    @Test(arguments: [UIUserInterfaceStyle.light, .dark])
    func launchScreenMatchesTheAppBackground(style: UIUserInterfaceStyle) throws {
        let launchColor = try #require(try launchBackgroundComponents()[style])
        let appColor = AppUIColor.appBackground.resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        appColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        for (launch, app) in zip(launchColor, [red, green, blue, alpha]) {
            #expect(abs(launch - app) < 0.5 / 255, "Launch: \(launchColor), app: \([red, green, blue, alpha])")
        }
    }

    private func launchBackgroundComponents() throws -> [UIUserInterfaceStyle: [CGFloat]] {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "../Luego/Assets.xcassets/LaunchBackground.colorset/Contents.json")
        let asset = try JSONDecoder().decode(ColorSet.self, from: Data(contentsOf: url))
        return Dictionary(uniqueKeysWithValues: asset.colors.map { entry in
            let isDark = entry.appearances?.contains { $0.value == "dark" } ?? false
            let components = entry.color.components
            return (isDark ? .dark : .light, [components.red, components.green, components.blue, components.alpha].map(Self.value))
        })
    }

    private static func value(of component: String) -> CGFloat {
        if component.hasPrefix("0x"), let byte = Int(component.dropFirst(2), radix: 16) {
            return CGFloat(byte) / 255
        }
        return CGFloat(Double(component) ?? .nan)
    }

    private struct ColorSet: Decodable {
        let colors: [Entry]

        struct Entry: Decodable {
            let appearances: [Appearance]?
            let color: Color
        }

        struct Appearance: Decodable {
            let value: String
        }

        struct Color: Decodable {
            let components: Components
        }

        struct Components: Decodable {
            let red: String
            let green: String
            let blue: String
            let alpha: String
        }
    }
}
