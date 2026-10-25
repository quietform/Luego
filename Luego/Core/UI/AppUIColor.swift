import UIKit

enum AppUIColor {
    static let paperCream = UIColor(red: 252 / 255, green: 252 / 255, blue: 253 / 255, alpha: 1)
    static let brandPurple = UIColor(red: 223 / 255, green: 210 / 255, blue: 224 / 255, alpha: 1)
    static let brandPurpleInk = UIColor(red: 120 / 255, green: 98 / 255, blue: 125 / 255, alpha: 1)
    static let nightBackground = UIColor(red: 0x14 / 255.0, green: 0x15 / 255.0, blue: 0x19 / 255.0, alpha: 1)
    static let nightPanel = UIColor(red: 0x1b / 255.0, green: 0x1c / 255.0, blue: 0x22 / 255.0, alpha: 1)
    static let nightElevatedPanel = UIColor(red: 0x23 / 255.0, green: 0x24 / 255.0, blue: 0x2c / 255.0, alpha: 1)
    static let duskPurple = UIColor(red: 0xa0 / 255.0, green: 0x8e / 255.0, blue: 0xad / 255.0, alpha: 1)
    static let duskPurpleInk = UIColor(red: 0xe4 / 255.0, green: 0xda / 255.0, blue: 0xe8 / 255.0, alpha: 1)
    // Mirrored by the LaunchBackground color asset so the launch screen matches the first frame; LaunchBackgroundTests keeps them in sync.
    static let appBackground = adaptive(light: paperCream, dark: nightBackground)
    static let regularPanelBackground = adaptive(light: paperCream, dark: nightPanel)
    static let elevatedPanelBackground = adaptive(
        light: UIColor(red: 1, green: 1, blue: 1, alpha: 0.92),
        dark: nightElevatedPanel
    )
    static let mascotPurple = adaptive(light: brandPurple, dark: duskPurple)
    static let mascotPurpleInk = adaptive(light: brandPurpleInk, dark: duskPurpleInk)
    static let barAccentFill = adaptive(
        light: brandPurple.withAlphaComponent(0.72),
        dark: duskPurple.withAlphaComponent(0.56)
    )
    static let barAccentInk = adaptive(light: brandPurpleInk, dark: duskPurpleInk)
    static let regularSelectionFill = adaptive(
        light: brandPurple.withAlphaComponent(0.5),
        dark: duskPurple.withAlphaComponent(0.34)
    )
    static let regularSelectionInk = adaptive(light: brandPurpleInk, dark: duskPurpleInk)
    static let regularGlassTint = adaptive(
        light: brandPurple.withAlphaComponent(0.8),
        dark: duskPurple.withAlphaComponent(0.72)
    )
    static let readerBackground = adaptive(
        light: paperCream,
        dark: UIColor(red: 0x18 / 255.0, green: 0x19 / 255.0, blue: 0x1d / 255.0, alpha: 1)
    )

    private static func adaptive(light: UIColor, dark: UIColor) -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        }
    }
}
