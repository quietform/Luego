import Foundation
import Testing
import UIKit

func expectColorAsset(
    named name: String,
    matches appColor: UIColor,
    style: UIUserInterfaceStyle,
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    let assetComponents = try #require(
        try colorAssetComponents(named: name)[style],
        "\(name) has no \(style == .dark ? "dark" : "light") color",
        sourceLocation: sourceLocation
    )
    let appComponents = components(of: appColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: style)))

    for (asset, app) in zip(assetComponents, appComponents) {
        #expect(abs(asset - app) < 0.5 / 255, "\(name): \(assetComponents), app: \(appComponents)", sourceLocation: sourceLocation)
    }
}

private func components(of color: UIColor) -> [CGFloat] {
    var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
    color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    return [red, green, blue, alpha]
}

private func colorAssetComponents(named name: String) throws -> [UIUserInterfaceStyle: [CGFloat]] {
    let url = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .appending(path: "../Luego/Assets.xcassets/\(name).colorset/Contents.json")
    let asset = try JSONDecoder().decode(ColorSet.self, from: Data(contentsOf: url))
    return Dictionary(uniqueKeysWithValues: asset.colors.compactMap { entry in
        guard let components = entry.color?.components else { return nil }
        let isDark = entry.appearances?.contains { $0.value == "dark" } ?? false
        let values = [components.red, components.green, components.blue, components.alpha].map(componentValue)
        return (isDark ? UIUserInterfaceStyle.dark : .light, values)
    })
}

private func componentValue(_ component: String) -> CGFloat {
    if component.hasPrefix("0x"), let byte = Int(component.dropFirst(2), radix: 16) {
        return CGFloat(byte) / 255
    }
    return CGFloat(Double(component) ?? .nan)
}

private struct ColorSet: Decodable {
    let colors: [Entry]

    struct Entry: Decodable {
        let appearances: [Appearance]?
        let color: Color?
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
