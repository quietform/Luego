import Testing
import UIKit

struct AccentColorTests {
    @Test(arguments: [UIUserInterfaceStyle.light, .dark])
    func everyLayoutInheritsTheBrandInk(style: UIUserInterfaceStyle) throws {
        try expectColorAsset(named: "AccentColor", matches: AppUIColor.regularSelectionInk, style: style)
    }
}
