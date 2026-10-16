import Testing
import UIKit

@MainActor
struct AppTypographyTests {
    @Test(arguments: ["lora", "nunito"], [
        UIContentSizeCategory.small,
        .large,
        .extraExtraExtraLarge,
        .accessibilityExtraExtraExtraLarge
    ])
    func bodyFontScalesOnceFromSeventeenPoints(family: String, category: UIContentSizeCategory) {
        let traits = UITraitCollection(preferredContentSizeCategory: category)
        let expectedSize = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: UIFont.systemFont(ofSize: 17),
            compatibleWith: traits
        ).pointSize

        let font = family == "lora"
            ? UIFont.lora(forTextStyle: .body, scalesWithDynamicType: true, compatibleWith: traits)
            : UIFont.nunito(forTextStyle: .body, scalesWithDynamicType: true, compatibleWith: traits)

        #expect(abs(font.pointSize - expectedSize) < 0.01, "Font: \(font.pointSize), expected: \(expectedSize)")
    }
}
