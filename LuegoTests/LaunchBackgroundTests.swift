import Testing
import UIKit

struct LaunchBackgroundTests {
    @Test(arguments: [UIUserInterfaceStyle.light, .dark])
    func launchScreenMatchesTheAppBackground(style: UIUserInterfaceStyle) throws {
        try expectColorAsset(named: "LaunchBackground", matches: AppUIColor.appBackground, style: style)
    }
}
